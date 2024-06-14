#!/bin/bash
#author: Jianhong Yin <yin-jianhong@163.com>
#example of nfs over Soft-RoCE

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-9}; shift

stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

vmserv=nfs-o-soft-roce-serv
vmclnt=nfs-o-soft-roce-clnt

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
#-------------------------------------------------------------------------------
#base mount test
servAddr=$(vm ifaddr $vmserv|head -1)
NIC=any  #$(vm exec $vmserv -- nmcli -g DEVICE connection show|sed -n 2p)
vmrunx 0 $vmserv -- modprobe rdma_rxe || exit 2
vmrunx - $vmserv -- rdma link add rxe0 type rxe netdev $NIC
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

vmrunx - $vmclnt -- modprobe rdma_rxe
vmrunx - $vmclnt -- rdma link add rxe0 type rxe netdev $NIC
vmrunx - $vmclnt -- rdma link
vmrunx - $vmclnt -- mkdir -p /mnt/nfsmp
vmrunx 0 $vmclnt -- showmount -e $servAddr
vmrunx - $vmclnt -- systemctl stop firewalld   #seems this's necessary for rdma, fixme if it's not true
vmrunx 0 $vmclnt -- mount $servAddr:/expdir /mnt/nfsmp -ordma,port=20049 -v
vmrunx 0 $vmclnt -- mount -t nfs4
vmrunx 0 $vmclnt -- umount /mnt/nfsmp

vmrunx - $vmserv -- tmux new -s listen -d 'ib_send_bw -d rxe0'
vmrunx - $vmclnt -- ib_send_bw -d rxe0 $servAddr

#-------------------------------------------------------------------------------
##xfstest
vm cpto -v $vmserv /usr/bin/make-nfs-server.sh .
tmux new -s roceNfsServer -d "vm exec -v $vmserv -- bash make-nfs-server.sh"

vm cpto -v $vmclnt /usr/bin/xfstests-install.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/.
vmrunx 0 $vmclnt -- tmux new -d 'yum-install-from-fedora.sh fsverity-utils'
vmrunx 0 $vmclnt -- "xfstests-install.sh nouring=$NOURING" || exit 1
while tmux ls | grep roceNfsServer; do sleep 8; done
vmrunx 0 $vmclnt -- showmount -e $servAddr

TESTS=${TESTS:--g quick}
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vmrunx - $vmclnt -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vmrunx - $vmclnt -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"
vmrunx - $vmclnt -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=$servAddr:/nfsshare/qe
export TEST_DIR=/mnt/xfstests_test
export TEST_FS_MOUNT_OPTS='-ordma,port=20049'
export MOUNT_OPTIONS='-ordma,port=20049'
export SCRATCH_DEV=$servAddr:/nfsshare/devel
export SCRATCH_MNT=/mnt/xfstests_scratch
export WORKAREA=/var/lib/xfstests
EOF"

vmrunx - $vmclnt -- uname -r;
vmrunx - $vmclnt -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check -nfs ${TESTS};"

} |& tee $resdir/nfs-soft-roce.log
