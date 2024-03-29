#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

[[ -n "$1" && "$1" != -* ]] && { distro=${1}; shift; [[ -n "$1" && "$1" != -* ]] && { clientvm=${1}; shift 1; }; }
distro=${distro:-9}
clientvm=${clientvm:-nfstest-interop-OK-clnt}

### __prepare__ test env build
#create Windows AD server, ONTAP simulator and client VMs
trun -x0 make-ontap-with-windows-ad.sh $distro $clientvm "$@" || exit $?

#install nfstest on $clientvm
vm cpto $clientvm /usr/bin/install-nfstest.sh /usr/bin/.
vm exec -vx $clientvm -- install-nfstest.sh
vm exec -vx $clientvm -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'

ONTAP_ENV_FILE=/tmp/ontap2info.env
source "$ONTAP_ENV_FILE"

distro=$(vm homedir $clientvm|awk -F/ 'NR==1{print $(NF-1)}')
distrodir=$distro; [[ -n "${SUFFIX}" ]] && distrodir+=-${SUFFIX}
resdir=~/testres/$distrodir/nfstest
mkdir -p $resdir
{
  vm exec -v  $clientvm -- uname -r;
  vm exec -v  $clientvm -- nfstest_interop --server ${NETAPP_NAS_HOSTNAME} --export=${NETAPP_NFS_SHARE} --sec=krb5 --datadir datadir --nfsversion=4.2;
} |& tee $resdir/interop-ontap-krb5.log

vm stop $clientvm
