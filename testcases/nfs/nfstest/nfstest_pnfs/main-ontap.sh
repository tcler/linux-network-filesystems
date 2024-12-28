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
PUBIF=${PUBIF:-no} \
trun -x0 make-ontap-simulator.sh $distro $nfsclnt "$@" || exit $?
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
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
read clntaddr < <(vm ifaddr $nfsclnt | grep ${lservaddr%.*})
NIC=$(vm exec $nfsclnt -- get-if-by-ip.sh $clntaddr)
vmrunx - $nfsclnt -- install-nfstest.sh
vmrunx - $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>~/.bashrc'
vmrunx - $nfsclnt -- ip link set "$NIC" promisc on

_test=pnfs-ontap
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  trun -tmux=$_test-client.console -logpath=$resdir vm console $nfsclnt
  vmrunx 0 $nfsclnt -- mount -overs=4.1,noresvport ${NETAPP_NAS_IP_LOC}:${NETAPP_NFS_SHARE2} $nfsmp
  vmrunx 0 $nfsclnt -- tmux new -s ddSession -d "dd if=/dev/zero of=$nfsmp/testfile bs=1b count=10000000"
  vmrunx 0 $nfsclnt -- 'sleep 3; ss -nat | grep :2049'
  vmrunx 0 $nfsclnt -- "ss -nat | grep ${NETAPP_NAS_IP_LOC}:2049"
  vmrunx 0 $nfsclnt -- "ss -nat | grep -v ${NETAPP_NAS_IP_LOC} | grep :2049"   #the connect to DS may be not 192.168.20.22, but through the macvtap IF
  vmrunx 0 $nfsclnt -- tmux kill-session -t ddSession
  vmrunx - $nfsclnt -- 'sleep 16; ss -nat | grep :2049'   #tcp connect may not be release immediately
  vmrunx 0 $nfsclnt -- rm -f $nfsmp/testfile
  vmrunx 0 $nfsclnt -- umount $nfsmp

  vmrunx - $nfsclnt -- nfstest_pnfs --server $lservaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --trcdelay=3 --client-ipaddr=$clntaddr --nfsversion=4.2 $TESTS;
  trun -x1-255 grep RI[P]: $resdir/*console.log
  [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsclnt
} &> >(tee $resdir/std.log)

tcnt
