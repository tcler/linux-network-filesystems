#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

baseurl=https://raw.githubusercontent.com/tcler/bkr-client-improved/master
curl -s -o /usr/local/bin/ns -L ${baseurl}/utils/ns
chmod +x /usr/local/bin/ns

ServerIP1=192.168.10.1
ClientIP1=192.168.10.2
ServerIP2=192.168.11.1
ClientIP2=192.168.11.2
ExportDir=/nfsshare
MountPoint=/mnt/nfs
export nsverbose=yes

ns
ns jj nsbase bash nfs-utils iproute iputils firewalld
ns jj nsmini bash

ns -n serv --macvlan-ip $ServerIP1,$ServerIP2  --clone nsbase
ns exec serv -- mkdir -p $ExportDir
ns exec serv -- touch $ExportDir/testfile
ns exec serv -- "echo '$ExportDir *(rw,no_root_squash,security_label)' >/etc/exports"
ns exec serv -- systemctl restart nfs-server
ns exec serv -- systemctl start firewalld
ns exec serv -- firewall-cmd --add-service={nfs,mountd,rpc-bind}
ns exec serv -- firewall-cmd --get-services

ns -n c1 --macvlan-ip $ClientIP1,$ClientIP2 -bind=/usr -noboot -clone nsmini
ns exec c1 -- mkdir -p $MountPoint
ns exec c1 -- showmount -e $ServerIP1
ns exec c1 -- ping -c 4 $ServerIP1
ns exec c1 -- mount -vvv $ServerIP1:/ $MountPoint

ns exec c1 -- showmount -e $ServerIP2
ns exec c1 -- ping -c 4 $ServerIP2
ns exec c1 -- mount -vvv $ServerIP2:/ $MountPoint
ns exec c1 -- mount -l | grep nfs4

#ns exec serv -- dd if=/dev/zero of=$ExportDir/testimage bs=1M count=1024

#please clean test env:
ns exec c1 -- umount $MountPoint
ns exec c1 -- umount $MountPoint
ns exec serv -- systemctl stop firewalld
ns exec serv -- systemctl stop nfs-server

ns delete c1
ns delete serv
