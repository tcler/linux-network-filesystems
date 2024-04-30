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
servaddr=$(vm ifaddr $smbserv)

vm cpto -v $smbserv /usr/bin/make-samba-server.sh .
tmux new -s smbServer -d "vm exec -v $smbserv -- bash make-samba-server.sh"

vm cpto -v  $cifsclnt /usr/bin/xfstests-install.sh /usr/bin/yum-install-from-fedora.sh /usr/bin/.
vm exec -vx $cifsclnt -- tmux new -d 'yum-install-from-fedora.sh fsverity-utils'
vm exec -vx $cifsclnt -- "xfstests-install.sh nouring=$NOURING" || exit 1

while tmux ls | grep smbServer; do sleep 8; done
vm exec -vx $cifsclnt -- smbclient -L //$smbserv -U $USERNAME%$PASSWORD

#-------------------------------------------------------------------------------
#prepare TEST_DEV TEST_DIR SCRATCH_DEV SCRATCH_MNT for xfstests
vm exec -v $cifsclnt -- "mkdir -p /mnt/xfstests_test /mnt/xfstests_scratch"
vm exec -v $cifsclnt -- "useradd -m fsgqa; useradd 123456-fsgqa; useradd fsgqa2; groupadd fsgqa"
#see: https://wiki.samba.org/images/9/99/Xfstests.local.config.txt
vm exec -v $cifsclnt -- "cat >/var/lib/xfstests/local.config <<EOF
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

distrodir=$(gen_distro_dir_name $cifsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/xfstest
mkdir -p $resdir
{
  vm exec -v $cifsclnt -- uname -r;
  vm exec -v $cifsclnt -- "cd /var/lib/xfstests/; DIFF_LENGTH=${DIFFLEN} ./check -cifs -s default-version ${TESTS};"
} |& tee $resdir/xfstests-cifs.log

vm stop $smbserv $cifsclnt
