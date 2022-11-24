#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }

ServerIP1=192.168.9.1
ClientIP1=192.168.9.2
ServerIP2=192.168.10.1
ClientIP2=192.168.10.2
ExportDir=/nfsshare
MountPoint=/mnt/nfs
MOUNT_OPTS="$*"
MOUNT_OPTS=${MOUNT_OPTS:--onconnect=16}

ns 2>/dev/null

#ns jj nsmini bash
ns jj nsbase bash nfs-utils iproute iputils #firewalld

systemctl stop firewalld

ns -n serv --macvlan-ip $ServerIP1,$ServerIP2  --clone nsbase
ns exec -v serv -- systemctl stop firewalld
ns exec -v serv -- mkdir -p $ExportDir
ns exec -v serv -- touch $ExportDir/testfile
ns exec -v serv -- "echo '$ExportDir *(rw,no_root_squash,security_label)' >/etc/exports"
ns exec -v serv -- systemctl restart nfs-server

ns -n c1 --macvlan-ip $ClientIP1,$ClientIP2 -bind=/usr -clone nsbase
ns exec -v   c1 -- systemctl stop firewalld
ns exec -v   c1 -- mkdir -p $MountPoint

ns exec -vx0 c1 -- showmount -e $ServerIP1
ns exec -vx0 c1 -- mount $MOUNT_OPTS $ServerIP1:/ $MountPoint
ns exec -vx0 c1 -- showmount -e $ServerIP2
ns exec -v   c1 -- mount $MOUNT_OPTS $ServerIP2:/ $MountPoint

ns exec -v   c1 -- mount -t nfs,nfs4
ns exec -v   c1 -- grep xprt /proc/self/mountstats
ns exec -v   c1 -- ss -nt "dst $ServerIP1"

#please clean test env:
ns exec -vx0 c1 -- umount -t nfs,nfs4 -a
ns exec -v serv -- systemctl stop nfs-server

ns delete c1
ns delete serv
