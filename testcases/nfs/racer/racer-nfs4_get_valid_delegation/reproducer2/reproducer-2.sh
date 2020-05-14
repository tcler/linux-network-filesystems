#!/bin/bash

distro=$1

[[ -z "$distro" ]] && {
	echo "Usage: $0 <distro> #e.g: $0 RHEL-8.2.0-20200404.0"
	exit
}

mkdir -p /nfsshare 
echo "/nfsshare *(rw,no_root_squash)" | sudo tee /etc/exports
sudo systemctl restart nfs-server

# Here we assume that kiss-vm[1] is already installed in your system
# [1] https://github.com/tcler/kiss-vm-ns
vm $distro -n nfsclient2 cpus=2 -msize=4000 --kdump -f -p "gcc make kernel-devel elfutils-libelf-devel" --nointeract
vm exec nfsclient2 -- mkdir /mnt/nfs
scp -o Batchmode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r nfsv4-open-race root@nfsclient2:

vm -v exec nfsclient2 -- 'cd nfsv4-open-race && ./run.sh 192.168.122.1:/nfsshare /mnt/nfs 281 #fix 281 if need'
