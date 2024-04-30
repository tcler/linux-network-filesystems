#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=nfstest-cache-serv
nfsclnt=nfstest-cache-clnt
nfsclntx=nfstest-cache-clntx

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p vim,nfs-utils,tmux,tcpdump,wireshark -I=$imgf "$@"
trun -tmux vm create $distro -n $nfsclntx -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark,python3 -I=$imgf "$@"
trun       vm create $distro -n $nfsclnt -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark,expect,iproute-tc,kernel-modules-extra -I=$imgf "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh .
vm exec -v $nfsserv -- bash make-nfs-server.sh
vm exec -v $nfsserv -- mkdir -p /nfsshare/rw/testdir
vm exec -v $nfsserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv)

vm exec -v $nfsclnt -- showmount -e $servaddr

#nfstest_cache
nfsmp=/mnt/nfsmp
expdir=/nfsshare/rw
NIC=$(vm exec -v $nfsclnt -- nmcli -g DEVICE connection show|head -1)
clntxaddr=$(vm ifaddr $nfsclntx)
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh /usr/bin/.
vm exec -v $nfsclnt -- install-nfstest.sh
vm exec -v $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vm exec -v foo@$nfsclnt -- ssh-copy-id.sh $servaddr foo redhat
vm exec -v foo@$nfsclnt -- ssh-copy-id.sh $servaddr root redhat
vm exec -v foo@$nfsclnt -- ssh-copy-id.sh $clntxaddr foo redhat
vm exec -v foo@$nfsclnt -- ssh-copy-id.sh $clntxaddr root redhat

vm exec -v $nfsclnt -- ip link set "$NIC" promisc on
vm exec -v $nfsclnt -- usermod -a -G nobody foo

distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest
mkdir -p $resdir
{
  vm exec -v $nfsserv -- 'echo "foo ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers'
  vm exec -v $nfsclnt -- 'echo "foo ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers'
  vm exec -v $nfsclntx -- 'echo "foo ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers'

  vm exec -v foo@$nfsclnt -- uname -r;
  vm exec -v foo@$nfsclnt -- nfstest_cache --server $servaddr --client $clntxaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --nfsversion=4.2;
} |& tee $resdir/cache.log

vm stop $nfsserv $nfsclnt $nfsclntx
