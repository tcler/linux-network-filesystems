#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

warnlog() { echo -e "\033[41m{TEST:WARN} $*\033[0m"; }
faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }

ExportDir=/nfsshare
MountPoint=/mnt/nfs
distro=${1:-9}; shift
MOUNT_OPTS=${MOUNT_OPTS:--onosharecache,nconnect=16}

subnet1=12
brname1=vm-vbr$subnet1
netname1=net$subnet1

stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

S=nfs-nconn-serv
C=nfs-nconn-clnt

[[ -z "$distro" ]] && {
	echo "Usage: $0 <distro> [mount options]"
	exit 1
}

vm netcreate netname=$netname1 brname=$brname1 subnet=$subnet1
vm netinfo $netname1

vm create "$distro" -n $S -p "nfs-utils" --nointeract --net default --net $netname1 -I=$imgf -f
vm create "$distro" -n $C -p "nfs-utils" --nointeract --net default --net $netname1 -I=$imgf -f

servIpAddrs=$(vm exec -v $S -- ip a s)
echo "$servIpAddrs"

Saddr0=$(echo "$servIpAddrs" | awk -F'[/ ]+' '/inet 192.168.122.[0-9]+/{print $3}')
Saddr1=$(echo "$servIpAddrs" | awk -F'[/ ]+' "/inet 192.168.$subnet1.[0-9]+/{print \$3}")

vm exec -v   $S -- mkdir -p $ExportDir
vm exec -v   $S -- touch $ExportDir/testfile
vm exec -v   $S -- "echo '$ExportDir *(rw,no_root_squash,insecure,security_label)' >/etc/exports"
vm exec -v   $S -- systemctl restart nfs-server
vm exec -v   $S -- firewall-cmd --permanent --add-service={mountd,nfs,rpc-bind}
vm exec -v   $S -- firewall-cmd --reload

vm exec -v   $C -- mkdir -p $MountPoint
vm exec -vx0 $C -- showmount -e $Saddr0
vm exec -vx0 $C -- mount $MOUNT_OPTS $Saddr0:$ExportDir $MountPoint
vm exec -vx0 $C -- showmount -e $Saddr1
vm exec -v   $C -- mount $MOUNT_OPTS $Saddr1:$ExportDir $MountPoint

vm exec -v   $C -- mount -t nfs,nfs4
vm exec -v   $C -- grep xprt /proc/self/mountstats
vm exec -v   $C -- ss -nt "dst $Saddr0"
vm exec -v   $C -- ss -nt "dst $Saddr1"

vm exec -v   $C -- mount -t nfs,nfs4
vm exec -vx0 $C -- umount -t nfs,nfs4 -a

#please clean test env:
vm del $C
vm del $S
vm netdel $netname1
