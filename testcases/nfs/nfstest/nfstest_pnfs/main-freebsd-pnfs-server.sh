#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsclnt=fbpnfs-linux-client

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

#create freebsd pnfs server. flex-file layout
nfsmp=/mnt/nfsmp
expdir0=/export0
expdir1=/export1
vm_ds1=freebsd-pnfs-ds1
vm_ds2=freebsd-pnfs-ds2
vm_mds=freebsd-pnfs-mds
trun -x0 make-freebsd-pnfsserver.sh $distro $nfsclnt "$@" || exit $?
timeout 300 vm port-available -w $nfsclnt || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

mdsaddr=$(vm ifaddr $vm_mds|head -1)
vmrunx - $nfsclnt -- showmount -e $mdsaddr
vmrunx - $nfsclnt -- mkdir -p $nfsmp

#nfstest_pnfs
NIC=$(vmrunx - $nfsclnt -- nmcli -g DEVICE connection show|sed -n 2p)
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/get-ip.sh /usr/bin/.
vmrunx - $nfsclnt -- install-nfstest.sh
vmrunx - $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>~/.bashrc'
vmrunx - $nfsclnt -- ip link set "$NIC" promisc on
clntaddr=$(vm ifaddr $nfsclnt|head -1)

_test=pnfs-freebsd
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  trun -tmux=$_test-client.console -logpath=$resdir vm console $nfsclnt
  vmrunx - $nfsclnt -- nfstest_pnfs --server $mdsaddr --export=$expdir0 --mtpoint=$nfsmp --interface=$NIC --trcdelay=3 --client-ipaddr=$clntaddr --nfsversion=4.2 $TESTS;
  trun -x1-255 grep RI[P]: $resdir/*console.log
} |& tee $resdir/std.log

[[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsclnt
