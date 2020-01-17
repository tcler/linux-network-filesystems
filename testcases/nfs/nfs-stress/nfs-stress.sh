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

toolsurl=https://raw.githubusercontent.com/tcler/kiss-vm-ns/master
which netns &>/dev/null || {
	is_available_url() { curl --connect-timeout 8 -m 16 --output /dev/null --silent --head --fail $1 &>/dev/null; }
	is_intranet() { is_available_url http://download.devel.redhat.com; }
	is_intranet && toolsurl=http://download.devel.redhat.com/qa/rhts/lookaside/kiss-vm-ns
	echo -e "[INFO] install kiss-netns ..."
	sudo curl -s -o /usr/bin/netns -L ${toolsurl}/kiss-netns
	sudo chmod +x /usr/bin/netns
}

faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }
warnlog() { echo -e "\033[41m{TEST:WARN} $*\033[0m"; }

getIp() {
  local ret
  local nic=$1
  local ver=$2
  local sc=${3}
  local ipaddr=`ip addr show $nic`;
  [ -z "$sc" ] && {
      sc=global;
      echo "$ipaddr"|grep -q 'inet6.*global' || sc=link;
  }
  local flg='(global|host lo)'

  case $ver in
  6|6nfs)
      ret=`echo "$ipaddr" |
          awk '/inet6.*'$sc'/{match($0,"inet6 ([0-9a-f:]+)",M); print M[1]}'`
      [ -n "$ret" -a $ver = 6nfs ] && ret=$ret%$nic;;
  4|*)
      ret=`echo "$ipaddr" |
          awk '/inet .*'"$flg"'/{match($0,"inet ([0-9.]+)",M); print M[1]}'`;;
  esac

  echo "$ret"
  [ -z "$ret" ] && return 1 || return 0
}

getDefaultNic() {
  ip route | awk '/default/{match($0,"dev ([^ ]+)",M); print M[1]; exit}'
}

getDefaultIp() {
  local nic=`getDefaultNic`
  [ -z "$nic" ] && return 1

  getIp "$nic" "$@"
}

NSCNT=10
prefix=nfs-stress
serv=$(getDefaultIp)

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
firewall-cmd --add-service=nfs --add-service=mountd --add-service=rpc-bind

#create a series network namespaces
sysctl -w net.ipv4.conf.all.forwarding=1
modprobe -r veth

for ((n=0; n<NSCNT; n++)); do
	i=$((100+n))
	ns=ns$i
	vethif=ve-$ns.h
	vethif_peer=ve-$ns.n
	hostip=192.168.$i.1
	nsip=192.168.$i.2

	netns host,$vethif,$hostip---$ns,$vethif_peer,$nsip
	netns exec -v "$ns" -- ip route add default via $hostip dev $vethif_peer
	iptables -A POSTROUTING -s 192.168.$i.0/24 -j MASQUERADE -t nat
done

touch $expdir/nfsstress.sh
chmod +x $expdir/nfsstress.sh
cat <<'EOF' >$expdir/nfsstress.sh
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
for ((n=0; n<NSCNT; n++)); do
	j=$((100+n))
	ns=ns$j
	mp=$nfsmp/${ns}mp
	mkdir -p $mp

	echo "{INFO} Test in namespace $ns ..."
	netns exec -vx0 $ns -- showmount -e ${serv}
	netns exec -vx0 $ns -- mount -vv $nfsshare $mp
	netns exec -v   $ns -- mount -t nfs4

	echo "- {INFO} Running nfsstress.sh script $runcnt instance from client $ns"
	for ((i=0; i<runcnt; i++)) do
		netns exec -v $ns -- "tmux -L netns-$ns new -d '$mp/nfsstress.sh $nfsshare &>/tmp/$ns-nfs-stress$i.log'"
		sleep 1
	done
	sleep 400
	ps aux | grep -v grep | grep nfsstress.sh
	netns exec -v $ns -- pkill nfsstress.sh
	netns exec -v $ns -- umount -a -f -t nfs4
	netns del $ns

	if dmesg | egrep '\[[ .[0-9]]+\] WARNING:'; then
		:
	fi
done
