#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

warnlog() { echo -e "\033[41m{TEST:WARN} $*\033[0m"; }
if ! egrep -wo '(vmx|svm)' /proc/cpuinfo -q; then
	warnlog "this testcase need host support Virtualiztion, but current machine doen't support." >&2
	exit 1
fi

toolsurl=https://raw.githubusercontent.com/tcler/kiss-vm-ns/master
faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }

which vm &>/dev/null || {
	is_available_url() { curl --connect-timeout 8 -m 16 --output /dev/null --silent --head --fail $1 &>/dev/null; }
	is_intranet() { is_available_url http://download.devel.redhat.com; }
	is_intranet && toolsurl=http://download.devel.redhat.com/qa/rhts/lookaside/kiss-vm-ns
	echo -e "[INFO] install kiss-vm ..."
	sudo curl -s -o /usr/bin/vm -L ${toolsurl}/kiss-vm
	sudo chmod +x /usr/bin/vm
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

[[ -z "$distro" ]] && {
	echo "Usage: $0 <distro> [mount options]"
	exit 1
}

vm --prepare

vm net netname=$netname1 brname=$brname1 subnet=$subnet1
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
