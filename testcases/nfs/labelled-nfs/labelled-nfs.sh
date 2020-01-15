#!/bin/bash

baseurl=https://raw.githubusercontent.com/tcler/kiss-vm-ns/master
curl -s -o /usr/bin/ns -L ${baseurl}/kiss-ns
chmod +x /usr/bin/ns

sleeptime=${1:-1}
ServerIP=192.168.254.1
Client1IP=192.168.254.11
Client2IP=192.168.254.12
ExportDir=/nfsshare
MountPoint=/mnt/nfs
export nsverbose=yes
ns 2>/dev/null

#ns jj nsmini bash
ns jj nsbase nfs-utils iproute iputils

systemctl stop firewalld

ns -n serv --macvlan-ip $ServerIP  --clone nsbase
ns exec serv -- systemctl stop firewalld
ns exec serv -- mkdir -p $ExportDir
ns exec serv -- touch $ExportDir/testfile
ns exec serv -- "echo '$ExportDir *(rw,no_root_squash,security_label)' >/etc/exports"
ns exec serv -- systemctl restart nfs-server

ns -n c1 --macvlan-ip $Client1IP -bind=/usr  -clone nsbase
ns exec c1 -- systemctl stop firewalld
ns exec c1 -- mkdir -p $MountPoint
ns exec c1 -- showmount -e $ServerIP
ns exec c1 -- ping -c 4 $ServerIP
ns exec c1 -- mount -vvv $ServerIP:/ $MountPoint -overs=4.2,actimeo=1,sync
ns exec c1 -- mount -t nfs
ns exec c1 -- mount -t nfs4

ns -n c2 --macvlan-ip $Client2IP -bind=/usr -clone nsbase
ns exec c2 -- systemctl stop firewalld
ns exec c2 -- mkdir -p $MountPoint
ns exec c2 -- showmount -e $ServerIP
ns exec c2 -- ping -c 4 $ServerIP
ns exec c2 -- mount -vvv $ServerIP:/ $MountPoint -overs=4.2,actimeo=1,sync
ns exec c2 -- mount -t nfs
ns exec c2 -- mount -t nfs4

#init value
ns exec serv -- ls -lZ $ExportDir/testfile
ns exec c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
cmp con.s con.c1 || echo -e "\n{warnig} ^^^^^^^^^^^"
cmp con.s con.c2 || echo -e "\n{warnig} ^^^^^^^^^^^"

#change from server
ns exec serv -- chcon -t etc_t $ExportDir/testfile
sleep ${sleeptime}
ns exec serv -- ls -lZ $ExportDir/testfile
ns exec c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
cmp con.s con.c1 || echo -e "\n{warnig} ^^^^^^^^^^^"
cmp con.s con.c2 || echo -e "\n{warnig} ^^^^^^^^^^^"

#change from server again
ns exec serv -- chcon -t default_t $ExportDir/testfile
sleep ${sleeptime}
ns exec serv -- ls -lZ $ExportDir/testfile
ns exec c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
cmp con.s con.c1 || echo -e "\n{warnig} ^^^^^^^^^^^"
cmp con.s con.c2 || echo -e "\n{warnig} ^^^^^^^^^^^"

#change from c1
ns exec c1 -- "chcon -t usr_t $MountPoint/$ExportDir/testfile; sync"
sleep ${sleeptime}
ns exec serv -- ls -lZ $ExportDir/testfile
ns exec c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
cmp con.s con.c1 || echo -e "\n{warnig} ^^^^^^^^^^^"
cmp con.s con.c2 || echo -e "\n{warnig} ^^^^^^^^^^^"

#change from c2
ns exec c2 -- "chcon -t etc_t $MountPoint/$ExportDir/testfile; sync"
sleep ${sleeptime}
ns exec serv -- ls -lZ $ExportDir/testfile
ns exec c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
cmp con.s con.c1 || echo -e "\n{warnig} ^^^^^^^^^^^"
cmp con.s con.c2 || echo -e "\n{warnig} ^^^^^^^^^^^"

#check mount -t output
ns exec c1 -- mount -t nfs
ns exec c1 -- mount -t nfs4
ns exec c2 -- mount -t nfs
ns exec c2 -- mount -t nfs4

#check file info again
echo -e "\n{info} 1. will get unexpected stale file handle, if hit bug"
ns exec c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec c2 -- ls -lZ $MountPoint/$ExportDir/testfile

#please clean test env:
ns exec c2 -- umount $MountPoint
ns exec c1 -- umount $MountPoint
ns exec serv -- systemctl stop nfs-server
