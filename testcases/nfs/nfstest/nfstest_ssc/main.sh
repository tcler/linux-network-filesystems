#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }
export LANG=C LANGUAGE=C   #nfstest only works on english lang env

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=nfstest-ssc-serv
nfsserv2=nfstest-ssc-serv2
nfsclnt=nfstest-ssc-clnt

#download image file
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

#create nfs server,client vm
trun -tmux vm create $distro -n $nfsserv  -f -nointeract -p vim,tcpdump,nfs-utils -I=$imgf "$@"
trun -tmux vm create $distro -n $nfsserv2 -f -nointeract -p vim,tcpdump,nfs-utils -I=$imgf "$@"
trun       vm create $distro -n $nfsclnt  -f -nointeract -p vim,tcpdump,nfs-utils,tcpdump,iproute-tc,kernel-modules-extra -I=$imgf "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $nfsserv || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

vm cpto -v $nfsserv  /usr/bin/make-nfs-server.sh /usr/bin/.
vm cpto -v $nfsserv2 /usr/bin/make-nfs-server.sh /usr/bin/.
vmrunx 0 $nfsserv  -- make-nfs-server.sh
vmrunx 0 $nfsserv2 -- make-nfs-server.sh
vmrunx 0 $nfsserv  -- "echo Y >/sys/module/nfsd/parameters/inter_copy_offload_enable"
vmrunx 0 $nfsserv2 -- "echo Y >/sys/module/nfsd/parameters/inter_copy_offload_enable"

serv1addr=$(vm ifaddr $nfsserv)
serv2addr=$(vm ifaddr $nfsserv2)
vmrunx - $nfsclnt -- showmount -e $serv1addr
vmrunx - $nfsclnt -- showmount -e $serv2addr

#nfstest_ssc
nfsmp=/mnt/nfsmp
expdir=/nfsshare/rw
NIC=$(vmrunx - $nfsclnt -- nmcli -g DEVICE connection show|sed -n '2p')
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh /usr/bin/get-ip.sh /usr/bin/.
vmrunx - $nfsclnt -- install-nfstest.sh
vmrunx - $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'

distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfstest/ssc
mkdir -p $resdir
{
  vmrunx - $nfsclnt -- uname -r;
  trun -tmux=server.console -logpath=$resdir vm console $nfsserv
  trun -tmux=server2.console -logpath=$resdir vm console $nfsserv2
  trun -tmux=client.console -logpath=$resdir vm console $nfsclnt
  vmrunx - $nfsclnt -- nfstest_ssc -s $serv1addr -e /nfsshare/rw --dst-server $serv2addr --dst-export /nfsshare/async inter;
} |& tee $resdir/std.log

vm stop $nfsserv $nfsserv2 $nfsclnt
