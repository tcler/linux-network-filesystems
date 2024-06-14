#!/usr/bin/env bash
#

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#export share dir by nfs
nfsmp=/mnt/nfsmp
script_dir=$(readlink -f $(dirname $0))

#create nfs-server vm
distro=${1:-9}; shift
vmserv=nfs-server
vmclnt=nfs-client
trun -tmux vm create $distro -n $vmserv -f -nointeract -p nfs-utils,wireshark,tmux "$@"
trun       vm create $distro -n $vmclnt -f -nointeract -p nfs-utils,wireshark,tmux "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm -v cpto $vmserv /usr/bin/make-nfs-server.sh /usr/bin/.
vm -v exec $vmserv -- make-nfs-server.sh --no-tlshd
vm -v exec $vmserv -- mkdir -p /nfsshare/rw/testdir
vm -v exec $vmserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $vmserv)
NIC=any  #$(vmrunx - $vmserv -- nmcli -g DEVICE connection show|sed -n '2p;q')
pcapf=nfs.pcap

vmrunx - $vmclnt -- showmount -e $servaddr
vmrunx - $vmclnt -- mkdir -p $nfsmp
vmrunx - $vmclnt -- mount -overs=3 $servaddr:/nfsshare/rw $nfsmp
vmrunx - $vmclnt -- mount -t nfs,nfs4
vmrunx - $vmclnt -- "touch $pcapf; tmux new -d 'tshark -i $NIC -w ${pcapf}'"
vmrunx - $vmclnt -- ls -l $nfsmp $nfsmp/testdir
vmrunx - $vmclnt -- sleep 2
vmrunx - $vmclnt -- pkill tshark
vmrunx - $vmclnt -- "tshark -i $NIC -Y nfs -r $pcapf -T fields -e nfs.fhandle -f 'nfs.name == testdir'|grep -E '^.{80}$'|sort -u|tee fhlist.txt"
trun maxblksize=$(vm exec $vmserv -- cat /proc/fs/nfsd/max_block_size)
vm -v cpto $vmclnt "${script_dir}/nfsv3-read.py" .
trun fh1=$(vm exec $vmclnt -- head -1 fhlist.txt)
trun "fhlist='$(vm exec $vmclnt -- cat fhlist.txt)'"
vmrunx - $vmclnt -- "./nfsv3-read.py $servaddr readdirplus $maxblksize $fh1 -s | grep nfs.status3.=.0"
	xrc 0 "output of test log should include 'nfs.status3 = 0'"
