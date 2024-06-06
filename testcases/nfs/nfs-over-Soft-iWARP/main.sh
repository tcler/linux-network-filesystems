#!/bin/bash
#author: Jianhong Yin <yin-jianhong@163.com>
#example of nfs over Soft-iWARP on RHEL-8.2 and after

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-9}; shift 1

stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

vmserv=nfs-o-soft-iwarp-serv
vmclnt=nfs-o-soft-iwarp-clnt

### __prepare__ test env build
pkgs=firewalld,libibverbs-utils,perftest,iproute,tmux
trun -tmux vm create -n $vmserv -p $pkgs -f $distro -I=$imgf --nointeract "$@"
trun       vm create -n $vmclnt -p $pkgs -f $distro -I=$imgf --nointeract "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $vmserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

### __main__ test start
distrodir=$(gen_distro_dir_name $vmclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfs-function
mkdir -p $resdir
{
NIC=$(vm exec $vmserv -- nmcli -g DEVICE connection show|sed -n 2p)
vmrunx - $vmserv -- modprobe siw
vmrunx - $vmserv -- rdma link add siw0 type siw netdev $NIC
vmrunx - $vmserv -- rdma link
vmrunx - $vmserv -- mkdir -p /expdir
vmrunx - $vmserv -- "echo '/expdir *(rw,no_root_squash)' > /etc/exports"
vmrunx - $vmserv -- cat /etc/exports
vmrunx - $vmserv -- sed -i -e '/rdma/s/^#//' -e 's/rdma=n/rdma=y/' /etc/nfs.conf
vmrunx - $vmserv -- grep -v '^#' /etc/nfs.conf
vmrunx - $vmserv -- systemctl restart nfs-server
vmrunx - $vmserv -- "firewall-cmd --permanent --add-service={mountd,nfs,rpc-bind}; firewall-cmd --reload"
vmrunx - $vmserv -- systemctl stop firewalld   #seems this's necessary for rdma, fixme if it's not true
vmrunx - $vmserv -- showmount -e localhost
vmrunx - $vmserv -- cat /proc/fs/nfsd/portlist

vmrunx - $vmclnt -- modprobe siw
vmrunx - $vmclnt -- rdma link add siw0 type siw netdev $NIC
vmrunx - $vmclnt -- rdma link
vmrunx - $vmclnt -- mkdir -p /mnt/nfsmp
servAddr=$(vm ifaddr $vmserv|head -1)
vmrunx 0 $vmclnt -- showmount -e $servAddr
vmrunx - $vmclnt -- systemctl stop firewalld   #seems this's necessary for rdma, fixme if it's not true
vmrunx 0 $vmclnt -- mount $servAddr:/expdir /mnt/nfsmp -ordma,port=20049 -v
vmrunx 0 $vmclnt -- mount -t nfs4

vmrunx - $vmserv -- tmux new -s listen -d 'ib_write_bw -d siw0 -R -n 5 -s 1500'
vmrunx - $vmclnt -- ib_write_bw -d siw0 -R -n 5 -s 1500 $servAddr

} |& tee $resdir/nfs-soft-iwarp.log
