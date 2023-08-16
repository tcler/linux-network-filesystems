#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv1=nfs-server1
nfsserv2=nfs-server2
nfsclnt=nfs-client

#create nfs server,client vm
vm create $distro -n $nfsserv1 -f -nointeract -p 'vim nfs-utils' --sa
vm create $distro -n $nfsserv2 -f -nointeract -p 'vim nfs-utils' --sa
vm create $distro -n $nfsclnt  -f -nointeract -p 'vim nfs-utils tcpdump iproute-tc kernel-modules-extra' --sa
vm cpto -v $nfsserv1 /usr/bin/make-nfs-server.sh /usr/bin/.
vm cpto -v $nfsserv2 /usr/bin/make-nfs-server.sh /usr/bin/.
vm exec -vx $nfsserv1 -- make-nfs-server.sh
vm exec -vx $nfsserv2 -- make-nfs-server.sh
vm exec -vx $nfsserv1 -- "echo Y >/sys/module/nfsd/parameters/inter_copy_offload_enable"
vm exec -vx $nfsserv2 -- "echo Y >/sys/module/nfsd/parameters/inter_copy_offload_enable"

serv1addr=$(vm ifaddr $nfsserv1)
serv2addr=$(vm ifaddr $nfsserv2)
vm exec -v $nfsclnt -- showmount -e $serv1addr
vm exec -v $nfsclnt -- showmount -e $serv2addr

#nfstest_ssc
nfsmp=/mnt/nfsmp
expdir=/nfsshare/rw
NIC=eth0
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh /usr/bin/.
vm exec -v $nfsclnt -- install-nfstest.sh
vm exec -v $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vm exec -v $nfsclnt -- nfstest_ssc -s $serv1addr -e /nfsshare/rw --dst-server $serv2addr --dst-export /nfsshare/async inter
