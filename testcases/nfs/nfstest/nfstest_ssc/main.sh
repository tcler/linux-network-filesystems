#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=nfstest-ssc-serv
nfsserv2=nfstest-ssc-serv2
nfsclnt=nfstest-ssc-clnt
NFSSHARE=/var/nfsshare

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsserv $nfsserv2 $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")
[[ -n "${imgf}" ]] && insOpt=-I=$imgf

#create nfs server,client vm
trun -tmux vm create $distro -n $nfsserv  -f -nointeract -p vim,tcpdump,nfs-utils "$@" $insOpt
trun -tmux vm create $distro -n $nfsserv2 -f -nointeract -p vim,tcpdump,nfs-utils "$@" $insOpt
trun       vm create $distro -n $nfsclnt  -f -nointeract -p vim,tcpdump,nfs-utils,tcpdump,iproute-tc,kernel-modules-extra "$@" $insOpt
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $nfsserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

vm cpto -v $nfsserv  /usr/bin/make-nfs-server.sh /usr/bin/.
vm cpto -v $nfsserv2 /usr/bin/make-nfs-server.sh /usr/bin/.
vmrunx 0 $nfsserv  -- make-nfs-server.sh --prefix=$NFSSHARE
vmrunx 0 $nfsserv2 -- make-nfs-server.sh --prefix=$NFSSHARE
vmrunx 0 $nfsserv  -- "echo Y >/sys/module/nfsd/parameters/inter_copy_offload_enable"
vmrunx 0 $nfsserv2 -- "echo Y >/sys/module/nfsd/parameters/inter_copy_offload_enable"

read serv1addr < <(vm ifaddr $nfsserv)
read serv2addr < <(vm ifaddr $nfsserv2 | grep ${serv1addr%.*})
vmrunx - $nfsclnt -- showmount -e $serv1addr
vmrunx - $nfsclnt -- showmount -e $serv2addr

#nfstest_ssc
nfsmp=/mnt/nfsmp
expdir=$NFSSHARE/rw
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
read clntaddr < <(vm ifaddr $nfsclnt | grep ${serv1addr%.*})
NIC=$(vm exec $nfsclnt -- get-if-by-ip.sh $clntaddr)
vmrunx - $nfsclnt -- install-nfstest.sh
vmrunx - $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'

_test=ssc
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  trun -tmux=${_test}-console-$nfsserv  -logf=$resdir/console-$nfsserv  vm console $nfsserv
  trun -tmux=${_test}-console-$nfsserv2 -logf=$resdir/console-$nfsserv2 vm console $nfsserv2
  trun -tmux=${_test}-console-$nfsclnt  -logf=$resdir/console-$nfsclnt  vm console $nfsclnt
  vmrunx - $nfsclnt -- nfstest_ssc -s $serv1addr -e $expdir --dst-server $serv2addr --dst-export $NFSSHARE/async ${TESTS:-inter};
  stopvms

  exFail=0
  trun -x0 nfstest-result-check.sh $exFail $resdir/std.log
} &> >(tee $resdir/std.log)

trun -x1-255 grep RI[P]: $resdir/console*.log
tcnt
