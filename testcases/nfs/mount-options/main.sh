#!/usr/bin/env bash
#

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#export share dir by nfs
nfsmp=/mnt/nfsmp
NFSSHARE=/var/nfsshare

#create nfs-server vm
distro=${1:-9}; shift
nfsserv=nfs-server
nfsclnt=nfs-client
trun -tmux vm create $distro -n $nfsserv -f -nointeract -p 'nfs-utils wireshark tmux' "$@"
trun       vm create $distro -n $nfsclnt -f -nointeract -p 'nfs-utils wireshark tmux' "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $nfsserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

vm -v cpto $nfsserv /usr/bin/make-nfs-server.sh .
vm -v exec $nfsserv -- bash make-nfs-server.sh --prefix=$NFSSHARE
vm -v exec $nfsserv -- mkdir -p $NFSSHARE/rw/testdir
vm -v exec $nfsserv -- touch $NFSSHARE/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv|head -1)
pcapf=nfs.pcap

_test=mount-options
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
vmrunx - $nfsclnt -- uname -r;
vmrunx - $nfsclnt -- rpm -q nfs-utils;

vmrunx 0 $nfsclnt -- showmount -e $servaddr
vmrunx 0 $nfsclnt -- mkdir -p $nfsmp
vmrunx 0 $nfsclnt -- "mount $servaddr:$NFSSHARE/rw $nfsmp || mount -vvv $servaddr:$NFSSHARE/rw $nfsmp"
vmrunx 0 $nfsclnt -- umount $nfsmp

#Test1: softreval
vmrunx 0 $nfsclnt -- mount -osoftreval $servaddr:$NFSSHARE/rw $nfsmp
vmrunx 0 $nfsclnt -- mount -t nfs,nfs4
vmrunx 0 $nfsclnt -- ls -l $nfsmp $nfsmp/testdir
vmrunx - $nfsserv -- systemctl stop nfs-server
#should umount success even nfs-server stop
sleep 1
vmrunx 0:"umount success even nfs-server stop" $nfsclnt -- umount $nfsmp
vmrunx - $nfsserv -- systemctl start nfs-server
} &> >(tee $resdir/std.log)

tcnt
