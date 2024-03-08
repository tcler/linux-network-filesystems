#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsclnt=nfs-client
nfsmp=/mnt/nfsmp

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -n '${s/^.* //;p}' <<<"$stdlog")

#create vm as nfs client
trun -tmux vm create $distro -n $nfsclnt -m 4G -f -nointeract --net ontap2-data -p nfs-utils,expect,iproute-tc,kernel-modules-extra -I=$imgf "$@"

#create netapp ontap-simulator
trun -x0 make-ontap-simulator.sh || exit $?

echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*-d.vm.creat[e]; do sleep 16; done

servaddr=192.168.20.21
vm exec -v $nfsclnt -- showmount -e $servaddr
vm exec -v $nfsclnt -- mkdir -p $nfsmp

#nfstest_pnfs
expdir=/share2
NIC=eth0
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/.
vm exec -v $nfsclnt -- install-nfstest.sh
vm exec -v $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>~/.bashrc'
vm exec -v $nfsclnt -- ip link set "$NIC" promisc on

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
resdir=~/testres/$distro/nfstest
mkdir -p $resdir
{
  vm exec -v $nfsclnt -- uname -r;
  vm exec -v $nfsclnt -- nfstest_pnfs --server $servaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --nfsversion=4.2;
} |& tee $resdir/pnfs.log
