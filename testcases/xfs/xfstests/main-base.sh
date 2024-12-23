#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#xfstests xfs test, based on kiss-vm

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#env
#TESTS="generic/068 ..."
#DIFFLEN=-0
#NOURING=yes
#FSTYPE=xfs
#MKFS_OPTIONS=
#MOUNT_OPTIONS=

[[ $1 != -* ]] && { distro="$1"; shift 1; }; at=("$@")
distro=${distro:-9}
fs=${FSTYPE:-xfs}
vmname=fstest-${fs}; for ((i=0;i<${#at};i++)); do [[ ${at[$i]} = -n ]] && vmname=${at[$((i+1))]}; done
pkglist=git,tmux,vim

### __prepare__ test env build
if [[ "${*}" != *-[lL]* ]]; then
	stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
	imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
	insOpt="-I=$imgf"
fi

case ${fs} in
xfs)
	MKFS_OPTIONS=${MKFS_OPTIONS:--m rmapbt=1,reflink=1}
	grep -q '.?-b  *upk' <<<"${*}" && xfsprogs_upstream=yes
	pkglist+=,xfsdump,xfsprogs-xfs_scrub
	;;
esac
mkfsOpt="${MKFS_OPTIONS} "
case $fs in ext*) mkfsOpt+=-F;; btrfs|xfs) mkfsOpt+=-f;; esac
trun vm create -n $vmname $distro --msize 4G -p $pkglist --nointeract ${insOpt} -f \
	--xdisk=16,${fs} --xdisk=16,${fs} --xdisk=16,${fs} --ks-only-use='vda' "$@" || exit $?
timeout 300 vm port-available -w $vmname || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }
vmrunx - $vmname -- yum install -y ${pkglist//,/ }  #avoid cloud-init install pkglist fail

[[ "$xfsprogs_upstream" = yes ]] && {
	vm cpto -v  $vmname /usr/bin/xfsprogs-upstream-install.sh  /usr/bin/.
	vmrunx 0 $vmname -- "xfsprogs-upstream-install.sh nouring=$NOURING" || exit 1
}
vm cpto -v  $vmname /usr/bin/xfstests-install.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/.
vmrunx 0 $vmname -- tmux new -d 'yum-install-from-fedora.sh fsverity-utils devscripts-checkbashisms'
vmrunx 0 $vmname -- "xfstests-install.sh nouring=$NOURING" || exit 1

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vmrunx - $vmname -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vmrunx - $vmname -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"

devs=($(vmrunx - $vmname -- lsblk -nio NAME,LABEL | awk '$2 ~ /.*xdisk[0-9]/{print substr($1,3)}'))
vmrunx - $vmname -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=/dev/${devs[0]}
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=/dev/${devs[1]}
export SCRATCH_MNT=/mnt/xfstests_scratch
export LOGWRITES_DEV=/dev/${devs[2]}
export MKFS_OPTIONS='${MKFS_OPTIONS}'
export MOUNT_OPTIONS='${MOUNT_OPTIONS}'
export WORKAREA=/var/lib/xfstests
EOF"
vmrunx 0 $vmname -- "for dev in ${devs[*]}; do mkfs.${fs} $mkfsOpt /dev/\$dev; done"

distrodir=$(gen_distro_dir_name $vmname ${SUFFIX})
resdir=~/testres/${distrodir}/localfs/xfstests/$fs
mkdir -p $resdir
{
  vmrunx - $vmname -- uname -r;
  #vmrunx - $vmname -- "cd /var/lib/xfstests/; ./check -n -g auto;"
  trun -tmux=$$-vm.console -logpath=$resdir vm console $vmname
  vmrunx - $vmname -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check ${TESTS};"
  trun -x1-255 grep RI[P]: $resdir/*console.log
} &> >(tee $resdir/std.log)

tcnt
