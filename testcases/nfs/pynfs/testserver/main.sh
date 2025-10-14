#!/usr/bin/env bash
#
export LANG=C
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
PROG=$0; ARGS=("$@")
trap_try_again() { exec $PROG "${ARGS[@]}"; }

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=pynfs-server
nfsclnt=pynfs-client
NFSSHARE=/nfsshare
NFSROOT=${NFSROOT}

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap cleanup EXIT
trap try_again SIGUSR2

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
[[ -n "${imgf}" ]] && insOpt=-I=$imgf

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p vim,nfs-utils,tmux,wireshark "$@" $insOpt
trun       vm create $distro -n $nfsclnt -m 4G -f -nointeract -p vim,nfs-utils,tmux,wireshark "$@" $insOpt
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin/
vmrunx - $nfsserv -- Squash=no_root_squash make-nfs-server.sh --prefix=$NFSSHARE --nfsroot=$NFSROOT
vmrunx - $nfsserv -- mkdir -p $NFSROOT/$NFSSHARE/rw/testdir
vmrunx - $nfsserv -- touch $NFSROOT/$NFSSHARE/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv|head -1)

vmrunx - $nfsclnt -- showmount -e $servaddr

#nfstest_alloc
expdir=$NFSSHARE/rw
nfsmp=/mnt/nfsmp
vm cpto -v $nfsclnt /usr/bin/install-pynfs.sh /usr/bin/get-if-by-ip.sh /usr/bin/
read nfsclntaddr < <(vm ifaddr $nfsclnt | grep ${servaddr%.*})
NIC=$(vm exec $nfsclnt -- get-if-by-ip.sh $nfsclntaddr)
vmrunx - $nfsclnt -- install-pynfs.sh
vmrunx - $nfsclnt -- ip link set "$NIC" promisc on

_test=pynfs-testserver
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX}) || kill -s SIGUSR2 $$
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  vmrunx - $nfsclnt -- testserver.py --maketree $servaddr:$expdir all;
  stopvms
} &> >(tee $resdir/std.log)

tcnt
