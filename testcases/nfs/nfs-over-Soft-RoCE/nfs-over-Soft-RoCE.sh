#!/bin/bash
#author: Jianhong Yin <yin-jianhong@163.com>
#example of nfs over Soft-RoCE

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-9}; shift

stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -n '${/^image url/{s/^.* //;p}}' <<<"$stdlog")

vmserv=nfs-o-soft-roce-serv
vmclnt=nfs-o-soft-roce-clnt

trun -tmux vm create -n $vmserv -p libibverbs-utils,perftest,iproute,tmux -f $distro -I=$imgf --nointeract "$@"
trun       vm create -n $vmclnt -p libibverbs-utils,perftest,iproute      -f $distro -I=$imgf --nointeract "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

NIC=$(vm exec -v $vmserv -- nmcli -g DEVICE connection show|head -1)

vm exec -v $vmserv -- modprobe rdma_rxe
vm exec -v $vmserv -- rdma link add rxe0 type rxe netdev $NIC
vm exec -v $vmserv -- rdma link
vm exec -v $vmserv -- mkdir -p /expdir
vm exec -v $vmserv -- "echo '/expdir *(rw,no_root_squash)' > /etc/exports"
vm exec -v $vmserv -- cat /etc/exports
vm exec -v $vmserv -- sed -i -e '/rdma/s/^#//' -e 's/rdma=n/rdma=y/' /etc/nfs.conf
vm exec -v $vmserv -- grep -v '^#' /etc/nfs.conf
vm exec -v $vmserv -- systemctl restart nfs-server
vm exec -v $vmserv -- firewall-cmd --permanent --add-service={mountd,nfs,rpc-bind}
vm exec -v $vmserv -- firewall-cmd --reload
vm exec -v $vmserv -- showmount -e localhost
vm exec -v $vmserv -- cat /proc/fs/nfsd/portlist

vm exec -v $vmclnt -- modprobe rdma_rxe
vm exec -v $vmclnt -- rdma link add rxe0 type rxe netdev $NIC
vm exec -v $vmclnt -- rdma link
vm exec -v $vmclnt -- mkdir -p /mnt/nfsmp
servAddr=$(vm ifaddr $vmserv|head -1)
vm exec -v -x $vmclnt -- mount $servAddr:/expdir /mnt/nfsmp -ordma,port=20049 -v
vm exec -v -x $vmclnt -- mount -t nfs4

vm exec -v $vmserv -- tmux new -s listen -d 'ib_send_bw -d rxe0'
vm exec -v $vmclnt -- ib_send_bw -d rxe0 $servAddr
