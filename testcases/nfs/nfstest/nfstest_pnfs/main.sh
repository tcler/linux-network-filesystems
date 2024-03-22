#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsclnt=nfstest-pnfs-Ontap-client
nfsmp=/mnt/nfsmp

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -n '${/^image url/{s/^.* //;p}}' <<<"$stdlog")

#create netapp ontap-simulator
trun -x0 make-ontap-simulator.sh $distro $nfsclnt || exit $?
ONTAP_ENV_FILE=/tmp/ontap2info.env
source "$ONTAP_ENV_FILE"

echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

oservaddr=$NETAPP_NAS_IP
lservaddr=192.168.20.21
vm exec -v $nfsclnt -- showmount -e $lservaddr
vm exec -v $nfsclnt -- mkdir -p $nfsmp

#nfstest_pnfs
expdir=/share2
NIC=$(vm exec -v $nfsclnt -- nmcli -g DEVICE connection show|head -1)
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/.
vm exec -v $nfsclnt -- install-nfstest.sh
vm exec -v $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>~/.bashrc'
vm exec -v $nfsclnt -- ip link set "$NIC" promisc on

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
distrodir=$distro; [[ -n "${SUFFIX}" ]] && distrodir+=-${SUFFIX}
resdir=~/testres/$distrodir/nfstest
mkdir -p $resdir
{
  vm exec -v $nfsclnt -- uname -r;
  vm exec -v $nfsclnt -- nfstest_pnfs --server $lservaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --nfsversion=4.2 --trcdelay=3;
} |& tee $resdir/pnfs.log

vm stop $nfsclnt
