#!/bin/bash

argv=()
for arg; do
	case "$arg" in
	-h)   echo "Usage: $0 [-h] [distro]";;
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
netaddr=77
vm net netname=nfsnet brname=nfsbr0 subnet=$netaddr #tftproot=/var/lib/tftpboot bootpfile=pxelinux/pxelinux.0


#---------------------------------------------------------------
#create nfs share
nfsshare=/nfsshare
vm $distro -n nfsserv -p nfs-utils --net nfsnet --nointeract --force
vmnfsserv=$(vm --getvmname $distro -n nfsserv)
vm -v exec $vmnfsserv -- systemctl stop firewalld
vm -v exec $vmnfsserv -- mkdir -p $nfsshare
vm -v exec $vmnfsserv -- "echo '$nfsshare *(rw,no_root_squash,security_label)' >/etc/exports"
vm -v exec $vmnfsserv -- systemctl restart nfs-server
vm -v exec $vmnfsserv -- touch $nfsshare/testfile
vm -v exec $vmnfsserv -- ls -lZ $nfsshare/testfile
scontextServ=$(vm -v exec $vmnfsserv -- ls -lZ $nfsshare/testfile)


nfsmp=/mnt/nfsmp
vm $distro -n nfsclnt -p nfs-utils --net nfsnet --nointeract --force
vmnfsclnt=$(vm --getvmname $distro -n nfsclnt)
vmnfsservaddr=$(vm if $vmnfsserv)
vm -v exec $vmnfsclnt -- mkdir -p $nfsmp
vm -v exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare $nfsmp -overs=4.2,actimeo=1,sync
vm -v exec $vmnfsclnt -- ls -lZ $nfsmp/testfile
scontextClnt=$(vm -v exec $vmnfsclnt -- ls -lZ $nfsmp/testfile)
vm -v exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'"

