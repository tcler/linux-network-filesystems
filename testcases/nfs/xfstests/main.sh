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

#download image file
if [[ "${*}" != *-[lL]* ]]; then
	stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
	imgf=$(sed -n '${/^image url/{s/^.* //;p}}' <<<"$stdlog")
	insOpt="-I=$imgf"
fi

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p ${pkglist}     $insOpt "$@"
trun       vm create $distro -n $nfsclnt -m 4G -f -nointeract -p ${pkglist},git $insOpt "$@" || exit $?
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 10; done
servaddr=$(vm ifaddr $nfsserv)

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh .
tmux new -s nfsServer -d "vm exec -v $nfsserv -- bash make-nfs-server.sh"

vm cpto -v  $nfsclnt /usr/bin/xfstests-install.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/.
vm exec -vx $nfsclnt -- tmux new -d 'yum-install-from-fedora.sh fsverity-utils'
vm exec -vx $nfsclnt -- "xfstests-install.sh nouring=$NOURING" || exit 1

while tmux ls | grep nfsServer; do sleep 8; done
vm exec -vx $nfsclnt -- showmount -e $servaddr

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vm exec -v $nfsclnt -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vm exec -v $nfsclnt -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"
vm exec -v $nfsclnt -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=$servaddr:/nfsshare/qe
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=$servaddr:/nfsshare/devel
export SCRATCH_MNT=/mnt/xfstests_scratch
export WORKAREA=/var/lib/xfstests
EOF"

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
resdir=~/testres/$distro/xfstest
mkdir -p $resdir
{
  vm exec -v $nfsclnt -- uname -r;
  vm exec -v $nfsclnt -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check -nfs ${TESTS};"
} |& tee $resdir/xfstests-nfs.log

vm stop $nfsserv $nfsclnt
