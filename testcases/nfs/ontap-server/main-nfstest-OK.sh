#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

[[ -n "$1" && "$1" != -* ]] && { distro=${1}; shift; [[ -n "$1" && "$1" != -* ]] && { clientvm=${1}; shift 1; }; }
distro=${distro:-9}
clientvm=${clientvm:-nfstest-ontap-krb5-clnt}

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $clientvm; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

### __prepare__ test env build
#create Windows AD server, ONTAP simulator and client VMs
trun -x0 make-ontap-with-windows-ad.sh $distro $clientvm "$@" || exit $?
timeout 300 vm port-available -w $clientvm || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

distrodir=$(gen_distro_dir_name $clientvm ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/ontap-env-prepare.log
mkdir -p $resdir
{
#install nfstest on $clientvm
vm cpto $clientvm /usr/bin/install-nfstest.sh /usr/bin/get-network-info.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
vmrunx 0 $clientvm -- install-nfstest.sh
vmrunx 0 $clientvm -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'

ONTAP_ENV_FILE=/tmp/ontap2info.env
source "$ONTAP_ENV_FILE"

oservaddr=$NETAPP_NAS_IP
lservaddr=192.168.20.21
vmrunx 0 $clientvm -- get-network-info.sh
#read NIC clntaddr < <(vm exec $clientvm -- get-network-info.sh | grep ${NETAPP_NAS_IP%?.*})
read NIC clntaddr < <(vm exec $clientvm -- get-network-info.sh | grep ${lservaddr%.*})
[[ -z "$NIC" ]] && { echo "{TENV:ERROR} get NIC fail" >&2; exit 2; }
} &> >(tee $resdir/std.log)


_test=pnfs-ontap
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  #nfstest_pnfs
  expdir=/share2
  nfsmp=/mnt/nfsmp

  vmrunx 0 $clientvm -- showmount -e $lservaddr
  vmrunx 0 $clientvm -- mkdir -p $nfsmp
  vmrunx - $clientvm -- ip link set "$NIC" promisc on

  vmrunx - $clientvm -- uname -r;
  trun -tmux=${_test}-console-$clientvm -logf=$resdir/console-$clientvm.log vm console $clientvm
  vmrunx 0 $clientvm -- mount -overs=4.1,noresvport ${NETAPP_NAS_IP_LOC}:${NETAPP_NFS_SHARE2} $nfsmp
  vmrunx 0 $clientvm -- tmux new -s ddSession -d "dd if=/dev/zero of=$nfsmp/testfile bs=1b count=10000000"
  vmrunx 0 $clientvm -- 'sleep 3; ss -nat | grep :2049'
  vmrunx 0 $clientvm -- "ss -nat | grep ${NETAPP_NAS_IP_LOC}:2049"
  vmrunx 0 $clientvm -- "ss -nat | grep -v ${NETAPP_NAS_IP_LOC}: | grep :2049"   #the connect to DS may be not 192.168.20.22, but through the macvtap IF
  vmrunx 0 $clientvm -- tmux kill-session -t ddSession
  vmrunx - $clientvm -- 'sleep 16; ss -nat | grep :2049'   #tcp connect may not be release immediately
  vmrunx 0 $clientvm -- rm -f $nfsmp/testfile
  vmrunx 0 $clientvm -- umount $nfsmp

  vmrunx - $clientvm -- nfstest_pnfs --server $lservaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --trcdelay=3 --client-ipaddr=$clntaddr --nfsversion=4.2 $TESTS;
  exFail=0
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)
trun -x1-255 grep RI[P]: $resdir/console*.log

_test=interop-ontap-krb5
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx -  $clientvm -- uname -r;
  trun -tmux=${_test}-console-$clientvm -logf=$resdir/console-$clientvm.log vm console $clientvm
  vmrunx -  $clientvm -- nfstest_interop --server ${NETAPP_NAS_HOSTNAME} --export=${NETAPP_NFS_SHARE} --sec=krb5 --datadir datadir --nfsversion=4.2 $TESTS;
  exFail=0
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)
trun -x1-255 grep RI[P]: $resdir/console*.log

_test=posix-ontap-krb5
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx - $clientvm -- uname -r;
  trun -tmux=${_test}-console-$clientvm -logf=$resdir/console-$clientvm.log vm console $clientvm
  vmrunx - $clientvm -- nfstest_posix --server ${NETAPP_NAS_HOSTNAME} --export=${NETAPP_NFS_SHARE} --sec=krb5p --nfsversion=4.2 --interface=$NIC --trcdelay=3 --client-ipaddr=$clntaddr $TESTS;
  #stopvms
  exFail=0
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)
trun -x1-255 grep RI[P]: $resdir/console*.log

tcnt
