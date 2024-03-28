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
trun -tmux vm create $distro -n $nfsserv  -f -nointeract -p vim,nfs-utils -I=$imgf "$@"
trun -tmux vm create $distro -n $nfsserv2 -f -nointeract -p vim,nfs-utils -I=$imgf "$@"
trun       vm create $distro -n $nfsclnt  -f -nointeract -p vim,nfs-utils,tcpdump,iproute-tc,kernel-modules-extra -I=$imgf "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm cpto -v $nfsserv  /usr/bin/make-nfs-server.sh /usr/bin/.
vm cpto -v $nfsserv2 /usr/bin/make-nfs-server.sh /usr/bin/.
vm exec -vx $nfsserv  -- make-nfs-server.sh
vm exec -vx $nfsserv2 -- make-nfs-server.sh
vm exec -vx $nfsserv  -- "echo Y >/sys/module/nfsd/parameters/inter_copy_offload_enable"
vm exec -vx $nfsserv2 -- "echo Y >/sys/module/nfsd/parameters/inter_copy_offload_enable"

serv1addr=$(vm ifaddr $nfsserv)
serv2addr=$(vm ifaddr $nfsserv2)
vm exec -v $nfsclnt -- showmount -e $serv1addr
vm exec -v $nfsclnt -- showmount -e $serv2addr

#nfstest_ssc
nfsmp=/mnt/nfsmp
expdir=/nfsshare/rw
NIC=$(vm exec -v $nfsclnt -- nmcli -g DEVICE connection show|head -1)
vm cpto -v $nfsclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh /usr/bin/.
vm exec -v $nfsclnt -- install-nfstest.sh
vm exec -v $nfsclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'

distro=$(vm homedir $nfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
distrodir=$distro; [[ -n "${SUFFIX}" ]] && distrodir+=-${SUFFIX}
resdir=~/testres/$distrodir/nfstest
mkdir -p $resdir
{
  vm exec -v $nfsclnt -- uname -r;
  vm exec -v $nfsclnt -- nfstest_ssc -s $serv1addr -e /nfsshare/rw --dst-server $serv2addr --dst-export /nfsshare/async inter;
} |& tee $resdir/ssc.log

vm stop $nfsserv $nfsserv2 $nfsclnt
