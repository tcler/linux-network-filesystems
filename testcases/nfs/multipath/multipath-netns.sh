#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

faillog() { echo -e "\033[41m{TEST:FAIL} $*\033[0m"; }

install-kiss-vm-ns() {
	local _name=$1
	local KissUrl=https://github.com/tcler/kiss-vm-ns
	which vm &>/dev/null || {
		echo -e "{info} installing kiss-vm-ns ..."
		which git &>/dev/null || yum install -y git
		while true; do
			git clone --depth=1 "$KissUrl" && make -C kiss-vm-ns
			which vm && break
			sleep 5
			echo -e "{warn} installing kiss-vm-ns  fail, try again ..."
		done
	}
	[[ "$_name"x = "vm"x ]] && vm prepare
}
install-kiss-vm-ns

ServerIP1=192.168.6.1
ClientIP1=192.168.6.2

ExportDir=/nfsshare
MountPoint=/mnt/netns0/nfs
MOUNT_OPTS="$*"
MOUNT_OPTS=${MOUNT_OPTS:--onconnect=16}

systemctl stop firewalld
mkdir -p $ExportDir $MountPoint
touch $ExportDir/testfile
echo "$ExportDir *(rw,no_root_squash,insecure,security_label)" >/etc/exports
systemctl restart nfs-server

netns 2>/dev/null
netns host,veth0.X,$ServerIP1---netns0,veth0.Y,$ClientIP1
netns exec -vx0 netns0 -- showmount -e $ServerIP1
netns exec -vx0 netns0 -- mount $ServerIP1:$ExportDir $MountPoint $MOUNT_OPTS
netns exec -v   netns0 -- mount -t nfs,nfs4

netns exec -v   netns0 -- cat /proc/self/mountstats
netns exec -v   netns0 -- grep xprt /proc/self/mountstats
netns exec -v   netns0 -- ss -nt "dst $ServerIP1"

netns exec -vx0 netns0 -- umount -t nfs,nfs4 -a
netns exec -v   netns0 -- mount -t nfs,nfs4

#please clean test env:
netns del netns0
