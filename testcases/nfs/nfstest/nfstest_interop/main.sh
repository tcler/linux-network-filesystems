#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=nfs-server
nfsclnt=nfs-client
vm create $distro -n $nfsserv -m 4G -f -nointeract -p 'nfs-utils wireshark' --sa
vm create $distro -n $nfsclnt -m 4G -f -nointeract -p 'nfs-utils wireshark' --sa

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin
vm exec -v $nfsserv -- make-nfs-server.sh
vm exec -v $nfsserv -- mkdir -p /nfsshare/rw/testdir
vm exec -v $nfsserv -- touch /nfsshare/rw/testdir/file{1..128}

servaddr=$(vm ifaddr $nfsserv)
vm exec -v $nfsclnt -- showmount -e $servaddr

#nfstest_posix
expdir=/nfsshare/rw
nfsmp=/mnt/nfsmp
NIC=eth0
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin
vm exec -v $nfsclnt -- install-nfstest.sh
vm exec -v $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>~/.bashrc'
vm exec -v $nfsclnt -- ip link set "$NIC" promisc on
vm exec -v $nfsclnt -- nfstest_interop --server ${servaddr} --export=${expdir} --nfsversion=4.2
