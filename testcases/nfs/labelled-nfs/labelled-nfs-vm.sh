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
#create nfs server and client VMs
vm -r $distro -n nfsserv -p nfs-utils --net $NET --nointeract --force
vmnfsserv=$(vm -r --getvmname $distro -n nfsserv)
vm -r $distro -n nfsclnt -p nfs-utils --net $NET --nointeract --force
vmnfsclnt=$(vm -r --getvmname $distro -n nfsclnt)
vm -v exec $vmnfsserv -- systemctl stop firewalld
vm -v exec $vmnfsclnt -- systemctl stop firewalld

#---------------------------------------------------------------
# test0
nfsshare=/nfsshare
echo -e "\n"
echo "Test 0: export $nfsshare" | GREP_COLORS='ms=44' grep --color=always .
vm -v exec $vmnfsserv -- rm -rf $nfsshare
vm -v exec $vmnfsserv -- mkdir -p $nfsshare
vm -v exec $vmnfsserv -- "echo '$nfsshare *(rw,no_root_squash,security_label)' >/etc/exports"
vm -v exec $vmnfsserv -- systemctl restart nfs-server
vm -v exec $vmnfsserv -- touch $nfsshare/testfile

nfsmp=/mnt/nfsmp
vmnfsservaddr=$(vm -r if $vmnfsserv)
vm -v exec $vmnfsclnt -- mkdir -p $nfsmp
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare $nfsmp -overs=4.2,actimeo=1,sync
echo
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/testfile
echo
vm -v exec $vmnfsclnt -- sleep 1
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/testfile

scontextServ=$(vm -rv exec $vmnfsserv -- stat -c %C $nfsshare/testfile)
scontextClnt=$(vm -rv exec $vmnfsclnt -- stat -c %C $nfsmp/testfile)
vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'"

echo
vm -vx exec $vmnfsclnt -- umount $nfsmp


#---------------------------------------------------------------
# test1
nfsshare=/usr
echo -e "\n"
echo "Test 1: export $nfsshare" | GREP_COLORS='ms=44' grep --color=always .
vm -v exec $vmnfsserv -- systemctl stop firewalld
vm -v exec $vmnfsserv -- "echo '$nfsshare *(ro,no_root_squash,security_label)' >/etc/exports"
vm -v exec $vmnfsserv -- systemctl restart nfs-server
vm -vx exec $vmnfsserv -- cp $nfsshare/bin/bash $nfsshare/bin/bash2
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/bin/bash $nfsshare/bin/bash2

nfsmp=/mnt/nfsusr
vmnfsservaddr=$(vm -r if $vmnfsserv)
vm -v exec $vmnfsclnt -- mkdir -p $nfsmp
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare $nfsmp -overs=4.2,actimeo=1,sync
echo
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/bin/bash $nfsmp/bin/bash2
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/bin/bash $nfsshare/bin/bash2
echo
vm -v exec $vmnfsclnt -- sleep 1
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/bin/bash $nfsmp/bin/bash2
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/bin/bash $nfsshare/bin/bash2

scontextServ=$(vm -rv exec $vmnfsserv -- stat -c %C $nfsshare/bin/bash)
scontextClnt=$(vm -rv exec $vmnfsclnt -- stat -c %C $nfsmp/bin/bash)
vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'  #bash context compare"

scontextServ=$(vm -rv exec $vmnfsserv -- stat -c %C $nfsshare/bin/bash2)
scontextClnt=$(vm -rv exec $vmnfsclnt -- stat -c %C $nfsmp/bin/bash2)
vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'  #bash2 context compare"

echo
vm -vx exec $vmnfsclnt -- umount $nfsmp


#---------------------------------------------------------------
# test2
nfsshare2=/nfsshare2
nfsshareusr=/usr
echo -e "\n"
echo "Test 2: export both $nfsshare2 and $nfsshareusr" | GREP_COLORS='ms=44' grep --color=always .
vm -v exec $vmnfsserv -- mkdir -p $nfsshare2
vm -v exec $vmnfsserv -- "echo '$nfsshare2 *(rw,no_root_squash,security_label)' >/etc/exports"
vm -v exec $vmnfsserv -- "echo '$nfsshareusr *(ro,no_root_squash,security_label)' >>/etc/exports"
vm -v exec $vmnfsserv -- systemctl restart nfs-server
vm -v exec $vmnfsserv -- touch $nfsshare2/testfile
vm -v exec $vmnfsserv -- ls -lZ $nfsshare2/testfile $nfsshareusr/bin/bash


nfsmp=/mnt/nfsmp
nfsusr=/mnt/nfsusr
vm -v exec $vmnfsclnt -- systemctl stop firewalld
vmnfsservaddr=$(vm -r if $vmnfsserv)
vm -v exec $vmnfsclnt -- mkdir -p $nfsmp $nfsusr
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare2 $nfsmp -overs=4.2,actimeo=1,sync
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshareusr $nfsusr -overs=4.2,actimeo=1,sync,ro
echo
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile $nfsusr/bin/bash
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare2/testfile $nfsshareusr/bin/bash
echo
vm -v exec $vmnfsclnt -- sleep 1
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile $nfsusr/bin/bash
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare2/testfile $nfsshareusr/bin/bash

scontextServ=$(vm -rv exec $vmnfsserv -- stat -c %C $nfsshare2/testfile)
scontextClnt=$(vm -rv exec $vmnfsclnt -- stat -c %C $nfsmp/testfile)
vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'"

scontextServ2=$(vm -rv exec $vmnfsserv -- stat -c %C $nfsshareusr/bin/bash)
scontextClnt2=$(vm -rv exec $vmnfsclnt -- stat -c %C $nfsusr/bin/bash)
vm -vx exec $vmnfsclnt -- "test '$scontextServ2' = '$scontextClnt2'"

