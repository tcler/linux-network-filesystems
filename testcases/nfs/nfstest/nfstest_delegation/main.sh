#!/usr/bin/env bash
#
export LANG=C
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
PROG=$0; ARGS=("$@")
trap_try_again() { exec $PROG "${ARGS[@]}"; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
passwd=redhat
vmserv=nfstest-deleg-serv
vmclnt=nfstest-deleg-clnt
vmclntx=nfstest-deleg-clntx
NFSSHARE=/nfsshare
NFSROOT=${NFSROOT}

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $vmserv $vmclnt $vmclntx; }
cleanup() { stopvms 2>/dev/null; }
trap cleanup EXIT
trap try_again SIGUSR2

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
[[ -n "${imgf}" ]] && insOpt=-I=$imgf

trun -tmux vm create $distro -n $vmserv -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark "$@" $insOpt
trun -tmux vm create $distro -n $vmclntx -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark,python3 "$@" $insOpt
trun       vm create $distro -n $vmclnt -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark,expect,iproute-tc,kernel-modules-extra "$@" $insOpt
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $vmserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

vm cpto -v $vmserv /usr/bin/make-nfs-server.sh /usr/bin/.
vmrunx - $vmserv -- make-nfs-server.sh --prefix=$NFSSHARE --nfsroot=$NFSROOT
vmrunx - $vmserv -- mkdir -p $NFSROOT/$NFSSHARE/rw/testdir
vmrunx - $vmserv -- touch $NFSROOT/$NFSSHARE/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $vmserv|head -1)

vmrunx - $vmclntx -- showmount -e $servaddr
vmrunx - $vmclnt -- showmount -e $servaddr

#nfstest_delegation
expdir=$NFSSHARE/rw
vm cpto -v $vmclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
read clntxaddr < <(vm ifaddr $vmclntx | grep ${servaddr%.*})
read clntaddr < <(vm ifaddr $vmclnt | grep ${servaddr%.*})
NIC=$(vmrunx - $vmclnt -- get-if-by-ip.sh $clntaddr)
vmrunx - $vmclnt -- install-nfstest.sh
vmrunx - $vmclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vmrunx - $vmclnt -- ssh-copy-id.sh $clntxaddr root redhat
vmrunx - $vmclnt -- ip link set "$NIC" promisc on

_test=delegation
distrodir=$(gen_distro_dir_name $vmclnt ${SUFFIX}) || kill -s SIGUSR2 $$
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx - $vmclnt -- uname -r;
  trun -tmux=${_test}-console-$vmserv  -logf=$resdir/console-$vmserv.log  vm console $vmserv
  trun -tmux=${_test}-console-$vmclnt  -logf=$resdir/console-$vmclnt.log  vm console $vmclnt
  trun -tmux=${_test}-console-$vmclntx -logf=$resdir/console-$vmclntx.log vm console $vmclntx
  vmrunx - $vmclnt -- nfstest_delegation --server=$servaddr --export=$expdir --nfsversion=4.2 --client $clntxaddr --client-nfsvers=4.0,4.1,4.2 $TESTS;
  stopvms

  exFail=62
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)

trun -x1-255 grep RI[P]: $resdir/console*.log
tcnt
