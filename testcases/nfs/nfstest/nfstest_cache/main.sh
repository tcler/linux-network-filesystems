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
NFSSHARE=/var/nfsshare

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv $nfsclnt $nfsclntx; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
[[ -n "${imgf}" ]] && insOpt=-I=$imgf

trun -tmux vm create $distro -n $nfsserv -m 4G -f -nointeract -p vim,nfs-utils,tmux,tcpdump,wireshark "$@" $insOpt
trun -tmux vm create $distro -n $nfsclntx -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark,python3 "$@" $insOpt
trun       vm create $distro -n $nfsclnt -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark,expect,iproute-tc,kernel-modules-extra "$@" $insOpt
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $nfsserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin/.
vmrunx - $nfsserv -- make-nfs-server.sh --prefix=$NFSSHARE
vmrunx - $nfsserv -- mkdir -p $NFSSHARE/rw/testdir
vmrunx - $nfsserv -- touch $NFSSHARE/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $nfsserv|head -1)

vmrunx - $nfsclnt -- showmount -e $servaddr

#nfstest_cache
nfsmp=/mnt/nfsmp
expdir=$NFSSHARE/rw
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
read clntaddr < <(vm ifaddr $nfsclnt | grep ${servaddr%.*})
read clntxaddr < <(vm ifaddr $nfsclntx | grep ${servaddr%.*})
NIC=$(vm exec $nfsclnt -- get-if-by-ip.sh $clntaddr)
vmrunx - $nfsclnt -- install-nfstest.sh
vmrunx - $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vmrunx - foo@$nfsclnt -- ssh-copy-id.sh $servaddr foo redhat
vmrunx - foo@$nfsclnt -- ssh-copy-id.sh $servaddr root redhat
vmrunx - foo@$nfsclnt -- ssh-copy-id.sh $clntxaddr foo redhat
vmrunx - foo@$nfsclnt -- ssh-copy-id.sh $clntxaddr root redhat

vmrunx - $nfsclnt -- ip link set "$NIC" promisc on
vmrunx - $nfsclnt -- usermod -a -G nobody foo

_test=cache
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx - $nfsserv -- 'echo "foo ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers'
  vmrunx - $nfsclnt -- 'echo "foo ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers'
  vmrunx - $nfsclntx -- 'echo "foo ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers'

  vmrunx - foo@$nfsclnt -- uname -r;
  trun -tmux=${_test}-console-$nfsserv  -logf=$resdir/console-$nfsserv.log  vm console $nfsserv
  trun -tmux=${_test}-console-$nfsclnt  -logf=$resdir/console-$nfsclnt.log  vm console $nfsclnt
  trun -tmux=${_test}-console-$nfsclntx -logf=$resdir/console-$nfsclntx.log vm console $nfsclntx
  vmrunx - foo@$nfsclnt -- nfstest_cache --server $servaddr --client $clntxaddr --export=$expdir --mtpoint=$nfsmp --interface=$NIC --trcdelay=3 --client-ipaddr=$clntaddr --nfsversion=4.2 $TESTS;
  stopvms

  exFail=15
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)

trun -x1-255 grep RI[P]: $resdir/console*.log
tcnt
