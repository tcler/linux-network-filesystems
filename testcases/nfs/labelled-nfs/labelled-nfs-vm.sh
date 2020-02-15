#!/bin/bash

argv=()
for arg; do
	case "$arg" in
	-net=*) NET=${arg#*=};;
	-h)   echo "Usage: $0 [-h] [distro] [-net=netname]";;
	-*)   echo "{WARN} unkown option '${arg}'";;
	*)    argv+=($arg);;
	esac
done
set -- "${argv[@]}"

distro=${1:-RHEL-8.1.0}


#---------------------------------------------------------------
#install kiss-vm
which vm &>/dev/null || {
	is_available_url() { curl --connect-timeout 8 -m 16 --output /dev/null --silent --head --fail $1 &>/dev/null; }
	is_intranet() { is_available_url http://download.devel.redhat.com; }
	is_intranet && toolsurl=http://download.devel.redhat.com/qa/rhts/lookaside/kiss-vm-ns
	echo -e "[INFO] install kiss-vm ..."
	sudo curl -s -o /usr/bin/vm -L ${toolsurl}/kiss-vm
	sudo chmod +x /usr/bin/vm
}
vm --prepare

#---------------------------------------------------------------
: <<COMM
sudo -K
while true; do
	read -s -p "sudo Password: " password
	echo
	echo "$password" | sudo -S ls / >/dev/null && break
done
COMM

#---------------------------------------------------------------
#create virt network nfsnet
if [[ -z "$NET" ]]; then
	netaddr=77
	NET=nfsnet
	vm -r net netname=nfsnet brname=nfsbr0 subnet=$netaddr #tftproot=/var/lib/tftpboot bootpfile=pxelinux/pxelinux.0
fi


#---------------------------------------------------------------
#create nfs share
nfsshare=/nfsshare
nfsshare2=/usr/bin
vm -r $distro -n nfsserv -p nfs-utils --net $NET --nointeract --force
vmnfsserv=$(vm -r --getvmname $distro -n nfsserv)
vm -rv exec $vmnfsserv -- systemctl stop firewalld
vm -rv exec $vmnfsserv -- mkdir -p $nfsshare $nfsshare2
vm -rv exec $vmnfsserv -- "echo '$nfsshare *(rw,no_root_squash,security_label)' >/etc/exports"
vm -rv exec $vmnfsserv -- "echo '$nfsshare2 *(ro,no_root_squash,security_label)' >>/etc/exports"
vm -rv exec $vmnfsserv -- systemctl restart nfs-server
vm -rv exec $vmnfsserv -- touch $nfsshare/testfile
vm -rv exec $vmnfsserv -- ls -lZ $nfsshare/testfile $nfsshare2/bash


nfsmp=/mnt/nfsmp
nfsmp2=/mnt/nfsmp2
vm -r $distro -n nfsclnt -p nfs-utils --net $NET --nointeract --force
vmnfsclnt=$(vm -r --getvmname $distro -n nfsclnt)
vm -rv exec $vmnfsclnt -- systemctl stop firewalld
vmnfsservaddr=$(vm -r if $vmnfsserv)
vm -rv exec $vmnfsclnt -- mkdir -p $nfsmp $nfsmp2
vm -rvx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare $nfsmp -overs=4.2,actimeo=1,sync
vm -rvx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare2 $nfsmp2 -overs=4.2,actimeo=1,sync,ro
vm -rvx exec $vmnfsserv -- ls -lZ $nfsshare/testfile $nfsshare2/bash
vm -rvx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile $nfsmp2/bash

vm -rv exec $vmnfsclnt -- sleep 1

scontextServ=$(vm -rv exec $vmnfsserv -- stat -c %C $nfsshare/testfile)
scontextClnt=$(vm -rv exec $vmnfsclnt -- stat -c %C $nfsmp/testfile)
vm -rvx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'"

scontextServ2=$(vm -rv exec $vmnfsserv -- stat -c %C $nfsshare2/bash)
scontextClnt2=$(vm -rv exec $vmnfsclnt -- stat -c %C $nfsmp2/bash)
vm -rvx exec $vmnfsclnt -- "test '$scontextServ2' = '$scontextClnt2'"

