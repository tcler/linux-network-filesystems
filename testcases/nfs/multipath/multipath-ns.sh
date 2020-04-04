#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

toolsurl=https://raw.githubusercontent.com/tcler/kiss-vm-ns/master
faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }

which ns &>/dev/null || {
	is_available_url() { curl --connect-timeout 8 -m 16 --output /dev/null --silent --head --fail $1 &>/dev/null; }
	is_intranet() { is_available_url http://download.devel.redhat.com; }
	is_intranet && toolsurl=http://download.devel.redhat.com/qa/rhts/lookaside/kiss-vm-ns
	echo -e "[INFO] install kiss-ns ..."
	sudo curl -s -o /usr/bin/ns -L ${toolsurl}/kiss-ns
	sudo chmod +x /usr/bin/ns
}

ServerIP1=192.168.9.1
ClientIP1=192.168.9.2
ServerIP2=192.168.10.1
ClientIP2=192.168.10.2
ServerIP3=192.168.11.1
ClientIP3=192.168.11.2
ExportDir=/nfsshare
MountPoint=/mnt/nfs
MOUNT_OPTS="$*"

ns 2>/dev/null

#ns jj nsmini bash
ns jj nsbase bash nfs-utils iproute iputils #firewalld

systemctl stop firewalld

ns -n serv --macvlan-ip $ServerIP1,$ServerIP2,$ServerIP3  --clone nsbase
ns exec -v serv -- systemctl stop firewalld
ns exec -v serv -- mkdir -p $ExportDir
ns exec -v serv -- touch $ExportDir/testfile
ns exec -v serv -- "echo '$ExportDir *(rw,no_root_squash,security_label)' >/etc/exports"
ns exec -v serv -- systemctl restart nfs-server

ns -n c1 --macvlan-ip $ClientIP1,$ClientIP2,$ClientIP3 -bind=/usr -clone nsbase
ns exec -v   c1 -- systemctl stop firewalld
ns exec -v   c1 -- mkdir -p $MountPoint

ns exec -vx0 c1 -- showmount -e $ServerIP1
ns exec -vx0 c1 -- mount -v $ServerIP1:/ $MountPoint -onconnect=2 $MOUNT_OPTS
ns exec -vx0 c1 -- showmount -e $ServerIP2
ns exec -vx0 c1 -- mount -v $ServerIP2:/ $MountPoint -onconnect=2 $MOUNT_OPTS
ns exec -vx0 c1 -- showmount -e $ServerIP3
ns exec -v   c1 -- mount -v $ServerIP3:/ $MountPoint -onconnect=2 $MOUNT_OPTS

ns exec -v   c1 -- "mount -l | grep nfs4"
ns exec -v   c1 -- mount -t nfs
ns exec -v   c1 -- mount -t nfs4

#ns exec -v serv -- dd if=/dev/zero of=$ExportDir/testimage bs=1M count=1024

#please clean test env:
ns exec -vx0 c1 -- umount $MountPoint
ns exec -vx0 c1 -- umount $MountPoint
ns exec -v   serv -- systemctl stop nfs-server

ns delete c1
ns delete serv
