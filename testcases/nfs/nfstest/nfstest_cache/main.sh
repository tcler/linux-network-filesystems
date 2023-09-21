#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=nfs-server
nfsclntx=nfs-clientx
nfsclnt=nfs-client

#download image file
stdlog=$(trun vm create $distro --downloadonly |& tee /dev/tty)
imgf=$(sed -n '${s/^.* //;p}' <<<"$stdlog")

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p vim,nfs-utils,tmux,wireshark -I=$imgf "$@"
trun -tmux vm create $distro -n $nfsclntx -m 4G -f -nointeract -p vim,nfs-utils,wireshark,python3 -I=$imgf "$@"
trun       vm create $distro -n $nfsclnt -m 4G -f -nointeract -p vim,nfs-utils,wireshark,expect,iproute-tc,kernel-modules-extra -I=$imgf "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*-d.vm.creat[e]; do sleep 16; done

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh .
vm exec -v $nfsserv -- bash make-nfs-server.sh
vm exec -v $nfsserv -- mkdir -p /nfsshare/rw/testdir
vm exec -v $nfsserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv)

vm exec -v $nfsclnt -- showmount -e $servaddr

#nfstest_cache
nfsmp=/mnt/nfsmp
expdir=/nfsshare/rw
NIC=eth0
clntxaddr=$(vm ifaddr $nfsclntx)
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh /usr/bin/.
vm exec -v $nfsclnt -- install-nfstest.sh
vm exec -v $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vm exec -v foo@$nfsclnt -- ssh-copy-id.sh $servaddr foo redhat
vm exec -v foo@$nfsclnt -- ssh-copy-id.sh $clntxaddr root redhat

vm exec -v $nfsclnt -- ip link set "$NIC" promisc on
vm exec -v $nfsclnt -- usermod -a -G nobody foo

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
resdir=~/testres/$distro/nfstest
mkdir -p $resdir
vm exec -v foo@$nfsclnt -- nfstest_cache --server $servaddr --client $clntxaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --nfsversion=4.2 "$@" |& tee $resdir/cache.log
