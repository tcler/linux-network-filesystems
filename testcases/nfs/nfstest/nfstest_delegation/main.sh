#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
passwd=redhat
vmserv=nfstest-deleg-serv
vmclnt=nfstest-deleg-clnt
vmclntx=nfstest-deleg-clntx

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $vmserv $vmclnt $vmclntx; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

trun -tmux vm create $distro -n $vmserv -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark -I=$imgf "$@"
trun -tmux vm create $distro -n $vmclntx -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark,python3 -I=$imgf "$@"
trun       vm create $distro -n $vmclnt -m 4G -f -nointeract -p vim,nfs-utils,tcpdump,wireshark,expect,iproute-tc,kernel-modules-extra -I=$imgf "$@"
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $vmserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

vm cpto -v $vmserv /usr/bin/make-nfs-server.sh /usr/bin/.
vmrunx - $vmserv -- make-nfs-server.sh
vmrunx - $vmserv -- mkdir -p /nfsshare/rw/testdir
vmrunx - $vmserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $vmserv|head -1)

vmrunx - $vmclntx -- showmount -e $servaddr
vmrunx - $vmclnt -- showmount -e $servaddr

#nfstest_delegation
expdir=/nfsshare/rw
vm cpto -v $vmclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh /usr/bin/get-if-by-ip.sh /usr/bin/.
read clntxaddr < <(vm ifaddr $vmclntx | grep ${servaddr%.*})
read clntaddr < <(vm ifaddr $vmclnt | grep ${servaddr%.*})
NIC=$(vmrunx - $vmclnt -- get-if-by-ip.sh $clntaddr)
vmrunx - $vmclnt -- install-nfstest.sh
vmrunx - $vmclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vmrunx - $vmclnt -- ssh-copy-id.sh $clntxaddr root redhat
vmrunx - $vmclnt -- ip link set "$NIC" promisc on

_test=delegation
distrodir=$(gen_distro_dir_name $vmclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/$_test
mkdir -p $resdir
{
  vmrunx - $vmclnt -- uname -r;
  trun -tmux=$_test-server.console -logpath=$resdir vm console $vmserv
  trun -tmux=$_test-client.console -logpath=$resdir vm console $vmclnt
  trun -tmux=$_test-clientx.console -logpath=$resdir vm console $vmclntx
  vmrunx - $vmclnt -- nfstest_delegation --server=$servaddr --export=$expdir --nfsversion=4.2 --client $clntxaddr --client-nfsvers=4.0,4.1,4.2 $TESTS;
  trun -x1-255 grep RI[P]: $resdir/*console.log
  stopvms
} &> >(tee $resdir/std.log)

tcnt
