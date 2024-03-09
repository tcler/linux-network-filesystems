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
vmname=fstest; for ((i=0;i<${#at};i++)); do [[ ${at[$i]} = -n ]] && vmname=${at[$((i+1))]}; done

### __prepare__ test env build
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -n '${s/^.* //;p}' <<<"$stdlog")

fs=${FSTYPE:-xfs}
case ${fs} in
xfs) MKFS_OPTIONS=${MKFS_OPTIONS:--m rmapbt=1,reflink=1};;
esac
mkfsOpt="${MKFS_OPTIONS} "
case $fs in ext*) mkfsOpt+=-F;; btrfs|xfs) mkfsOpt+=-f;; esac
trun vm create -n $vmname $distro --msize 4096 -p git,tmux,vim --nointeract -I=$imgf -f \
	--xdisk=16,${fs} --xdisk=16,${fs} --xdisk=16,${fs} "$@"

vm cpto -v  $vmname /usr/bin/xfstests-install.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/.
vm exec -vx $vmname -- tmux new -d 'yum-install-from-fedora.sh fsverity-utils'
vm exec -vx $vmname -- "xfstests-install.sh $NOURING" || exit 1

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vm exec -v $vmname -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vm exec -v $vmname -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"

devs=($(vm exec -v $vmname -- lsblk -nio NAME,LABEL | awk '$2 ~ /.*xdisk[0-9]/{print substr($1,3)}'))
vm exec -v $vmname -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=/dev/${devs[0]}
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=/dev/${devs[1]}
export SCRATCH_MNT=/mnt/xfstests_scratch
export LOGWRITES_DEV=/dev/${devs[2]}
export MKFS_OPTIONS='${MKFS_OPTIONS}'
export MOUNT_OPTIONS='${MOUNT_OPTIONS}'
EOF"
[[ -n "$MKFS_OPTIONS" ]] && vm exec -vx $vmname -- "for dev in ${devs[*]}; do mkfs.${fs} $mkfsOpt /dev/\$dev; done"

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
resdir=~/testres/$distro/xfstest
mkdir -p $resdir
{
  vm exec -v $vmname -- uname -r;
  #vm exec -v $vmname -- "cd /var/lib/xfstests/; ./check -n -g auto;"
  vm exec -v $vmname -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check ${TESTS};"
} |& tee $resdir/xfstests-${fs}.log