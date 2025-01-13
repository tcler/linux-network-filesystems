#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#xfstests xfs test, based on kiss-vm

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#env
#TESTS="-g quick ..."
#DIFFLEN=-0
#NOURING=yes

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=fstest-nfsserv
nfsclnt=fstest-nfsclnt
pkglist=vim,nfs-utils,tmux

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

#download image file
if [[ "${*}" != *-[lL]* ]]; then
	stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
	imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
	insOpt="-I=$imgf"
fi

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p ${pkglist}     $insOpt "$@"
trun       vm create $distro -n $nfsclnt -m 6G -f -nointeract -p ${pkglist},git $insOpt "$@" || exit $?
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 10; done
servaddr=$(vm ifaddr $nfsserv|head -1)

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh .
tmux new -s nfsServer -d "vm exec -v $nfsserv -- bash make-nfs-server.sh"

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
export TEST_DEV=$servaddr:/nfsshare/qe
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=$servaddr:/nfsshare/devel
export SCRATCH_MNT=/mnt/xfstests_scratch
export WORKAREA=/var/lib/xfstests
EOF"

_test=xfstests-nfs
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  trun -tmux=${_test}-console-$nfsserv -logf=$resdir/console-$nfsserv.log vm console $nfsserv
  trun -tmux=${_test}-console-$nfsclnt -logf=$resdir/console-$nfsclnt.log vm console $nfsclnt
  vmrunx - $nfsclnt -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check -nfs ${TESTS};"
  trun -x1-255 grep RI[P]: $resdir/*console.log
  stopvms
} &> >(tee $resdir/std.log)

tcnt
