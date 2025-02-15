#!/bin/bash
#author: Jianhong Yin <yin-jianhong@163.com>
#example of nfs over Soft-RoCE

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-9}; shift

stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
[[ -n "${imgf}" ]] && insOpt=-I=$imgf

nfsserv=nfs-o-soft-roce-serv
nfsclnt=nfs-o-soft-roce-clnt

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

### __prepare__ test env build
pkgs=firewalld,libibverbs-utils,perftest,iproute,tmux
trun -tmux vm create -n $nfsserv -p $pkgs -f $distro --nointeract "$@" $insOpt
trun       vm create -n $nfsclnt -p $pkgs -f $distro --nointeract "$@" $insOpt
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $nfsserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

### __main__ test start
_test=soft-roce
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin/get-if-by-ip.sh /usr/bin/
vm cpto -v $nfsclnt /usr/bin/xfstests-install.sh /usr/bin/get-if-by-ip.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/
#-------------------------------------------------------------------------------
#base mount test
servAddr=$(vm ifaddr $nfsserv|head -1)
NIC=$(vm exec $nfsserv -- get-if-by-ip.sh $servAddr)
vmrunx 0 $nfsserv -- modprobe rdma_rxe || exit 2
vmrunx - $nfsserv -- rdma link add rxe0 type rxe netdev $NIC
vmrunx - $nfsserv -- rdma link
vmrunx - $nfsserv -- mkdir -p /expdir
vmrunx - $nfsserv -- "echo '/expdir *(rw,no_root_squash)' > /etc/exports"
vmrunx - $nfsserv -- cat /etc/exports
vmrunx - $nfsserv -- sed -i -e '/rdma/s/^#//' -e 's/rdma=n/rdma=y/' /etc/nfs.conf
vmrunx - $nfsserv -- grep -v '^#' /etc/nfs.conf
vmrunx - $nfsserv -- systemctl restart nfs-server
vmrunx - $nfsserv -- "firewall-cmd --permanent --add-service={mountd,nfs,rpc-bind}; firewall-cmd --reload"
vmrunx - $nfsserv -- systemctl stop firewalld   #seems this's necessary for rdma, fixme if it's not true
vmrunx - $nfsserv -- showmount -e localhost
vmrunx - $nfsserv -- cat /proc/fs/nfsd/portlist

read clntaddr < <(vm ifaddr $nfsclnt | grep ${servAddr%.*})
NIC=$(vm exec $nfsclnt -- get-if-by-ip.sh $clntaddr)
vmrunx - $nfsclnt -- modprobe rdma_rxe
vmrunx - $nfsclnt -- rdma link add rxe0 type rxe netdev $NIC
vmrunx - $nfsclnt -- rdma link
vmrunx - $nfsclnt -- mkdir -p /mnt/nfsmp
vmrunx 0 $nfsclnt -- showmount -e $servAddr
vmrunx - $nfsclnt -- systemctl stop firewalld   #seems this's necessary for rdma, fixme if it's not true
vmrunx 0 $nfsclnt -- mount $servAddr:/expdir /mnt/nfsmp -ordma,port=20049 -v
vmrunx 0 $nfsclnt -- mount -t nfs4
vmrunx 0 $nfsclnt -- umount /mnt/nfsmp

##nconnect over rdma test
for N in 1 4 16; do
	vmrunx 0 $nfsclnt -- mount $servAddr:/expdir /mnt/nfsmp -ordma,port=20049,nconnect=$N
	vmrunx 0 $nfsclnt -- "test \$(grep xprt /proc/self/mountstats | wc -l) -eq $N"
	vmrunx 0 $nfsclnt -- mount -t nfs4
	vmrunx 0 $nfsclnt -- umount /mnt/nfsmp
done
for N in 0 17; do
	vmrunx 1-255 $nfsclnt -- mount $servAddr:/expdir /mnt/nfsmp -ordma,port=20049,nconnect=$N
done
vmrunx 0 $nfsclnt -- uname -a

vmrunx - $nfsserv -- tmux new -s listen -d 'ib_send_bw -d rxe0'
vmrunx - $nfsclnt -- ib_send_bw -d rxe0 $servAddr

#-------------------------------------------------------------------------------
##xfstest
if [[ $XFSTEST = yes ]]; then
	tmux new -s roceNfsServer -d "vm exec -v $nfsserv -- bash make-nfs-server.sh"

	vmrunx 0 $nfsclnt -- tmux new -d 'yum-install-from-fedora.sh fsverity-utils'
	vmrunx 0 $nfsclnt -- "xfstests-install.sh nouring=$NOURING" || exit 1
	while tmux ls | grep roceNfsServer; do sleep 8; done
	vmrunx 0 $nfsclnt -- showmount -e $servAddr

	TESTS=${TESTS:--g quick}
	#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
	vmrunx - $nfsclnt -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
	vmrunx - $nfsclnt -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"
	vmrunx - $nfsclnt -- "cat >/var/lib/xfstests/local.config <<EOF
	export TEST_DEV=$servAddr:/nfsshare/qe
	export TEST_DIR=/mnt/xfstests_test
	export TEST_FS_MOUNT_OPTS='-ordma,port=20049'
	export MOUNT_OPTIONS='-ordma,port=20049'
	export SCRATCH_DEV=$servAddr:/nfsshare/devel
	export SCRATCH_MNT=/mnt/xfstests_scratch
	export WORKAREA=/var/lib/xfstests
	EOF"

	vmrunx - $nfsclnt -- uname -r;
	vmrunx - $nfsclnt -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check -nfs ${TESTS};"
fi

stopvms
} &> >(tee $resdir/std.log)

tcnt
