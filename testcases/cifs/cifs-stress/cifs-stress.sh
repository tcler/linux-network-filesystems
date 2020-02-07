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

yum install -y samba samba-common cifs-utils /usr/bin/firewall-cmd expect

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
prefix=cifs-stress
serv=$(getDefaultIp)

expdir=/cifsshare-$prefix
cifsmp=/mnt/cifsmp-$prefix
sharename=cifsshare
cifsshare=//$serv/$sharename
startNetAddr=128

#configure cifs server
mkdir -p $expdir $cifsmp
chmod 777 $expdir
cat >/etc/samba/smb.conf <<EOF
[global]
    workgroup = RHTS
    realm = RHQE.COM
    kerberos method = system keytab
    server signing = mandatory
    client signing = mandatory
    encrypt passwords = yes
    security = user

[$sharename]
    path = $expdir
    writable = yes
    browsable = yes
    read only = no
    valid users = root,tuser1,tuser2,tuser3
EOF
restorecon /etc/samba/smb.conf
chcon -R -t samba_share_t $expdir
echo -e "redhat\nredhat" | smbpasswd -a root -s
#testparm -s
systemctl restart smb

#add test users
useradd tuser1
useradd tuser2
useradd tuser3
echo redhat | passwd tuser1 --stdin
echo redhat | passwd tuser2 --stdin
echo redhat | passwd tuser3 --stdin
echo -e "redhat\nredhat" |smbpasswd -a tuser1 -s
echo -e "redhat\nredhat" |smbpasswd -a tuser2 -s
echo -e "redhat\nredhat" |smbpasswd -a tuser3 -s

#firewall configure
systemctl start firewalld
firewall-cmd --add-service=samba --permanent
firewall-cmd --add-service=samba

#create a series network namespaces
sysctl -w net.ipv4.conf.all.forwarding=1
modprobe -r veth

for ((n=0; n<NSCNT; n++)); do
	i=$((startNetAddr+n))
	ns=netns$i
	vethif=ve-$ns.h
	vethif_peer=ve-$ns.n
	hostip=192.168.$i.1
	nsip=192.168.$i.2

	netns host,$vethif,$hostip---$ns,$vethif_peer,$nsip
	netns exec -v "$ns" -- ip route add default via $hostip dev $vethif_peer
	iptables -A POSTROUTING -s 192.168.$i.0/24 -j MASQUERADE -t nat
done

touch $expdir/cifsstress.sh
chmod +x $expdir/cifsstress.sh
chcon -R -t samba_share_t $expdir
cat <<'EOF' >$expdir/cifsstress.sh
#!/bin/bash

CIFSSHARE="${1}"
TestUser=${2}
NSIP=${3}
Ver=${4}
[[ -n "$Ver" ]] && VerOpt=vers=${Ver},
read CIFS_SRV _  <<<"${CIFSSHARE//\// }"

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

	echo "[cifs-stress] Iteration $i"
	MOUNT_POINT="/${CIFS_SRV:?}_${TestUser}_$RANDOM"
	RemoteDIR="${MOUNT_POINT:?}/MY_CIFS/$(hostname -s)"
	LocalDIR="/tmp/$(hostname -s)-$$"

	mkdir "${MOUNT_POINT:?}"
	chmod 777 $MOUNT_POINT
	echo "[cifs-stress] mount ${CIFSSHARE:?} ${MOUNT_POINT:?} -o ${VerOpt}multiuser,password=redhat,file_mode=0777,dir_mode=0777,rsize=65536,wsize=65536"
	mount ${CIFSSHARE:?} "${MOUNT_POINT:?}" -o ${VerOpt}multiuser,password=redhat,file_mode=0777,dir_mode=0777,rsize=65536,wsize=65536
	[[ $? != 0 ]] && break

	#cifscreds
	echo "[cifs-stress] cifscreds add -u $TestUser $HOSTNAME"
	su $TestUser --session-command='expect -c "spawn cifscreds add -u '"$TestUser $NSIP"'
		expect {
			{Password:} {
				send \"redhat\\r\"
				expect eof
			}
			{You already *} {exit 0}
		}
		foreach {pid spawnid os_error_flag value} [wait] break
		exit \$value
	"
	'
	[[ $? != 0 ]] && break

	mkdir -p $LocalDIR
	chmod 777 $LocalDIR
	[[ -d $RemoteDIR ]] || mkdir -p $RemoteDIR
	chown -R $TestUser $RemoteDIR

	file_name=file_$$.txt
	file_size=$(get_random 1024)
	bs_size=$(get_random 104857)

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[cifs-stress] permission check"
	su $TestUser --session-command="ls -ld ${MOUNT_POINT}"
	su $TestUser --session-command="ls -l ${MOUNT_POINT}"
	su $TestUser --session-command="ls -ld ${RemoteDIR}"
	su $TestUser --session-command="touch ${RemoteDIR}/testfile"

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[cifs-stress] Creating  $file_size file on local machine"
	su $TestUser --session-command="time dd if=/dev/zero of=$LocalDIR/$file_name count=${file_size:?} bs=${bs_size}"

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[cifs-stress] {$TestUser} Moving file from Local-->Remote"
	su $TestUser --session-command="time mv $LocalDIR/$file_name ${RemoteDIR:?}/."

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[cifs-stress] {$TestUser} Removing file on Remote"
	su $TestUser --session-command="time rm -rf ${RemoteDIR:?}/$file_name"

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[cifs-stress] {$TestUser} Creating a file on Remote machine"
	su $TestUser --session-command="time dd if=/dev/zero of=$RemoteDIR/$file_name count=1024 bs=1048576"

	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "
	echo "[cifs-stress] {$TestUser} Moving file from Remote-->Local"
	su $TestUser --session-command="time mv ${RemoteDIR:?}/$file_name $LocalDIR/."
	echo " - - - - - - - - - - - - - - - - - - - - - - - -  "

	echo "[cifs-stress] Removing local file"
	rm -rf $LocalDIR

	echo "[cifs-stress] Umounting CIFS mount"
	time umount -f "${MOUNT_POINT}"
	rm -rf "$MOUNT_POINT"

	i=$((i + 1))
	sleep 40
done
EOF

runcnt=${1:-3}
for ((n=0; n<NSCNT; n++)); do
	j=$((startNetAddr+n))
	ns=netns$j
	mp=$cifsmp/${ns}mp
	mkdir -p $mp
	NSIP=192.168.$j.2

	echo "{INFO} Test in namespace $ns ..."
	#don't use vers=1.0, will cause stale file
	netns exec -vx0 $ns -- mount $cifsshare $mp -o vers=2.1,multiuser,password=redhat,file_mode=0777,dir_mode=0777,rsize=65536,wsize=65536
	netns exec -v   $ns -- mount -t cifs

	echo "- {INFO} Running cifsstress.sh script $runcnt instance from client $ns"
	for V in 3.11 3.02 3.0 2.1 2.0 1.0 ; do
		for U in tuser{1..3}; do
			for ((i=0; i<runcnt; i++)) do
				netns exec -v $ns -- "tmux -L $ns-test new -d '$mp/cifsstress.sh $cifsshare $U $NSIP $V &>/tmp/$ns-cifs-$V-stress-$i-$U.log'"
				sleep 1
			done
		done
	done

	for ((i=0; i<40; i++)); do
		sleep 10
		pgrep cifsstress.sh >/dev/null || break
	done

	ps aux | grep -v grep | grep cifsstress.sh
	netns exec -v $ns -- pkill cifsstress.sh
	netns exec -v $ns -- umount -a -f -t cifs
	netns del $ns
	netns ls

	if dmesg | egrep '\[[ .[0-9]]+\] WARNING:'; then
		:
	fi
done
