#!/bin/bash

distro=$1

[[ -z "$distro" ]] && {
	echo "Usage: Prog <distro>"
	exit
}

mkdir -p /nfsshare 
echo "/nfsshare *(rw,no_root_squash)" >/etc/exports
systemctl restart nfs-server

vm $distro -n nfsclient2 cpus=2 -msize=4000 --kdump -f -p "vim gcc make kernel-devel elfutils-libelf" --nointeract
vm exec nfsclient2 -- mkdir /mnt/nfs
scp -o Batchmode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r nfsv4-open-race root@nfsclient2:

vm exec nfsclient2 -- 'cd nfsv4-open-race && ./run.sh 192.168.122.1:/nfsshare /mnt/nfs 0x306'
