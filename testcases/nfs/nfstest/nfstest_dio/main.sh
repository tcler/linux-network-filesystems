#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=nfstest-dio-serv
nfsclnt=nfstest-dio-clnt

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p nfs-utils,wireshark,tmux -I=$imgf "$@"
trun       vm create $distro -n $nfsclnt -m 4G -f -nointeract -p nfs-utils,wireshark,tmux -I=$imgf "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin/.
vm exec -v $nfsserv -- make-nfs-server.sh
vm exec -v $nfsserv -- mkdir -p /nfsshare/rw/testdir
vm exec -v $nfsserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv)

vm exec -v $nfsclnt -- showmount -e $servaddr

#nfstest_dio
nfsmp=/mnt/nfsmp
expdir=/nfsshare/rw
NIC=$(vm exec -v $nfsclnt -- nmcli -g DEVICE connection show|head -1)
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/.
vm exec -v $nfsclnt -- install-nfstest.sh
vm exec -v $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vm exec -v $nfsclnt -- ip link set "$NIC" promisc on
vm exec -v $nfsclnt -- getconf PAGESIZE

pgsize=$(vm exec $nfsclnt -- getconf PAGESIZE)
distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
distrodir=$distro; [[ -n "${SUFFIX}" ]] && distrodir+=-${SUFFIX}
resdir=~/testres/$distrodir/nfstest
mkdir -p $resdir
{
  vm exec -v $nfsclnt -- uname -r;
  vm exec -v $nfsclnt -- nfstest_dio --server $servaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --rsize=$pgsize --wsize=$pgsize --nfsversion=4.2;
} |& tee $resdir/dio.log

vm stop $nfsserv $nfsclnt
