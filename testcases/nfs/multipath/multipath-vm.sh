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
distro=${distro:-$1}
subnet=11
brname=vm-vbr$subnet
netname=net$subnet

[[ -z "$distro" ]] && {
	echo "Usage: $0 <distro>"
	exit 1
}

vm --prepare

vm net netname=$netname brname=$brname subnet=$subnet
vm netinfo $netname
vm create "$distro" -n serv --saveimage -p "nfs-utils" --nointeract --net default --net $netname -f
vm create "$distro" -n clnt --saveimage -p "nfs-utils" --nointeract --net default --net $netname -f
S=$(vm -r --getvmname "$distro" -n serv)
C=$(vm -r --getvmname "$distro" -n clnt)
Saddr1=$(vm -r ifaddr $S|grep '192.168.122\.')
Saddr2=$(vm -r ifaddr $S|grep '192.168.11\.')

vm exec -v $S -- mkdir -p $ExportDir
vm exec -v $S -- touch $ExportDir/testfile
vm exec -v $S -- "echo '$ExportDir *(rw,no_root_squash,security_label)' >/etc/exports"
vm exec -v $S -- systemctl restart nfs-server

vm exec -v   $C -- mkdir -p $MountPoint
vm exec -vx0 $C -- showmount -e $Saddr1
vm exec -vx0 $C -- mount -vvv $Saddr1:/ $MountPoint
vm exec -vx0 $C -- showmount -e $Saddr2
vm exec -vx0 $C -- mount -vvv $Saddr2:/ $MountPoint

vm exec -v   $C -- mount -t nfs4
vm exec -vx0 $C -- umount $MountPoint
vm exec -vx0 $C -- umount $MountPoint

#please clean test env:
vm del $C
vm del $S
vm netdel $netname
