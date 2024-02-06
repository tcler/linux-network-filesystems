#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-9}
clientvm=${2:-rhel-client}
if [[ $# -ge 2 ]]; then
	shift 2
elif [[ $# -ge 1 ]]; then
	shift
fi

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
resdir=~/testres/nfstest/$distro
mkdir -p $resdir
vm exec -v  $clientvm -- nfstest_interop --server ${NETAPP_NAS_HOSTNAME} --export=${NETAPP_NFS_SHARE} --sec=krb5 --datadir datadir --nfsversion=4.2 |& tee $resdir/interop-ontap-krb5.log
