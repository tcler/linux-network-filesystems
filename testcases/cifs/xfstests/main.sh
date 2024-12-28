#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#xfstests cifs test, based on kiss-vm

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#env
#TESTS="-g quick ..."
#DIFFLEN=-0
#NOURING=yes

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
smbserv=fstest-smbserv
cifsclnt=fstest-cifsclnt
pkglist=vim,cifs-utils,samba-client,tmux
USERNAME=root
PASSWORD=redhat

#download image file
if [[ "${*}" != *-[lL]* ]]; then
	stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
	imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
	insOpt="-I=$imgf"
fi

trun -tmux vm create $distro -n $smbserv -m 4G -f -nointeract -p ${pkglist}     $insOpt "$@"
trun       vm create $distro -n $cifsclnt -m 4G -f -nointeract -p ${pkglist},git $insOpt "$@" || exit $?
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 10; done
timeout 300 vm port-available -w $smbserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

vm cpto -v $smbserv /usr/bin/make-samba-server.sh .
tmux new -s smbServer -d "vm exec -v $smbserv -- bash make-samba-server.sh"

vm cpto -v  $cifsclnt /usr/bin/xfstests-install.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/.
vmrunx 0 $cifsclnt -- tmux new -d 'yum-install-from-fedora.sh fsverity-utils'
vmrunx 0 $cifsclnt -- "xfstests-install.sh nouring=$NOURING" || exit 1

while tmux ls | grep smbServer; do sleep 8; done
vmrunx 0 $cifsclnt -- smbclient -L //$smbserv -U $USERNAME%$PASSWORD

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vmrunx - $cifsclnt -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vmrunx - $cifsclnt -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"
#see: https://wiki.samba.org/images/9/99/Xfstests.local.config.txt
vmrunx - $cifsclnt -- "cat >/var/lib/xfstests/local.config <<EOF
[default-version]
FSTYP=cifs
TEST_DEV=//$smbserv/share1
TEST_DIR=/mnt/xfstests_test
TEST_FS_MOUNT_OPTS='-ousername=$USERNAME,password=$PASSWORD,noperm,mfsymlinks,actimeo=0'
export MOUNT_OPTIONS='-ousername=$USERNAME,password=$PASSWORD,noperm,mfsymlinks,actimeo=0'
export SCRATCH_DEV=//$smbserv/share2
export SCRATCH_MNT=/mnt/xfstests_scratch
[smb3]
FSTYP=cifs
TEST_DEV=//$smbserv/share1
TEST_DIR=/mnt/xfstests_test
TEST_FS_MOUNT_OPTS='-ousername=$USERNAME,password=$PASSWORD,noperm,vers=3.0,mfsymlinks,actimeo=0'
export MOUNT_OPTIONS='-ousername=$USERNAME,password=$PASSWORD,noperm,mfsymlinks,actimeo=0'
export SCRATCH_DEV=//$smbserv/share2
export SCRATCH_MNT=/mnt/xfstests_scratch
[smb21]
FSTYP=cifs
TEST_DEV=//$smbserv/share1
TEST_DIR=/mnt/xfstests_test
TEST_FS_MOUNT_OPTS='-ousername=$USERNAME,password=$PASSWORD,noperm,vers=2.1,mfsymlinks,actimeo=0'
[smb2]
FSTYP=cifs
TEST_DEV=//$smbserv/share1
TEST_DIR=/mnt/xfstests_test
TEST_FS_MOUNT_OPTS='-ousername=$USERNAME,password=$PASSWORD,noperm,vers=2.0,mfsymlinks,actimeo=0'

[sambacifswithposixextensions]
FSTYP=cifs
TEST_DEV=//$smbserv/share1
TEST_DIR=/mnt/xfstests_test
TEST_FS_MOUNT_OPTS='-ousername=$USERNAME,password=$PASSWORD,vers=1.0,actimeo=0'
[cifs]
FSTYP=cifs
TEST_DEV=//$smbserv/share1
TEST_DIR=/mnt/xfstests_test
TEST_FS_MOUNT_OPTS='-ousername=$USERNAME,password=$PASSWORD,noperm,cifsacl,vers=1.0,mfsymlinks,actimeo=0'
[sambacifs]
FSTYP=cifs
TEST_DEV=//$smbserv/share1
TEST_DIR=/mnt/xfstests_test
TEST_FS_MOUNT_OPTS='-ousername=$USERNAME,password=$PASSWORD,nounix,noperm,cifsacl,vers=1.0,mfsymlinks,actimeo=0'
EOF"

_test=xfstests-cifs
distrodir=$(gen_distro_dir_name $cifsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/cifs/$_test
mkdir -p $resdir
{
  vmrunx - $cifsclnt -- uname -r;
  trun -tmux=${_test}-${distrodir}-server.console -logpath=$resdir vm console $smbserv
  trun -tmux=${_test}-${distrodir}-client.console -logpath=$resdir vm console $cifsclnt
  vmrunx - $cifsclnt -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check -cifs -s default-version ${TESTS};"
  trun -x1-255 grep RI[P]: $resdir/*console.log
  [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $smbserv $cifsclnt
} &> >(tee $resdir/std.log)

tcnt
