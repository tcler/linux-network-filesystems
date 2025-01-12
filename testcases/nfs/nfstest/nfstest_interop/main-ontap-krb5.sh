#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

[[ -n "$1" && "$1" != -* ]] && { distro=${1}; shift; [[ -n "$1" && "$1" != -* ]] && { clientvm=${1}; shift 1; }; }
distro=${distro:-9}
clientvm=${clientvm:-nfstest-interop-OK-clnt}

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $clientvm; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

### __prepare__ test env build
#create Windows AD server, ONTAP simulator and client VMs
trun -x0 make-ontap-with-windows-ad.sh $distro $clientvm "$@" || exit $?
timeout 300 vm port-available -w $clientvm || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

#install nfstest on $clientvm
vm cpto $clientvm /usr/bin/install-nfstest.sh /usr/bin/.
vmrunx 0 $clientvm -- install-nfstest.sh
vmrunx 0 $clientvm -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'

ONTAP_ENV_FILE=/tmp/ontap2info.env
source "$ONTAP_ENV_FILE"

_test=interop-ontap-krb5
distrodir=$(gen_distro_dir_name $clientvm ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx -  $clientvm -- uname -r;
  trun -tmux=${_test}-console-$clientvm -logf=$resdir/console-$clientvm.log vm console $clientvm
  vmrunx -  $clientvm -- nfstest_interop --server ${NETAPP_NAS_HOSTNAME} --export=${NETAPP_NFS_SHARE} --sec=krb5 --datadir datadir --nfsversion=4.2 $TESTS;
  trun -x1-255 grep RI[P]: $resdir/*console.log
  stopvms
} &> >(tee $resdir/std.log)

tcnt
