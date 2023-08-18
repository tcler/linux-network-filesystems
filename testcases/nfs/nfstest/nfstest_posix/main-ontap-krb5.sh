#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

distro=${1:-9}
clientvm=${2:-rhel-client}

### __prepare__ test env build
#create Windows AD server, ONTAP simulator and client VMs
make-ontap-with-windows-ad.sh $distro $clientvm

#install nfstest on $clientvm
vm cpto $clientvm /usr/bin/install-nfstest.sh /usr/bin/.
vm exec -vx $clientvm -- install-nfstest.sh
vm exec -vx $clientvm -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'

ONTAP_ENV_FILE=/tmp/ontap2info.env
source "$ONTAP_ENV_FILE"
vm exec -v  $clientvm -- nfstest_posix --server ${NETAPP_NAS_HOSTNAME} --export=${NETAPP_NFS_SHARE} --sec=krb5p --nfsversion=4.2
