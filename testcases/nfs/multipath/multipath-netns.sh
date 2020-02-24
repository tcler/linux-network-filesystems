#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

toolsurl=https://raw.githubusercontent.com/tcler/kiss-vm-ns/master
faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }

which netns &>/dev/null || {
	is_available_url() { curl --connect-timeout 8 -m 16 --output /dev/null --silent --head --fail $1 &>/dev/null; }
	is_intranet() { is_available_url http://download.devel.redhat.com; }
	is_intranet && toolsurl=http://download.devel.redhat.com/qa/rhts/lookaside/kiss-vm-ns
	echo -e "[INFO] install kiss-netns ..."
	sudo curl -s -o /usr/bin/netns -L ${toolsurl}/kiss-netns
	sudo chmod +x /usr/bin/netns
}

ServerIP1=192.168.6.1
ClientIP1=192.168.6.2
ServerIP2=192.168.7.1
ClientIP2=192.168.7.2

ExportDir=/nfsshare
MountPoint=/mnt/netns0/nfs

systemctl stop firewalld
mkdir -p $ExportDir $MountPoint
touch $ExportDir/testfile
echo "$ExportDir *(rw,no_root_squash,security_label)" >/etc/exports
systemctl restart nfs-server

netns 2>/dev/null
netns host,veth0.X,$ServerIP1---netns0,veth0.Y,$ClientIP1  host,veth1.X,$ServerIP2---netns0,veth1.Y,$ClientIP2
netns exec -vx0 netns0 -- showmount -e $ServerIP1
netns exec -vx0 netns0 -- mount -v $ServerIP1:$ExportDir $MountPoint -onconnect=16
netns exec -vx0 netns0 -- showmount -e $ServerIP2
netns exec -vx0 netns0 -- mount -v $ServerIP2:$ExportDir $MountPoint -onconnect=16
netns exec -v   netns0 -- mount -t nfs
netns exec -v   netns0 -- mount -t nfs4
netns exec -vx0 netns0 -- umount $MountPoint
netns exec -vx0 netns0 -- umount $MountPoint

#dd if=/dev/zero of=$ExportDir/testimage bs=1M count=1024

#please clean test env:
netns del netns0
