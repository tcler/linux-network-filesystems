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

vm -v cpto $vmserv /usr/bin/make-nfs-server.sh .
vm -v exec $vmserv -- bash make-nfs-server.sh
vm -v exec $vmserv -- mkdir -p /nfsshare/rw/testdir
vm -v exec $vmserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $vmserv)
pcapf=nfs.pcap

vm exec -vx $vmclnt -- showmount -e $servaddr
vm exec -vx $vmclnt -- mkdir -p $nfsmp
vm exec -vx $vmclnt -- "mount $servaddr:/nfsshare/rw $nfsmp || mount -vvv $servaddr:/nfsshare/rw $nfsmp"
vm exec -vx $vmclnt -- umount $nfsmp

#Test1: softreval
vm exec -v $vmclnt -- mount -osoftreval $servaddr:/nfsshare/rw $nfsmp
vm exec -v $vmclnt -- mount -t nfs,nfs4
vm exec -v $vmclnt -- ls -l $nfsmp $nfsmp/testdir
vm exec -v $vmserv -- systemctl stop nfs-server
#should umount success even nfs-server stop
vm exec -vx $vmclnt -- umount $nfsmp
vm exec -v $vmserv -- systemctl start nfs-server
