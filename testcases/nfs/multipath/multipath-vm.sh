#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

if ! egrep -wo '(vmx|svm)' /proc/cpuinfo -q; then
	warnlog "this testcase need host support Virtualiztion, but current machine doen't support." >&2
	exit 1
fi
[[ -z "$distro" ]] && {
	echo "Usage: $0 <distro> [mount options]"
	exit 1
}

warnlog() { echo -e "\033[41m{TEST:WARN} $*\033[0m"; }
faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }
install-kiss-vm-ns() {
	local _name=$1
	local KissUrl=https://github.com/tcler/kiss-vm-ns
	which vm &>/dev/null || {
		echo -e "{info} installing kiss-vm-ns ..."
		which git &>/dev/null || yum install -y git
		while true; do
			git clone --depth=1 "$KissUrl" && make -C kiss-vm-ns
			which vm && break
			sleep 5
			echo -e "{warn} installing kiss-vm-ns  fail, try again ..."
		done
	}
	[[ "$_name"x = "vm"x ]] && vm prepare
}

ExportDir=/nfsshare
MountPoint=/mnt/nfs
distro=$1; shift
MOUNT_OPTS="$*"
MOUNT_OPTS=${MOUNT_OPTS:--onconnect=16}

subnet1=12
brname1=vm-vbr$subnet1
netname1=net$subnet1
S=serv
C=clnt

install-kiss-vm-ns vm

vm netcreate netname=$netname1 brname=$brname1 subnet=$subnet1
vm netinfo $netname1

vm create "$distro" -n $S --saveimage -p "nfs-utils" --nointeract --net default --net $netname1 -f
vm create "$distro" -n $C --saveimage -p "nfs-utils" --nointeract --net default --net $netname1 -f

servIpAddrs=$(vm exec -v $S -- ip a s)
echo "$servIpAddrs"

Saddr0=$(vm -r ifaddr $S|grep '192.168.122\.' || echo "$servIpAddrs" | awk -F'[/ ]+' '/inet 192.168.122.[0-9]+/{print $3}')
Saddr1=$(vm -r ifaddr $S|grep "192.168.${subnet1}\\." || echo "$servIpAddrs" | awk -F'[/ ]+' "/inet 192.168.$subnet1.[0-9]+/{print \$3}")

vm exec -v   $S -- mkdir -p $ExportDir
vm exec -v   $S -- touch $ExportDir/testfile
vm exec -v   $S -- "echo '$ExportDir *(rw,no_root_squash,insecure,security_label)' >/etc/exports"
vm exec -v   $S -- systemctl restart nfs-server

vm exec -v   $C -- mkdir -p $MountPoint
vm exec -vx0 $C -- showmount -e $Saddr0
vm exec -vx0 $C -- mount $MOUNT_OPTS $Saddr0:$ExportDir $MountPoint
vm exec -vx0 $C -- showmount -e $Saddr1
vm exec -v   $C -- mount $MOUNT_OPTS $Saddr1:$ExportDir $MountPoint

vm exec -v   $C -- mount -t nfs,nfs4
vm exec -v   $C -- grep xprt /proc/self/mountstats
vm exec -v   $C -- ss -nt "dst $ServerIP1"

vm exec -v   $C -- mount -t nfs,nfs4
vm exec -vx0 $C -- umount -t nfs,nfs4 -a

#please clean test env:
vm del $C
vm del $S
vm netdel $netname1
