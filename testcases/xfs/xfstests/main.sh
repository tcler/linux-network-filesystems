#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#xfstests xfs test, based on kiss-vm

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
vmname=fstest

### __prepare__ test env build
stdlog=$(trun vm create $distro --downloadonly |& tee /dev/tty)
imgf=$(sed -n '${s/^.* //;p}' <<<"$stdlog")

trun vm create -n $vmname $distro --msize 4096 -p vim --nointeract -I=$imgf -f --xdisk=16,xfs,bus=sata --xdisk=16,xfs,bus=sata "$@"

vm cpto -v  $vmname /usr/bin/xfstests-install.sh /usr/bin/make-nfs-server.sh /usr/bin/.
vm exec -vx $vmname -- "xfstests-install.sh" || exit 1

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vm exec -v $vmname -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vm exec -v $vmname -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"
vm exec -v $vmname -- "cat >/var/lib/xfstests/local.config <<EOF
export TEST_DEV=/dev/sda1
export TEST_DIR=/mnt/xfstests_test
export SCRATCH_DEV=/dev/sdb1
export SCRATCH_MNT=/mnt/xfstests_scratch
EOF"
vm exec -v $vmname -- "cd /var/lib/xfstests/; ./check -n -g auto"
#vm exec -v $vmname -- "cd /var/lib/xfstests/; DIFF_LENGTH=-0 ./check"
vm exec -v $vmname -- "cd /var/lib/xfstests/; ./check"
