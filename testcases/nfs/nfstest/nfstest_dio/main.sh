#!/usr/bin/env bash
#

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#export share dir by nfs
_USER=$(whoami)
[[ $(id -u) = 0 && -n "$SUDO_USER" ]] && _USER=$SUDO_USER
nfsmp=/mnt/nfsmp

#create nfs-server vm
distro=${1:-CentOS-9-stream}; shift;
vmserv=nfs-server
vmclnt=nfs-client
vm create $distro -n $vmserv -m 4G -f -nointeract -p 'nfs-utils wireshark tmux' --sa
vm -v cpto $vmserv /usr/bin/make-nfs-server.sh .
vm -v exec $vmserv -- bash make-nfs-server.sh
vm -v exec $vmserv -- mkdir -p /nfsshare/rw/testdir
vm -v exec $vmserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $vmserv)

vm create $distro -n $vmclnt -m 4G -f -nointeract -p 'nfs-utils wireshark tmux' --sa
vm exec -v $vmclnt -- showmount -e $servaddr
vm exec -v $vmclnt -- mkdir -p $nfsmp

#nfstest_alloc
expdir=/nfsshare/rw
NIC=eth0
vm -v cpto $vmclnt /usr/bin/install-nfstest.sh .
vm -v exec $vmclnt -- bash install-nfstest.sh
vm -v exec $vmclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vm -v exec $vmclnt -- ip link set "$NIC" promisc on
vm -v exec $vmclnt -- getconf PAGESIZE
pgsize=$(vm exec $vmclnt -- getconf PAGESIZE)
vm -v exec $vmclnt -- nfstest_alloc --server $servaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --rsize=$pgsize --wsize=$pgsize --nfsversion=4.2 "$@"
