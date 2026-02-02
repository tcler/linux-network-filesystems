#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#xfstests xfs test, based on kiss-vm

export LANG=C
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
PROG=$0; ARGS=("$@")
trap_try_again() { exec $PROG "${ARGS[@]}"; }
Usage() {
	cat <<-EOF
	Usage:
	  [ENV] $PROG <9|10|CentOS-10-stream|RHEL-10.2-20251217.0> [vm-create-options]
	Example:
	  $PROG RHEL-10.2-20251217.0 --brewinstall=-debugk
	  KEEPVMS=yes NOURING=no TESTS="-i 5 generic/751" $PROG RHEL-10.2-20251217.0 --brewinstall=-debugk
	EOF
}

#env:
#TESTS="-g quick ..."
#DIFFLEN=-0
#NOURING=yes

[[ $1 != -* ]] && { distro="$1"; shift; }
[[ -z "$distro" ]] && { Usage >&2; exit 1; }
nfsserv=fstest-nfsserv
nfsclnt=fstest-nfsclnt
pkglist=vim,nfs-utils,tmux
NFSSHARE=/nfsshare
NFSROOT=${NFSROOT}

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap cleanup EXIT
trap try_again SIGUSR2

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
[[ -n "${imgf}" ]] && insOpt=-I=$imgf

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p ${pkglist} --xdisk 10,xfs --xdisk 10,xfs "$@" $insOpt
trun       vm create $distro -n $nfsclnt -m 12G -f -nointeract -p ${pkglist},git "$@" $insOpt || exit $?
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 10; done
servaddr=$(vm ifaddr $nfsserv|head -1)

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin
tmux new -s nfsServer -d "vm exec -v $nfsserv -- make-nfs-server.sh --prefix=$NFSSHARE --nfsroot=$NFSROOT"

vm cpto -v  $nfsclnt /usr/bin/xfstests-install.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/.
vmrunx 0 $nfsclnt -- tmux new -d 'yum-install-from-fedora.sh fsverity-utils'
vmrunx 0 $nfsclnt -- "xfstests-install.sh nouring=$NOURING" || exit 1

while tmux ls | grep nfsServer; do sleep 8; done
vmrunx 0 $nfsclnt -- showmount -e $servaddr

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vmrunx - $nfsclnt -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vmrunx - $nfsclnt -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"
vmrunx - $nfsclnt -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=$servaddr:$NFSSHARE/qe
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=$servaddr:$NFSSHARE/devel
export SCRATCH_MNT=/mnt/xfstests_scratch
export WORKAREA=/var/lib/xfstests
EOF"

_test=xfstests-nfs
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX}) || kill -s SIGUSR2 $$
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  trun -tmux=${_test}-console-$nfsserv -logf=$resdir/console-$nfsserv.log vm console $nfsserv
  trun -tmux=${_test}-console-$nfsclnt -logf=$resdir/console-$nfsclnt.log vm console $nfsclnt
  vmrunx - $nfsclnt -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check -nfs ${TESTS};"
  console_check $resdir/console*.log
  stopvms
} &> >(tee $resdir/std.log)

tcnt
