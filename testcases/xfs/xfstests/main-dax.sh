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
fs=${FSTYPE:-xfs}

### __prepare__ test env build
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -n '${s/^.* //;p}' <<<"$stdlog")

trun vm create -n $vmname $distro --msize 8G -p git,tmux,vim,ndctl --nointeract -I=$imgf -f \
	--nvdimm='1024+2 1024+2' --xdisk=16,${fs} --kernel-opts='memmap=10240M!4G memmap=10240M!6G' "$@"

vm cpto -v  $vmname /usr/bin/xfstests-install.sh /usr/bin/make-nfs-server.sh /usr/bin/.
vm exec -vx $vmname -- "xfstests-install.sh $NOURING" || exit 1

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vm exec -v $vmname -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vm exec -v $vmname -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"

read logdev < <(vm exec -v $vmname -- lsblk -nio NAME,LABEL | awk '$2 ~ /.*xdisk[0-9]/{print substr($1,3)}')
pdevs=($(vm exec -v $vmname -- lsblk -nio NAME,SIZE | awk '/pmem/ && $2 ~ /[0-9]G/ {print $1}'))
MKFS_OPTIONS=${MKFS_OPTIONS:--m rmapbt=1,reflink=0 -d daxinherit=1}
MOUNT_OPTIONS=${MOUNT_OPTIONS:--o dax=always}
vm exec -v $vmname -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=/dev/${pdevs[0]}
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=/dev/${pdevs[1]}
export SCRATCH_MNT=/mnt/xfstests_scratch
export LOGWRITES_DEV=/dev/$logdev
export MKFS_OPTIONS='${MKFS_OPTIONS}'
export MOUNT_OPTIONS='${MOUNT_OPTIONS}'
EOF"
case $fs in ext*) MKFS_OPTIONS+=" -F";; btrfs|xfs) MKFS_OPTIONS+=" -f";; esac
vm exec -vx $vmname -- ndctl list
vm exec -vx $vmname -- "for dev in ${pdevs[*]:0:2}; do mkfs.${fs} $MKFS_OPTIONS /dev/\${dev}; done"
TESTS=${TESTS:--g dax}

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
resdir=~/testres/$distro/xfstest
mkdir -p $resdir
{
  vm exec -v $vmname -- uname -r;
  #vm exec -v $vmname -- "cd /var/lib/xfstests/; ./check -n -g auto;"
  vm exec -v $vmname -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check ${TESTS};"
} |& tee $resdir/xfstests-${fs}-dax.log
