#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=pynfs-server
nfsclnt=pynfs-client

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p vim,nfs-utils,tmux,wireshark -I=$imgf "$@"
trun       vm create $distro -n $nfsclnt -m 4G -f -nointeract -p vim,nfs-utils,tmux,wireshark -I=$imgf "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh .
vmrunx - $nfsserv -- bash make-nfs-server.sh
vmrunx - $nfsserv -- mkdir -p /nfsshare/rw/testdir
vmrunx - $nfsserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv)

vmrunx - $nfsclnt -- showmount -e $servaddr

#nfstest_alloc
expdir=/nfsshare/rw
nfsmp=/mnt/nfsmp
NIC=$(vmrunx - $nfsclnt -- nmcli -g DEVICE connection show|sed -n '2p')
vm cpto -v $nfsclnt /usr/bin/install-pynfs.sh /usr/bin/
vmrunx - $nfsclnt -- install-pynfs.sh
vmrunx - $nfsclnt -- ip link set "$NIC" promisc on

distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/pynfs
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  vmrunx - $nfsclnt -- testserver.py --maketree $servaddr:$expdir all;
} |& tee $resdir/testserver.log

vm stop $nfsserv $nfsclnt
