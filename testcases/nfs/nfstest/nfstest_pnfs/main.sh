#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsclnt=nfs-client
nfsmp=/mnt/nfsmp

#create netapp ontap-simulator
make-ontap-simulator.sh
servaddr=192.168.20.21

#create vm as nfs client
vm create $distro -n $nfsclnt -m 4G -f -nointeract --net ontap2-data -p 'nfs-utils expect iproute-tc kernel-modules-extra' --sa
vm exec -v $nfsclnt -- showmount -e $servaddr
vm exec -v $nfsclnt -- mkdir -p $nfsmp

#nfstest_pnfs
expdir=/share2
NIC=eth0
vm -v cpto $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/.
vm -v exec $nfsclnt -- install-nfstest.sh
vm -v exec $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>~/.bashrc'
vm -v exec $nfsclnt -- ip link set "$NIC" promisc on
vm -v exec $nfsclnt -- nfstest_pnfs --server $servaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --nfsversion=4.2 "$@"
