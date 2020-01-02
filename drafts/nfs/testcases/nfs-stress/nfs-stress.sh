#!/bin/bash

LANG=C
P=$0
[[ $0 = /* ]] && P=${0##*/}
AT=("$@")
switchroot() {
	[[ $(id -u) != 0 ]] && {
		echo -e "{NETNS:WARN} $P need root permission, switch to:\n  sudo $P ${AT[@]}" | GREP_COLORS='ms=1;30' grep --color=always . >&2
		exec sudo $P "${AT[@]}"
	}
}
switchroot;

NSCNT=10
prefix=nfs-stress
serv=$HOSTNAME

expdir=/nfsshare-$prefix
nfsmp=/mnt/nfsmp-$prefix
nfsshare=$serv:$expdir

#configure nfs server
mkdir -p $expdir $nfsmp
echo "$expdir *(rw,no_root_squash,sync,insecure,no_subtree_check)" >/etc/exports
dmesg -c
systemctl restart nfs-server
exportfs -v
systemctl start firewalld

#create a series network namespaces
sysctl -w net.ipv4.conf.all.forwarding=1
modprobe -r veth
which netns || {
	netnsurl=https://raw.githubusercontent.com/tcler/kiss-vm-ns/master/kiss-netns
	curl -s -o /usr/local/bin/netns -L $netnsurl
	chmod +x /usr/local/bin/netns
}
for ((i=0; i<NSCNT; i++)); do
	ns=ns$i
	vethif=ve-$ns.h
	vethif_peer=ve-$ns.n
	hostip=192.168.$i.1
	nsip=192.168.$i.2

	netns host,$vethif,$hostip---$ns,$vethif_peer,$nsip
	netns -v exec "$ns" -- ip route add default via $hostip dev $vethif_peer
	iptables -A POSTROUTING -s 192.168.$i.0/24 -j MASQUERADE -t nat
done

showmount -e ${serv}
touch $expdir/nfs-stress.sh
chmod +x $expdir/nfs-stress.sh
cat <<'EOF' >$expdir/nfs-stress.sh
#!/bin/bash

NFSSHARE="${1}"
NFS_SRV=${NFSSHARE%:/*}

function get_random {
	local RANGE=$1
	local MY_RANDOM=$RANDOM

	let "MY_RANDOM%=$RANGE"
	echo $MY_RANDOM
}

function chk_fs_size {
	while [[ true ]]; do
		root_fs_size=$(df -hl | grep -w "/" | awk '{print $5}' | cut -f 1 -d "%")
		if [[ $root_fs_size -gt 90 ]]; then
			echo "[INFO] / is more than 90%. Test will sleep until / becomes free"
			sleep 27
		else
			break
		fi
	done
}

i=1
while [[ true ]]; do
	#check file system size.
	chk_fs_size

	echo "[nfs-stress] Iteration $i"
	MOUNT_POINT="/${NFS_SRV:?}_$RANDOM"
	RemoteDIR="${MOUNT_POINT:?}/MY_NFS/$(hostname -s)"
	LocalDIR="/tmp/$(hostname -s)-$$"

	mkdir "${MOUNT_POINT:?}"
	mount ${NFSSHARE:?} "${MOUNT_POINT:?}" -vv
	mkdir -p $LocalDIR
	[[ -d $RemoteDIR ]] || mkdir -p $RemoteDIR

	file_name=file_$$.txt
	file_size=$(get_random 1024)
	bs_size=$(get_random 104857)

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[nfs-stress] Creating  $file_size file on local machine"
	time dd if=/dev/zero of=$LocalDIR/$file_name count=${file_size:?} bs=${bs_size}

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[nfs-stress] Moving file from Local-->Remote"
	time mv $LocalDIR/$file_name ${RemoteDIR:?}/

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[nfs-stress] Removing file on Remote"
	time rm -rf ${RemoteDIR:?}/$file_name

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[nfs-stress] Creating a file on Remote machine"
	time dd if=/dev/zero of=$RemoteDIR/$file_name count=1024 bs=1048576

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[nfs-stress] Copying file from Remote-->Local"
	time mv ${RemoteDIR:?}/$file_name $LocalDIR/
	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "

	echo "[nfs-stress] Removing local file"
	rm -rf $LocalDIR

	echo "[nfs-stress] Umounting NFS mount"
	time umount -f "${MOUNT_POINT}"
	rm -rf "$MOUNT_POINT"

	i=$((i + 1))
	sleep 40
done
EOF

runcnt=10
for ((j=0; j<NSCNT; j++)); do
	ns=ns$j
	mp=$nfsmp/${ns}mp
	mkdir -p $mp

	echo "{INFO} Test in namespace $ns ..."
	netns -v exec $ns -- mount -vv $nfsshare $mp
	netns -v exec $ns -- mount -t nfs4

	echo "- {INFO} Running nfs-stress.sh script $runcnt instance from client $ns"
	for ((i=0; i<runcnt; i++)) do
		netns -v exec $ns -- "tmux -L netns-$ns new -d '$mp/nfs-stress.sh $nfsshare &>/tmp/$ns-nfs-stress$i.log'"
		sleep 1
	done
	sleep 400
	ps aux | grep -v grep | grep nfs-stress.sh
	netns -v exec $ns -- pkill nfs-stress.sh
	netns -v exec $ns -- umount -a -f -t nfs4
	netns del $ns

	if dmesg | egrep '\[[ .[0-9]]+\] WARNING:'; then
		:
	fi
done
