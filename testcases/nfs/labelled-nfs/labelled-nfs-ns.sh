#!/bin/bash

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }

sleeptime=${1:-1}
ServerIP=192.168.254.1
Client1IP=192.168.254.11
Client2IP=192.168.254.12
ExportDir=/nfsshare
MountPoint=/mnt/nfs

trun 'ns 2>/dev/null'

#ns jj nsmini bash
trun ns jj nsbase nfs-utils iproute iputils

trun systemctl stop firewalld

trun ns -n serv --macvlan-ip $ServerIP  --clone nsbase
ns exec -v serv -- systemctl stop firewalld
ns exec -v serv -- mkdir -p $ExportDir
ns exec -v serv -- touch $ExportDir/testfile
ns exec -v serv -- "echo '$ExportDir *(rw,no_root_squash,security_label)' >/etc/exports"
ns exec -v serv -- systemctl restart nfs-server

trun ns -n c1 --macvlan-ip $Client1IP -bind=/usr  -clone nsbase
ns exec -v c1 -- systemctl stop firewalld
ns exec -v c1 -- mkdir -p $MountPoint
ns exec -vx0 c1 -- showmount -e $ServerIP
ns exec -vx0 c1 -- ping -c 4 $ServerIP
ns exec -vx0 c1 -- mount -vvv $ServerIP:/ $MountPoint -overs=4.2,actimeo=1,sync
ns exec -v c1 -- mount -t nfs
ns exec -v c1 -- mount -t nfs4

trun ns -n c2 --macvlan-ip $Client2IP -bind=/usr -clone nsbase
ns exec -v c2 -- systemctl stop firewalld
ns exec -v c2 -- mkdir -p $MountPoint
ns exec -vx0 c2 -- showmount -e $ServerIP
ns exec -vx0 c2 -- ping -c 4 $ServerIP
ns exec -vx0 c2 -- mount -vvv $ServerIP:/ $MountPoint -overs=4.2,actimeo=1,sync
ns exec -v c2 -- mount -t nfs
ns exec -v c2 -- mount -t nfs4

#init value
trun ns exec -v serv -- ls -lZ $ExportDir/testfile
ns exec -v c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec -v c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec -v c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
cmp con.s con.c1 || faillog "$(< con.s) != $(< con.c1)"
cmp con.s con.c2 || faillog "$(< con.s) != $(< con.c2)"

#change from server
trun ns exec -v serv -- chcon -t etc_t $ExportDir/testfile
trun sleep ${sleeptime}
ns exec -v serv -- ls -lZ $ExportDir/testfile
ns exec -v c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec -v c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec -v c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
trun cmp con.s con.c1
	xrc 0 "$(< con.s) != $(< con.c1)"
trun cmp con.s con.c2
	xrc 0 faillog "$(< con.s) != $(< con.c2)"

#change from server again
ns exec -v serv -- chcon -t default_t $ExportDir/testfile
sleep ${sleeptime}
ns exec -v serv -- ls -lZ $ExportDir/testfile
ns exec -v c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec -v c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec -v c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
trun cmp con.s con.c1
	xrc 0 "$(< con.s) != $(< con.c1)"
trun cmp con.s con.c2
	xrc 0 "$(< con.s) != $(< con.c2)"

#change from c1
ns exec -v c1 -- "chcon -t usr_t $MountPoint/$ExportDir/testfile; sync"
sleep ${sleeptime}
ns exec -v serv -- ls -lZ $ExportDir/testfile
ns exec -v c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec -v c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec -v c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
trun cmp con.s con.c1 
	xrc 0 "$(< con.s) != $(< con.c1)"
trun cmp con.s con.c2
	xrc 0 "$(< con.s) != $(< con.c2)"

#change from c2
ns exec -v c2 -- "chcon -t etc_t $MountPoint/$ExportDir/testfile; sync"
sleep ${sleeptime}
ns exec -v serv -- ls -lZ $ExportDir/testfile
ns exec -v c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v c2 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v serv -- stat -c %C $ExportDir/testfile | tee con.s
ns exec -v c1 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c1
ns exec -v c2 -- stat -c %C $MountPoint/$ExportDir/testfile | tee con.c2
trun cmp con.s con.c1
	xrc 0 "$(< con.s) != $(< con.c1)"
trun cmp con.s con.c2
	xrc 0 "$(< con.s) != $(< con.c2)"

#check mount -t output
ns exec -v c1 -- mount -t nfs
ns exec -v c1 -- mount -t nfs4
ns exec -v c2 -- mount -t nfs
ns exec -v c2 -- mount -t nfs4

#check file info again
echo -e "\n{info} 1. will get unexpected stale file handle, if hit bug"
ns exec -v c1 -- ls -lZ $MountPoint/$ExportDir/testfile
ns exec -v c2 -- ls -lZ $MountPoint/$ExportDir/testfile

#please clean test env:
ns exec -vx0 c2 -- umount $MountPoint
ns exec -vx0 c1 -- umount $MountPoint
ns exec -v   serv -- systemctl stop nfs-server

trun ns del c1 c2 serv
