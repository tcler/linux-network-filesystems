#!/bin/bash
#author: Jianhong Yin <yin-jianhong@163.com>
#example of nfs over Soft-RoCE

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-9}

Cleanup() {
	rm -f $stdlogf
	exit
}
trap Cleanup EXIT #SIGINT SIGQUIT SIGTERM
stdlogf=/tmp/nfs-o-soft-roce-$$.log
vm --downloadonly $distro 2>&1 | tee $stdlogf
imagef=$(sed -n '${s/^.* //; p}' $stdlogf)
if [[ ! -f "$imagef" ]]; then
	echo "{WARN} seems cloud image file download fail." >&2
	exit 1
fi

vmserv=nfs-o-soft-roce-serv
vmclnt=nfs-o-soft-roce-clnt

vm create -n $vmserv -p "libibverbs-utils perftest iproute tmux" -f $distro -i $imagef --nointeract
vm create -n $vmclnt -p "libibverbs-utils perftest iproute"      -f $distro -i $imagef --nointeract

vm exec -v $vmserv -- modprobe rdma_rxe
vm exec -v $vmserv -- rdma link add rxe0 type rxe netdev eth0
vm exec -v $vmserv -- rdma link
vm exec -v $vmserv -- mkdir -p /expdir
vm exec -v $vmserv -- "echo '/expdir *(rw,no_root_squash)' > /etc/exports"
vm exec -v $vmserv -- cat /etc/exports
vm exec -v $vmserv -- sed -i -e '/rdma/s/^#//' -e 's/rdma=n/rdma=y/' /etc/nfs.conf
vm exec -v $vmserv -- grep -v '^#' /etc/nfs.conf
vm exec -v $vmserv -- systemctl restart nfs-server
vm exec -v $vmserv -- showmount -e localhost
vm exec -v $vmserv -- cat /proc/fs/nfsd/portlist

vm exec -v $vmclnt -- modprobe rdma_rxe
vm exec -v $vmclnt -- rdma link add rxe0 type rxe netdev eth0
vm exec -v $vmclnt -- rdma link
vm exec -v $vmclnt -- mkdir -p /mnt/nfsmp
servAddr=$(vm ifaddr $vmserv|head -1)
vm exec -v -x $vmclnt -- mount $servAddr:/expdir /mnt/nfsmp -ordma,port=20049 -v
vm exec -v -x $vmclnt -- mount -t nfs4

vm exec -v $vmserv -- tmux new -s listen -d 'ib_send_bw -d rxe0'
vm exec -v $vmclnt -- ib_send_bw -d rxe0 $servAddr
