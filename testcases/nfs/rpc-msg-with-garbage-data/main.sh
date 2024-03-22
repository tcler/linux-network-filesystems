#!/usr/bin/env bash
#

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#export share dir by nfs
_USER=$(whoami)
[[ $(id -u) = 0 && -n "$SUDO_USER" ]] && _USER=$SUDO_USER
nfsmp=/mnt/nfsmp
script_dir=$(readlink -f $(dirname $0))

#create nfs-server vm
distro=${1:-9}; shift
vmserv=nfs-server
vmclnt=nfs-client
trun vm create $distro -n $vmserv -f -nointeract -p 'nfs-utils wireshark tmux' "$@"
vm -v cpto $vmserv /usr/bin/make-nfs-server.sh .
vm -v exec $vmserv -- bash make-nfs-server.sh
vm -v exec $vmserv -- mkdir -p /nfsshare/rw/testdir
vm -v exec $vmserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $vmserv)
pcapf=nfs.pcap
NIC=$(vm exec -v $vmserv -- nmcli -g DEVICE connection show|head -1)

if true; then
	[[ $(id -u) != 0 ]] && {
		sudo -K
		while true; do
			read -s -p "sudo Password: " password
			echo
			echo "$password" | sudo -S ls / >/dev/null && break
		done
	}
	trun -as=root mkdir -p $nfsmp
	trun -as=root mount -overs=3 $servaddr:/nfsshare/rw $nfsmp
	trun mount -t nfs,nfs4
	#seems can not capture nfs pkg from virbr0
	vm exec -v $vmserv -- "touch $pcapf; tmux new -d 'tshark -i $NIC -w ${pcapf}'"
	trun sleep 2
	trun ls -l $nfsmp $nfsmp/testdir
	trun sleep 3
	vm exec -v $vmserv -- pkill tshark
	vm exec -v $vmserv -- "tshark -i $NIC -Y nfs -r $pcapf -T fields -e nfs.fhandle -f 'nfs.name == testdir'|grep -E '^.{80}$'|sort -u|tee fhlist.txt"
	trun maxblksize=$(vm exec $vmserv -- cat /proc/fs/nfsd/max_block_size)
	trun fh1=$(vm exec $vmserv -- head -1 fhlist.txt)
	trun -as=root "${script_dir}/nfsv3-read.py" $servaddr readdirplus $maxblksize $fh1 -s
	trun -x -as=root "'${script_dir}/nfsv3-read.py' $servaddr readdirplus $maxblksize $fh1 -s|grep nfs.status3.=.0"
	trun -as=root umount -fl $nfsmp
else
	vm create $distro -n $vmclnt -f -nointeract -p 'nfs-utils wireshark tmux'
	vm exec -v $vmclnt -- showmount -e $servaddr
	vm exec -v $vmclnt -- mkdir -p $nfsmp
	vm exec -v $vmclnt -- mount -overs=3 $servaddr:/nfsshare/rw $nfsmp
	vm exec -v $vmclnt -- mount -t nfs,nfs4
	vm exec -v $vmclnt -- "touch $pcapf; tmux new -d 'tshark -i $NIC -w ${pcapf}'"
	vm exec -v $vmclnt -- ls -l $nfsmp $nfsmp/testdir
	vm exec -v $vmclnt -- sleep 2
	vm exec -v $vmclnt -- pkill tshark
	vm exec -v $vmclnt -- "tshark -i $NIC -Y nfs -r $pcapf -T fields -e nfs.fhandle -f 'nfs.name == testdir'|grep -E '^.{80}$'|sort -u|tee fhlist.txt"
	trun maxblksize=$(vm exec $vmserv -- cat /proc/fs/nfsd/max_block_size)
	vm -v cpto $vmclnt "${script_dir}/nfsv3-read.py" .
	trun fh1=$(vm exec $vmclnt -- head -1 fhlist.txt)
	trun "fhlist='$(vm exec $vmclnt -- cat fhlist.txt)'"
	vm exec -vx $vmclnt -- "./nfsv3-read.py $servaddr readdirplus $maxblksize $fh1 -s | grep nfs.status3.=.0"
fi
