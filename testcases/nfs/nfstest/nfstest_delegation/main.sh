#!/usr/bin/env bash
#
. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

#create nfs-server vm
[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
passwd=redhat
vmserv=nfs-server
vmclntx=nfs-clientx
vmclnt=nfs-client

#download image file
stdlog=$(trun vm create $distro --downloadonly |& tee /dev/tty)
imgf=$(sed -n '${s/^.* //;p}' <<<"$stdlog")

trun -tmux vm create $distro -n $vmserv -m 4G -f -nointeract -p vim,nfs-utils,wireshark -I=$imgf "$@"
trun -tmux vm create $distro -n $vmclntx -m 4G -f -nointeract -p vim,nfs-utils,wireshark,python3 -I=$imgf "$@"
trun       vm create $distro -n $vmclnt -m 4G -f -nointeract -p vim,nfs-utils,wireshark,expect,iproute-tc,kernel-modules-extra -I=$imgf "$@"
vm cpto -v $vmserv /usr/bin/make-nfs-server.sh .
vm exec -v $vmserv -- bash make-nfs-server.sh
vm exec -v $vmserv -- mkdir -p /nfsshare/rw/testdir
vm exec -v $vmserv -- touch /nfsshare/rw/testdir/file{1..128}
servaddr=$(vm ifaddr $vmserv)

vm exec -v $vmclntx -- showmount -e $servaddr
vm exec -v $vmclnt -- showmount -e $servaddr

#nfstest_delegation
expdir=/nfsshare/rw
NIC=eth0
clntxaddr=$(vm ifaddr $vmclntx)
vm cpto -v $vmclnt /usr/bin/install-nfstest.sh /usr/bin/ssh-copy-id.sh .
vm exec -v $vmclnt -- bash install-nfstest.sh
vm exec -v $vmclnt -- bash -c 'cat /tmp/nfstest.env >>/etc/bashrc'
vm exec -v $vmclnt -- bash ssh-copy-id.sh $clntxaddr root redhat
vm exec -v $vmclnt -- ip link set "$NIC" promisc on

distro=$(vm homedir $vmclnt|awk -F/ 'NR==1{print $(NF-1)}')
resdir=~/testres/$distro/nfstest
mkdir -p $resdir
vm exec -v $vmclnt -- nfstest_delegation --server=$servaddr --export=$expdir --nfsversion=4.2 --client $clntxaddr --client-nfsvers=4.0,4.1,4.2 "$@" |& tee $resdir/delegation.log
