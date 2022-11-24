#!/bin/bash
#author: Jianhong Yin <yin-jianhong@163.com>
#example of nfs over Soft-iWARP on RHEL-8.2 and after

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-CentOS-8-stream}

Cleanup() {
	rm -f $stdlogf
	exit
}
trap Cleanup EXIT #SIGINT SIGQUIT SIGTERM
stdlogf=/tmp/nfs-o-soft-iwarp-$$.log
vm --downloadonly $distro 2>&1 | tee $stdlogf
imagef=$(sed -n '${s/^.* //; p}' $stdlogf)
if [[ ! -f "$imagef" ]]; then
	echo "{WARN} seems cloud image file download fail." >&2
	exit 1
fi

vmserv=nfs-o-soft-iwarp-serv
vmclnt=nfs-o-soft-iwarp-clnt

vm create -n $vmserv -p "libibverbs-utils perftest iproute tmux" -f $distro -i $imagef --nointeract
vm create -n $vmclnt -p "libibverbs-utils perftest iproute"      -f $distro -i $imagef --nointeract

vm exec -v $vmserv -- modprobe siw
vm exec -v $vmserv -- rdma link add siw0 type siw netdev eth0
vm exec -v $vmserv -- rdma link
vm exec -v $vmserv -- mkdir -p /expdir
vm exec -v $vmserv -- "echo '/expdir *(rw,no_root_squash)' > /etc/exports"
vm exec -v $vmserv -- cat /etc/exports
vm exec -v $vmserv -- sed -i -e '/rdma/s/^#//' -e 's/rdma=n/rdma=y/' /etc/nfs.conf
vm exec -v $vmserv -- grep -v '^#' /etc/nfs.conf
vm exec -v $vmserv -- systemctl restart nfs-server
vm exec -v $vmserv -- showmount -e localhost
vm exec -v $vmserv -- cat /proc/fs/nfsd/portlist

vm exec -v $vmclnt -- modprobe siw
vm exec -v $vmclnt -- rdma link add siw0 type siw netdev eth0
vm exec -v $vmclnt -- rdma link
vm exec -v $vmclnt -- mkdir -p /mnt/nfsmp
servAddr=$(vm ifaddr $vmserv|head -1)
vm exec -v -x $vmclnt -- mount $servAddr:/expdir /mnt/nfsmp -ordma,port=20049 -v
vm exec -v -x $vmclnt -- mount -t nfs4

vm exec -v $vmserv -- tmux new -s listen -d 'ib_write_bw -d siw0 -R -n 5 -s 1500'
vm exec -v $vmclnt -- ib_write_bw -d siw0 -R -n 5 -s 1500 $servAddr
