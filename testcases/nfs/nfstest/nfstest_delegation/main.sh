#!/usr/bin/env bash
#

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#export share dir by nfs
_USER=$(whoami)
[[ $(id -u) = 0 && -n "$SUDO_USER" ]] && _USER=$SUDO_USER
nfsmp=/mnt/nfsmp

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
vmserv=nfs-server
vmclntx=nfs-clientx
vmclnt=nfs-client
vm create $distro -n $vmserv -m 4G -f -nointeract -p 'nfs-utils wireshark tmux' --sa
vm -v cpto $vmserv /usr/bin/make-nfs-server.sh .
vm -v exec $vmserv -- bash make-nfs-server.sh
vm -v exec $vmserv -- mkdir -p /nfsshare/rw/testdir
vm -v exec $vmserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $vmserv)

vm create $distro -n $vmclntx -m 4G -f -nointeract -p 'nfs-utils wireshark tmux' --sa
vm exec -v $vmclntx -- showmount -e $servaddr
clntxaddr=$(vm ifaddr $vmclntx)

vm create $distro -n $vmclnt -m 4G -f -nointeract -p 'nfs-utils wireshark tmux' --sa
vm exec -v $vmclnt -- showmount -e $servaddr
clntaddr=$(vm ifaddr $vmclnt)

#nfstest_cache
expdir=/nfsshare/rw
NIC=eth0
vm -v cpto $vmclnt /usr/bin/install-nfstest.sh .
vm -v exec $vmclnt -- bash install-nfstest.sh
vm -v exec $vmclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vm -v exec $vmclnt -- ip link set "$NIC" promisc on
vm -v exec $vmclnt -- ssh-copy-id -oStrictHostKeyChecking=no -f $clntxaddr
vm -v exec $vmclnt -- nfstest_delegation --server $servaddr --client $clntxaddr --client-nfsvers=4.0,4.1,4.2 --export=$expdir --nfsversion=4.2 "$@"
