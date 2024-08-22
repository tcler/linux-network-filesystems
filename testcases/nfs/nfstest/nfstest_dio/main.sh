#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=nfstest-dio-serv
nfsclnt=nfstest-dio-clnt

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p nfs-utils,tcpdump,wireshark,tmux -I=$imgf "$@"
trun       vm create $distro -n $nfsclnt -m 4G -f -nointeract -p nfs-utils,tcpdump,wireshark,tmux -I=$imgf "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $nfsserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin/.
vmrunx - $nfsserv -- make-nfs-server.sh
vmrunx - $nfsserv -- mkdir -p /nfsshare/rw/testdir
vmrunx - $nfsserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv)

vmrunx - $nfsclnt -- showmount -e $servaddr

#nfstest_dio
nfsmp=/mnt/nfsmp
expdir=/nfsshare/rw
NIC=$(vmrunx - $nfsclnt -- nmcli -g DEVICE connection show|sed -n '2p')
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/get-ip.sh /usr/bin/.
vmrunx - $nfsclnt -- install-nfstest.sh
vmrunx - $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vmrunx - $nfsclnt -- ip link set "$NIC" promisc on
vmrunx - $nfsclnt -- getconf PAGESIZE
clntaddr=$(vm ifaddr $nfsclnt)

pgsize=$(vm exec $nfsclnt -- getconf PAGESIZE)
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  vmrunx - $nfsclnt -- nfstest_dio --server $servaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --trcdelay=3 --client-ipaddr=$clntaddr --rsize=$pgsize --wsize=$pgsize --nfsversion=4.2;
} |& tee $resdir/dio.log

vm stop $nfsserv $nfsclnt
