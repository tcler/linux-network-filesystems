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
	vm net netname=nfsnet brname=nfsbr0 subnet=$netaddr #tftproot=/var/lib/tftpboot bootpfile=pxelinux/pxelinux.0
fi


#---------------------------------------------------------------
#create nfs server and client VMs
vm $distro -n nfsserv -p nfs-utils --net $NET --nointeract --force
vmnfsserv=$(vm --getvmname $distro -n nfsserv)
vm $distro -n nfsclnt -p nfs-utils --net $NET --nointeract --force
vmnfsclnt=$(vm --getvmname $distro -n nfsclnt)
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
vmnfsservaddr=$(vm if $vmnfsserv)
vm -v exec $vmnfsclnt -- mkdir -p $nfsmp
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare $nfsmp -overs=4.2,actimeo=1,sync
echo
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/testfile
echo
vm -v exec $vmnfsclnt -- sleep 1
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/testfile

scontextServ=$(vm -v exec $vmnfsserv -- stat -c %C $nfsshare/testfile)
scontextClnt=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsmp/testfile)
vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'"

echo
vm -vx exec $vmnfsclnt -- umount $nfsmp


#---------------------------------------------------------------
# test1
nfsshare=/usr
echo -e "\n"
echo "Test 1: export $nfsshare" | GREP_COLORS='ms=44' grep --color=always .
vm -v exec $vmnfsserv -- "echo '$nfsshare *(ro,no_root_squash,security_label)' >/etc/exports"
vm -v exec $vmnfsserv -- systemctl restart nfs-server
vm -vx exec $vmnfsserv -- cp $nfsshare/bin/bash $nfsshare/bin/bash2
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/bin/bash $nfsshare/bin/bash2

nfsmp=/mnt/nfsusr
vmnfsservaddr=$(vm if $vmnfsserv)
vm -v exec $vmnfsclnt -- mkdir -p $nfsmp
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare $nfsmp -overs=4.2,actimeo=1,sync
echo
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/bin/bash $nfsmp/bin/bash2
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/bin/bash $nfsshare/bin/bash2
echo
vm -v exec $vmnfsclnt -- sleep 1
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/bin/bash $nfsmp/bin/bash2
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare/bin/bash $nfsshare/bin/bash2

scontextServ=$(vm -v exec $vmnfsserv -- stat -c %C $nfsshare/bin/bash)
scontextClnt=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsmp/bin/bash)
vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'  #bash context compare"

scontextServ=$(vm -v exec $vmnfsserv -- stat -c %C $nfsshare/bin/bash2)
scontextClnt=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsmp/bin/bash2)
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
vmnfsservaddr=$(vm if $vmnfsserv)
vm -v exec $vmnfsclnt -- mkdir -p $nfsmp $nfsusr
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare2 $nfsmp -overs=4.2,actimeo=1,sync
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshareusr $nfsusr -overs=4.2,actimeo=1,sync
echo
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile $nfsusr/bin/bash
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare2/testfile $nfsshareusr/bin/bash
echo
vm -v exec $vmnfsclnt -- sleep 1
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile $nfsusr/bin/bash
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare2/testfile $nfsshareusr/bin/bash

scontextServ=$(vm -v exec $vmnfsserv -- stat -c %C $nfsshare2/testfile)
scontextClnt=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsmp/testfile)
vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'"

scontextServ2=$(vm -v exec $vmnfsserv -- stat -c %C $nfsshareusr/bin/bash)
scontextClnt2=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsusr/bin/bash)
vm -vx exec $vmnfsclnt -- "test '$scontextServ2' = '$scontextClnt2'"

echo
vm -vx exec $vmnfsclnt -- umount $nfsmp
vm -vx exec $vmnfsclnt -- umount $nfsusr


#---------------------------------------------------------------
# test3
nfsshare3=/nfsshare3
nfssharebin=/usr/bin
echo -e "\n"
echo "Test 3: export both $nfsshare3 and $nfssharebin" | GREP_COLORS='ms=44' grep --color=always .
vm -v exec $vmnfsserv -- mkdir -p $nfsshare3
vm -v exec $vmnfsserv -- "echo '$nfsshare3 *(rw,no_root_squash,security_label)' >/etc/exports"
vm -v exec $vmnfsserv -- "echo '$nfssharebin *(ro,no_root_squash,security_label)' >>/etc/exports"
vm -v exec $vmnfsserv -- systemctl restart nfs-server
vm -v exec $vmnfsserv -- touch $nfsshare3/testfile
vm -v exec $vmnfsserv -- ls -lZ $nfsshare3/testfile $nfssharebin/bash


nfsmp=/mnt/nfsmp
nfsbin=/mnt/nfsbin
vmnfsservaddr=$(vm if $vmnfsserv)
vm -v exec $vmnfsclnt -- mkdir -p $nfsmp $nfsbin
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfsshare3 $nfsmp -overs=4.2,actimeo=1,sync
vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$nfssharebin $nfsbin -overs=4.2,actimeo=1,sync
echo
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile $nfsbin/bash
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare3/testfile $nfssharebin/bash
echo
vm -v exec $vmnfsclnt -- sleep 1
vm -vx exec $vmnfsclnt -- ls -lZ $nfsmp/testfile $nfsbin/bash
vm -vx exec $vmnfsserv -- ls -lZ $nfsshare3/testfile $nfssharebin/bash

scontextServ=$(vm -v exec $vmnfsserv -- stat -c %C $nfsshare3/testfile)
scontextClnt=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsmp/testfile)
vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'"

scontextServ2=$(vm -v exec $vmnfsserv -- stat -c %C $nfssharebin/bash)
scontextClnt2=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsbin/bash)
vm -vx exec $vmnfsclnt -- "test '$scontextServ2' = '$scontextClnt2'"

