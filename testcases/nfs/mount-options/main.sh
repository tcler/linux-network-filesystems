#!/usr/bin/env bash
#

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#export share dir by nfs
nfsmp=/mnt/nfsmp

#create nfs-server vm
distro=${1:-9}; shift
vmserv=nfs-server
vmclnt=nfs-client
trun -tmux vm create $distro -n $vmserv -f -nointeract -p 'nfs-utils wireshark tmux' "$@"
trun       vm create $distro -n $vmclnt -f -nointeract -p 'nfs-utils wireshark tmux' "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $vmserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

vm -v cpto $vmserv /usr/bin/make-nfs-server.sh .
vm -v exec $vmserv -- bash make-nfs-server.sh
vm -v exec $vmserv -- mkdir -p /nfsshare/rw/testdir
vm -v exec $vmserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $vmserv|head -1)
pcapf=nfs.pcap

vmrunx 0 $vmclnt -- showmount -e $servaddr
vmrunx 0 $vmclnt -- mkdir -p $nfsmp
vmrunx 0 $vmclnt -- "mount $servaddr:/nfsshare/rw $nfsmp || mount -vvv $servaddr:/nfsshare/rw $nfsmp"
vmrunx 0 $vmclnt -- umount $nfsmp

#Test1: softreval
vmrunx - $vmclnt -- mount -osoftreval $servaddr:/nfsshare/rw $nfsmp
vmrunx - $vmclnt -- mount -t nfs,nfs4
vmrunx - $vmclnt -- ls -l $nfsmp $nfsmp/testdir
vmrunx - $vmserv -- systemctl stop nfs-server
#should umount success even nfs-server stop
vmrunx 0 $vmclnt -- umount $nfsmp
vmrunx - $vmserv -- systemctl start nfs-server
