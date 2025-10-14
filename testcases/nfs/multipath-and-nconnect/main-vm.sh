#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

export LANG=C
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
[[ -n "${imgf}" ]] && insOpt=-I=$imgf

S=nfs-nconn-serv
C=nfs-nconn-clnt
pkgs=nfs-utils,firewalld

[[ -z "$distro" ]] && {
	echo "Usage: $0 <distro> [mount options]"
	exit 1
}

vm netcreate netname=$netname1 brname=$brname1 subnet=$subnet1
vm netinfo $netname1

vm create "$distro" -n $S -p $pkgs --nointeract --net default --net $netname1 -f "$@" $insOpt
vm create "$distro" -n $C -p $pkgs --nointeract --net default --net $netname1 -f "$@" $insOpt
timeout 300 vm port-available -w $S || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

servIpAddrs=$(vm exec $S -- ip a s)
echo "$servIpAddrs"

defaultNetIp=$(vm netinfo default | awk -F"[ =']+" '/ip address=/{print $4}')
Saddr0=$(echo "$servIpAddrs" | awk -F'[/ ]+' "/inet ${defaultNetIp%.*}.[0-9]+/{print \$3}")
Saddr1=$(echo "$servIpAddrs" | awk -F'[/ ]+' "/inet 192.168.${subnet1}.[0-9]+/{print \$3}")

vmrunx - $S  mkdir -p $ExportDir
vmrunx - $S  touch $ExportDir/testfile
vmrunx - $S  "echo '$ExportDir *(rw,no_root_squash,insecure,security_label)' >/etc/exports"
vmrunx - $S  systemctl restart nfs-server
vmrunx - $S  firewall-cmd --permanent --add-service={mountd,nfs,rpc-bind}
vmrunx - $S  firewall-cmd --reload

vmrunx - $C  mkdir -p $MountPoint
vmrunx 0 $C  showmount -e $Saddr0
vmrunx 0 $C  mount $MOUNT_OPTS $Saddr0:$ExportDir $MountPoint
vmrunx 0 $C  showmount -e $Saddr1
vmrunx - $C  mount $MOUNT_OPTS $Saddr1:$ExportDir $MountPoint

vmrunx - $C  mount -t nfs,nfs4
vmrunx - $C  grep xprt /proc/self/mountstats
vmrunx - $C  ss -nt "dst $Saddr0"
vmrunx - $C  ss -nt "dst $Saddr1"

vmrunx - $C  mount -t nfs,nfs4
vmrunx 0 $C  umount -t nfs,nfs4 -a

#please clean test env:
vm del $C $S
vm netdel $netname1

tcnt
