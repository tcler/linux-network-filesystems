#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=pynfs-server
nfsclnt=pynfs-client

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

#download image file
! grep -Eq -- '(^| )(-I=[^ ]+|-[lL])' <<<"$*" && {
	stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
	imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
}

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p vim,nfs-utils,tmux,wireshark -I=$imgf "$@"
trun       vm create $distro -n $nfsclnt -m 4G -f -nointeract -p vim,nfs-utils,tmux,wireshark -I=$imgf "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh .
vmrunx - $nfsserv -- bash make-nfs-server.sh
vmrunx - $nfsserv -- mkdir -p /nfsshare/rw/testdir
vmrunx - $nfsserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv|head -1)

vmrunx - $nfsclnt -- showmount -e $servaddr

#nfstest_alloc
expdir=/nfsshare/rw
nfsmp=/mnt/nfsmp
vm cpto -v $nfsclnt /usr/bin/install-pynfs.sh /usr/bin/get-if-by-ip.sh /usr/bin/
read nfsclntaddr < <(vm ifaddr $nfsclnt | grep ${servaddr%.*})
NIC=$(vm exec $nfsclnt -- get-if-by-ip.sh $nfsclntaddr)
vmrunx - $nfsclnt -- install-pynfs.sh
vmrunx - $nfsclnt -- ip link set "$NIC" promisc on

_test=pynfs-testserver
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  vmrunx - $nfsclnt -- testserver.py --maketree $servaddr:$expdir all;
  stopvms
} &> >(tee $resdir/std.log)

tcnt
