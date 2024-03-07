#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#xfstests xfs test, based on kiss-vm

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#env
#TESTS="generic/068 ..."
#DIFFLEN=-0
#NOURING=yes
#FSTYPE=xfs
#MKFS_OPTS=

[[ $1 != -* ]] && { distro="$1"; shift 1; }; at=("$@")
distro=${distro:-9}
vmname=fstest; for ((i=0;i<${#at};i++)); do [[ ${at[$i]} = -n ]] && vmname=${at[$((i+1))]}; done

### __prepare__ test env build
stdlog=$(trun vm create $distro --downloadonly |& tee /dev/tty)
imgf=$(sed -n '${s/^.* //;p}' <<<"$stdlog")

fs=${FSTYPE:-xfs}
mkfsOpt="${MKFS_OPTS} "
case $fs in ext*) mkfsOpt+=-F;; btrfs|xfs) mkfsOpt+=-f;; esac
trun vm create -n $vmname $distro --msize 4096 -p git,tmux,vim --nointeract -I=$imgf -f \
	--xdisk=16,${fs},bus=sata --xdisk=16,${fs},bus=sata --xdisk=16,${fs},bus=sata "$@"

vm cpto -v  $vmname /usr/bin/xfstests-install.sh /usr/bin/make-nfs-server.sh /usr/bin/.
vm exec -vx $vmname -- "xfstests-install.sh $NOURING" || exit 1

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vm exec -v $vmname -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vm exec -v $vmname -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"
vm exec -v $vmname -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=/dev/sda1
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=/dev/sdb1
export SCRATCH_MNT=/mnt/xfstests_scratch
export LOGWRITES_DEV=/dev/sdc1
EOF"
[[ -n "$MKFS_OPTS" ]] && vm exec -vx $vmname -- 'for dev in /dev/sd{a..c}1; do '"mkfs.${fs} $mkfsOpt"' $dev; done'

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
resdir=~/testres/$distro/nfstest
mkdir -p $resdir
{
  vm exec -v $vmname -- uname -r;
  #vm exec -v $vmname -- "cd /var/lib/xfstests/; ./check -n -g auto;"
  vm exec -v $vmname -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check ${TESTS};"
} |& tee $resdir/xfstests-xfs.log
