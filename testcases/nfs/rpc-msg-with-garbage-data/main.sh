#!/usr/bin/env bash
#

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#export share dir by nfs
nfsmp=/mnt/nfsmp
script_dir=$(readlink -f $(dirname $0))

distro=${1:-9}; shift
nfsserv=nfs-server
nfsclnt=nfs-client

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

#create nfs-server vm
trun -tmux vm create $distro -n $nfsserv -f -nointeract -p nfs-utils,wireshark,tmux "$@"
trun       vm create $distro -n $nfsclnt -f -nointeract -p nfs-utils,wireshark,tmux "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
vm exec -v $nfsserv -- make-nfs-server.sh --no-tlshd
vm exec -v $nfsserv -- mkdir -p /nfsshare/rw/testdir
vm exec -v $nfsserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv|head -1)
vm cpto -v $nfsclnt /usr/bin/get-if-by-ip.sh /usr/bin/.
read clntaddr < <(vm ifaddr $nfsclnt | grep ${servaddr%.*})
NIC=$(vm exec $nfsclnt -- get-if-by-ip.sh $clntaddr)
pcapf=nfs.pcap

vmrunx - $nfsclnt -- showmount -e $servaddr
vmrunx - $nfsclnt -- mkdir -p $nfsmp
vmrunx - $nfsclnt -- mount -overs=3 $servaddr:/nfsshare/rw $nfsmp
vmrunx - $nfsclnt -- mount -t nfs,nfs4
vmrunx - $nfsclnt -- "touch $pcapf; tmux new -d 'tshark -i $NIC -w ${pcapf}'"
vmrunx - $nfsclnt -- ls -l $nfsmp $nfsmp/testdir
vmrunx - $nfsclnt -- sleep 2
vmrunx - $nfsclnt -- pkill tshark
vmrunx - $nfsclnt -- "tshark -i $NIC -Y nfs -r $pcapf -T fields -e nfs.fhandle -f 'nfs.name == testdir'|grep -E '^.{80}$'|sort -u|tee fhlist.txt"
trun maxblksize=$(vm exec $nfsserv -- cat /proc/fs/nfsd/max_block_size)
vm cpto -v $nfsclnt "${script_dir}/nfsv3-read.py" .
trun fh1=$(vm exec $nfsclnt -- head -1 fhlist.txt)
trun "fhlist='$(vm exec $nfsclnt -- cat fhlist.txt)'"
vmrunx - $nfsclnt -- "./nfsv3-read.py $servaddr readdirplus $maxblksize $fh1 -s | grep nfs.status3.=.0"
	xrc 0 "output of test log should include 'nfs.status3 = 0'"

stopvms
