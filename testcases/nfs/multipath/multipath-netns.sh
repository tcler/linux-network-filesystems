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
ServerIP3=192.168.8.1
ClientIP3=192.168.8.2

ExportDir=/nfsshare
MountPoint1=/mnt/netns0/nfs1
MountPoint2=/mnt/netns0/nfs2
MountPoint3=/mnt/netns0/nfs3
MOUNT_OPTS="$*"

systemctl stop firewalld
mkdir -p $ExportDir $MountPoint1 $MountPoint2 $MountPoint3
touch $ExportDir/testfile
echo "$ExportDir *(rw,no_root_squash,insecure,security_label)" >/etc/exports
systemctl restart nfs-server

netns 2>/dev/null
netns host,veth0.X,$ServerIP1---netns0,veth0.Y,$ClientIP1  host,veth1.X,$ServerIP2---netns0,veth1.Y,$ClientIP2  host,veth2.X,$ServerIP3---netns0,veth2.Y,$ClientIP3
netns exec -vx0 netns0 -- showmount -e $ServerIP1
netns exec -vx0 netns0 -- mount  $ServerIP1:$ExportDir $MountPoint1 $MOUNT_OPTS

netns exec -vx0 netns0 -- showmount -e $ServerIP2
netns exec -vx0 netns0 -- mount  $ServerIP2:$ExportDir $MountPoint2 $MOUNT_OPTS

netns exec -vx0 netns0 -- showmount -e $ServerIP3
netns exec -v   netns0 -- mount  $ServerIP3:$ExportDir $MountPoint3 $MOUNT_OPTS

netns exec -v   netns0 -- ss -nt "dst $ServerIP1"
netns exec -v   netns0 -- ss -nt "dst $ServerIP2"
netns exec -v   netns0 -- ss -nt "dst $ServerIP3"

netns exec -v   netns0 -- mount -t nfs,nfs4
netns exec -vx0 netns0 -- umount -t nfs,nfs4 -a
netns exec -v   netns0 -- mount -t nfs,nfs4

#dd if=/dev/zero of=$ExportDir/testimage bs=1M count=1024

#please clean test env:
netns del netns0
