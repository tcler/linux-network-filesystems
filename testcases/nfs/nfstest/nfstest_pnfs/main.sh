#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsclnt=nfstest-pnfs-Ontap-client
nfsmp=/mnt/nfsmp

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

#create netapp ontap-simulator
trun -x0 make-ontap-simulator.sh $distro $nfsclnt || exit $?
timeout 300 vm port-available -w $nfsclnt || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }
ONTAP_ENV_FILE=/tmp/ontap2info.env
source "$ONTAP_ENV_FILE"

echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

oservaddr=$NETAPP_NAS_IP
lservaddr=192.168.20.21
vmrunx - $nfsclnt -- showmount -e $lservaddr
vmrunx - $nfsclnt -- mkdir -p $nfsmp

#nfstest_pnfs
expdir=/share2
NIC=$(vmrunx - $nfsclnt -- nmcli -g DEVICE connection show|sed -n '2p;q')
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/.
vmrunx - $nfsclnt -- install-nfstest.sh
vmrunx - $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>~/.bashrc'
vmrunx - $nfsclnt -- ip link set "$NIC" promisc on

distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  vmrunx - $nfsclnt -- nfstest_pnfs --server $lservaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --nfsversion=4.2 --trcdelay=3;
} |& tee $resdir/pnfs.log

vm stop $nfsclnt
