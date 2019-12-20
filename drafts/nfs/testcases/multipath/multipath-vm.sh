#!/bin/bash
#ref: https://packetpushers.net/multipathing-nfs4-1-kvm

baseurl=https://raw.githubusercontent.com/tcler/kiss-vm-ns/master
curl -s -o /usr/local/bin/vm -L ${baseurl}/kiss-vm
chmod +x /usr/local/bin/vm

ExportDir=/nfsshare
MountPoint=/mnt/nfs
distro=${distro:-$1}

[[ -z "$distro" ]] && {
	echo "Usage: $0 <distro>"
	exit 1
}

vm --prepare

vm net netname=net10 brname=vm-vbr10 subnet=10
vm netinfo net10
vm create "$distro" -n serv --saveimage -p "nfs-utils" --nointeract --net default --net net10 -f
vm create "$distro" -n clnt --saveimage -p "nfs-utils" --nointeract --net default --net net10 -f
S=$(vm --getvmname "$distro" -n serv)
C=$(vm --getvmname "$distro" -n clnt)
Saddr1=$(vm ifaddr $S|grep '192.168.122\.')
Saddr2=$(vm ifaddr $S|grep '192.168.10\.')

vm exec -v $S -- mkdir -p $ExportDir
vm exec -v $S -- touch $ExportDir/testfile
vm exec -v $S -- "echo '$ExportDir *(rw,no_root_squash,security_label)' >/etc/exports"
vm exec -v $S -- systemctl restart nfs-server
vm exec -v $C -- mkdir -p $MountPoint
vm exec -v $C -- showmount -e $Saddr1
vm exec -v $C -- mount -vvv $Saddr1:/ $MountPoint
vm exec -v $C -- showmount -e $Saddr2
vm exec -v $C -- mount -vvv $Saddr2:/ $MountPoint
vm exec -v $C -- mount -t nfs4

#please clean test env:
vm del $C
vm del $S
vm netdel net10
