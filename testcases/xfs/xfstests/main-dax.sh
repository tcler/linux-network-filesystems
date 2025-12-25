#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#xfstests xfs test, based on kiss-vm

export LANG=C
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
PROG=$0; ARGS=("$@")
trap_try_again() { exec $PROG "${ARGS[@]}"; }

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
vmname=dax-fstest-${fs}; for ((i=0;i<${#at};i++)); do [[ ${at[$i]} = -n ]] && vmname=${at[$((i+1))]}; done
pkglist=git,tmux,vim,ndctl

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $vmname; }
cleanup() { stopvms 2>/dev/null; }
trap cleanup EXIT
trap try_again SIGUSR2

### __prepare__ test env build
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
[[ -n "${imgf}" ]] && insOpt=-I=$imgf

trun vm create -n $vmname $distro --msize 4G -p $pkglist --nointeract -f \
	--nvdimm='4098+2 4098+2' --xdisk=16,${fs} --ks-only-use='vda' "$@" $insOpt || exit $?
timeout 300 vm port-available -w $vmname || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }
vmrunx - $vmname -- yum install -y ${pkglist//,/ }  #avoid cloud-init install pkglist fail

[[ ${fs} = xfs ]] && grep -q '.?-b  *upk' <<<"${*}" && xfsprogs_upstream=yes
[[ "$xfsprogs_upstream" = yes ]] && {
	vm cpto -v  $vmname /usr/bin/xfsprogs-upstream-install.sh  /usr/bin/.
	vmrunx 0 $vmname -- "xfsprogs-upstream-install.sh nouring=$NOURING" || exit 1
}

vm cpto -v  $vmname /usr/bin/xfstests-install.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/.
vmrunx 0 $vmname -- "xfstests-install.sh $NOURING" || exit 1

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vmrunx - $vmname -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vmrunx - $vmname -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"

read logdev < <(vmrunx - $vmname -- lsblk -nio NAME,LABEL | awk '$2 ~ /.*xdisk[0-9]/{print substr($1,3)}')
pdevs=(pmem0 pmem1)
case ${fs} in
xfs)
	vmrunx - $vmname -- man mkfs.${fs} |& grep -q daxinherit && _daxOpt='-d daxinherit=1'
	MKFS_OPTIONS=${MKFS_OPTIONS:--m rmapbt=1,reflink=1 $_daxOpt}
	;;
esac
MOUNT_OPTIONS=${MOUNT_OPTIONS:--o dax=always}
vmrunx - $vmname -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=/dev/${pdevs[0]}
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=/dev/${pdevs[1]}
export SCRATCH_MNT=/mnt/xfstests_scratch
export LOGWRITES_DEV=/dev/$logdev
export MKFS_OPTIONS='${MKFS_OPTIONS}'
export MOUNT_OPTIONS='${MOUNT_OPTIONS}'
export WORKAREA=/var/lib/xfstests
EOF"
case $fs in ext*) MKFS_OPTIONS+=" -F";; btrfs|xfs) MKFS_OPTIONS+=" -f";; esac
vmrunx 0 $vmname -- ndctl list
#ref: https://nvdimm.wiki.kernel.org  /convert all your raw mode namespaces to fsdax mode/
vmrunx 0 $vmname -- 'for n in $(ndctl list | grep -o namespace...); do ndctl create-namespace -f -e $n --mode=memory; done'
vmrunx 0 $vmname -- ndctl list
vmrunx 0 $vmname -- "for dev in ${pdevs[*]:0:2}; do mkfs.${fs} $MKFS_OPTIONS /dev/\${dev}; done"
TESTS=${TESTS:--g dax}

_test=${fs}-dax
distrodir=$(gen_distro_dir_name $vmname ${SUFFIX}) || kill -s SIGUSR2 $$
resdir=~/testres/${distrodir}/localfs/xfstests/${_test}
mkdir -p $resdir
{
  vmrunx - $vmname -- uname -r;
  #vmrunx - $vmname -- "cd /var/lib/xfstests/; ./check -n -g auto;"
  trun -tmux=${_test}-xfstests-console -logf=$resdir/console.log vm console $vmname
  vmrunx - $vmname -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check ${TESTS};"
  console_check $resdir/console*.log
  stopvms
} &> >(tee $resdir/std.log)

tcnt
