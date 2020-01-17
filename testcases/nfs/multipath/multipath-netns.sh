#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }

baseurl=https://raw.githubusercontent.com/tcler/kiss-vm-ns/master
curl -o /usr/bin/netns -L ${baseurl}/kiss-netns
chmod +x /usr/bin/netns

ServerIP1=192.168.10.1
ClientIP1=192.168.10.2
ServerIP2=192.168.11.1
ClientIP2=192.168.11.2

ExportDir=/nfsshare
MountPoint=/mnt/netns0/nfs

systemctl stop firewalld
mkdir -p $ExportDir $MountPoint
touch $ExportDir/testfile
echo "$ExportDir *(rw,no_root_squash,security_label)" >/etc/exports
systemctl restart nfs-server

netns 2>/dev/null
netns host,veth0.X,$ServerIP1---netns0,veth0.Y,$ClientIP1  host,veth1.X,$ServerIP2---netns0,veth1.Y,$ClientIP2
netns exec -vx0 netns0 -- mount -v $ServerIP1:$ExportDir $MountPoint
netns exec -vx0 netns0 -- mount -v $ServerIP2:$ExportDir $MountPoint
netns exec -v   netns0 -- mount -t nfs4
netns exec -vx0 netns0 -- umount $MountPoint
netns exec -vx0 netns0 -- umount $MountPoint

#dd if=/dev/zero of=$ExportDir/testimage bs=1M count=1024

#please clean test env:
netns del netns0
