#!/bin/bash

baseurl=http://download.eng.bos.redhat.com/qa/rhts/lookaside/bkr-client-improved
baseurl=https://raw.githubusercontent.com/tcler/bkr-client-improved/master
curl -s -o /usr/local/bin/ns -L ${baseurl}/utils/ns
chmod +x /usr/local/bin/ns

sleeptime=${1:-1}
ServerIP=192.168.254.1
Client1Ip=192.168.254.11
Client2Ip=192.168.254.12
ExportDir=/nfsshare
MountPoint=/mnt/nfs

ns
ns jj nsbase nfs-utils iproute iputils firewalld
ns jj nsmini bash

ns -n serv --macvlan-ip $ServerIp  --clone nsbase
ns exec serv -- mkdir -p $ExportDir
ns exec serv -- touch $ExportDir/testfile
ns exec serv -- "echo '$ExportDir *(rw,no_root_squash,security_label)' >/etc/exports"
ns exec serv -- systemctl restart nfs-server
ns exec serv -- systemctl start firewalld
ns exec serv -- firewall-cmd --add-service={nfs,mountd,rpc-bind}
ns exec serv -- firewall-cmd --get-services

ns -n c1 --macvlan-ip $Client1Ip -bind=/usr -noboot -clone nsmini
ns exec c1 -- mkdir -p $MountPoint
ns exec c1 -- showmount -e $ServerIp
ns exec c1 -- mount $ServerIp:/ $MountPoint -overs=4.2,actimeo=1,sync
ns exec c1 -- mount -t nfs
ns exec c1 -- mount -t nfs4

ns -n c2 --macvlan-ip $Client2Ip -bind=/usr -noboot -clone nsmini
ns exec c2 -- mkdir -p $MountPoint
ns exec c2 -- showmount -e $ServerIp
ns exec c2 -- mount $ServerIp:/ $MountPoint -overs=4.2,actimeo=1,sync
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
ns exec c1 -- 'chcon -t usr_t $MountPoint/$ExportDir/testfile; sync'
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
ns exec c2 -- 'chcon -t etc_t $MountPoint/$ExportDir/testfile; sync'
sleep ${sleeptime}
ns exec serv -- ls -lZ $ExportDir/testfile
ns exec c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
cmp con.s con.c1 || echo -e "\n{warnig} ^^^^^^^^^^^"
cmp con.s con.c2 || echo -e "\n{warnig} ^^^^^^^^^^^"

ns exec c1 -- mount -t nfs
ns exec c1 -- mount -t nfs4
ns exec c2 -- mount -t nfs
ns exec c2 -- mount -t nfs4

ns exec c1 -- umount $MountPoint
ns exec c2 -- umount $MountPoint
