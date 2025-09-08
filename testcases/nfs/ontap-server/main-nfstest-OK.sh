#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

[[ -n "$1" && "$1" != -* ]] && { distro=${1}; shift; [[ -n "$1" && "$1" != -* ]] && { nfsclnt=${1}; shift 1; }; }
distro=${distro:-9}
nfsclnt=${nfsclnt:-nfstest-ontap-clnt}
nfsclnt2="${nfsclnt}2"

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

### __prepare__ test env build
#create Windows AD server, ONTAP simulator and client VMs
if ! ping -c 4 -I $(get-default-if.sh) ipa.corp.redhat.com; then
	export PUBIF=no
fi
trun -x0 make-ontap-with-windows-ad.sh $distro ${nfsclnt},${nfsclnt2} "$@" || exit $?
timeout 300 vm port-available -w $nfsclnt || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/ontap-env-prepare.log
mkdir -p $resdir
{
#install nfstest on $nfsclnt
vm cpto $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/get-network-info.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
vm cpto $nfsclnt2 /usr/bin/install-nfstest.sh /usr/bin/get-network-info.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
vmrunx 0 $nfsclnt -- install-nfstest.sh
vmrunx 0 $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vmrunx 0 $nfsclnt2 -- install-nfstest.sh
vmrunx 0 $nfsclnt2 -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'

ONTAP_ENV_FILE=/tmp/ontap2info.env
source "$ONTAP_ENV_FILE"

oservaddr=$NETAPP_NAS_IP
lservaddr=192.168.20.21
vmrunx 0 $nfsclnt -- get-network-info.sh
#read NIC clntaddr < <(vm exec $nfsclnt -- get-network-info.sh | grep ${NETAPP_NAS_IP%?.*})
read NIC clntaddr < <(vm exec $nfsclnt -- get-network-info.sh | grep ${lservaddr%.*})
read NIC2 clnt2addr < <(vm exec $nfsclnt2 -- get-network-info.sh | grep ${lservaddr%.*})
[[ -z "$NIC" ]] && { echo "{TENV:ERROR} get NIC fail" >&2; exit 2; }
} &> >(tee $resdir/std.log)


_test=pnfs-ontap
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  #nfstest_pnfs
  expdir=/share2
  nfsmp=/mnt/nfsmp

  vmrunx 0 $nfsclnt -- showmount -e $lservaddr
  vmrunx 0 $nfsclnt -- mkdir -p $nfsmp
  vmrunx - $nfsclnt -- ip link set "$NIC" promisc on

  vmrunx - $nfsclnt -- uname -r;
  trun -tmux=${_test}-console-$nfsclnt -logf=$resdir/console-$nfsclnt.log vm console $nfsclnt
  vmrunx 0 $nfsclnt -- mount -overs=4.1,noresvport ${NETAPP_NAS_IP_LOC}:${NETAPP_NFS_SHARE2} $nfsmp
  vmrunx 0 $nfsclnt -- tmux new -s ddSession -d "dd if=/dev/zero of=$nfsmp/testfile bs=1b count=10000000"
  vmrunx 0 $nfsclnt -- 'sleep 3; ss -nat | grep :2049'
  vmrunx 0 $nfsclnt -- "ss -nat | grep ${NETAPP_NAS_IP_LOC}:2049"
  vmrunx 0 $nfsclnt -- "ss -nat | grep -v ${NETAPP_NAS_IP_LOC}: | grep :2049"   #the connect to DS may be not 192.168.20.22, but through the macvtap IF
  vmrunx 0 $nfsclnt -- tmux kill-session -t ddSession
  vmrunx - $nfsclnt -- 'sleep 16; ss -nat | grep :2049'   #tcp connect may not be release immediately
  vmrunx 0 $nfsclnt -- rm -f $nfsmp/testfile
  vmrunx 0 $nfsclnt -- umount $nfsmp

  vmrunx - $nfsclnt -- nfstest_pnfs --server $lservaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --trcdelay=3 --client-ipaddr=$clntaddr --nfsversion=4.2 $TESTS;
  exFail=0
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)
trun -x1-255 grep RI[P]: $resdir/console*.log

_test=interop-ontap-krb5
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx -  $nfsclnt -- uname -r;
  trun -tmux=${_test}-console-$nfsclnt -logf=$resdir/console-$nfsclnt.log vm console $nfsclnt
  vmrunx -  $nfsclnt -- nfstest_interop --server ${NETAPP_NAS_HOSTNAME} --export=${NETAPP_NFS_SHARE} --sec=krb5 --datadir datadir --nfsversion=4.2 $TESTS;
  exFail=0
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)
trun -x1-255 grep RI[P]: $resdir/console*.log

_test=posix-ontap-krb5
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  trun -tmux=${_test}-console-$nfsclnt -logf=$resdir/console-$nfsclnt.log vm console $nfsclnt
  vmrunx - $nfsclnt -- nfstest_posix --server ${NETAPP_NAS_HOSTNAME} --export=${NETAPP_NFS_SHARE} --sec=krb5p --nfsversion=4.2 --interface=$NIC --trcdelay=3 --client-ipaddr=$clntaddr $TESTS;
  #stopvms
  exFail=0
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)
trun -x1-255 grep RI[P]: $resdir/console*.log

_test=delegation-ontap
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  trun -tmux=${_test}-console-$nfsclnt -logf=$resdir/console-$nfsclnt.log vm console $nfsclnt
  trun -tmux=${_test}-console-$nfsclnt2 -logf=$resdir/console-$nfsclnt2.log vm console $nfsclnt2
  vm cpto $nfsclnt /usr/bin/ssh-copy-id.sh /usr/bin/.
  vmrunx - $nfsclnt -- ssh-copy-id.sh $clnt2addr root redhat

  vmrunx - $nfsclnt -- ip link set "$NIC" promisc on
  vmrunx - $nfsclnt2 -- ip link set "$NIC2" promisc on

  vmrunx - $nfsclnt -- nfstest_delegation --server=${NETAPP_NAS_HOSTNAME} --export=$expdir --nfsversion=4.1 --client ${clnt2addr} --client-nfsvers=4.1,4.2 $TESTS;
  #stopvms
  exFail=62
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)
trun -x1-255 grep RI[P]: $resdir/console*.log

tcnt
