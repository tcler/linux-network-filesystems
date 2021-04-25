#!/bin/bash

argv=()
for arg; do
	case "$arg" in
	-net=*) NET=${arg#*=};;
	-upk) VMOPT+=" --brewinstall=upk";;
	-f|-force) FORCE_OPT="-f";;
	-h)   echo "Usage: $0 [-h] [distro] [-net=netname] [-upk] [-force|-f]"; exit;;
	-*)   echo "{WARN} unkown option '${arg}'";;
	*)    argv+=($arg);;
	esac
done
set -- "${argv[@]}"

distro=${1:-RHEL-8.1.0}

#---------------------------------------------------------------
#install kiss-vm
install-kiss-vm-ns() {
	local _name=$1
	local KissUrl=https://github.com/tcler/kiss-vm-ns
	which vm &>/dev/null || {
		echo -e "{info} installing kiss-vm-ns ..."
		which git &>/dev/null || yum install -y git
		while true; do
			git clone --depth=1 "$KissUrl" && make -C kiss-vm-ns
			which vm && break
			sleep 5
			echo -e "{warn} installing kiss-vm-ns  fail, try again ..."
		done
	}
	[[ "$_name"x = "vm"x ]] && vm prepare
}
install-kiss-vm-ns vm

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
vm $distro -n nfsserv -p nfs-utils --net $NET --nointeract --saveimage $VMOPT $FORCE_OPT
vmnfsserv=$(vm --getvmname $distro -n nfsserv)
vm $distro -n nfsclnt -p nfs-utils --net $NET --nointeract --saveimage $VMOPT $FORCE_OPT
vmnfsclnt=$(vm --getvmname $distro -n nfsclnt)
vm -v exec $vmnfsserv -- systemctl stop firewalld
vm -v exec $vmnfsclnt -- systemctl stop firewalld
vmnfsservaddr=$(vm if $vmnfsserv)
vm -v exec $vmnfsserv -- ln -sf /opt /optlink
#vm -v exec $vmnfsserv -- ln -sf /crash /var/crash
#vm -v exec $vmnfsserv -- rm /crash

tests=(
	/:+testfile,usr/bin/bash
	+/nfsshare1:+testfile
	/boot:grub2
	/etc:nfs.conf
	/home:foo
	/tmp:+labelled-nfs.txt
	/usr:bin/bash
	/var:lib

	/usr/lib64:gawk
	/usr/lib:systemd
	/usr/bin:bash
	/usr/sbin:rpc.nfsd
	/usr/share:awk

	/home/foo:+testfile

	/opt:+testfile
	/var/crash:+testfile

	+/opt/nfsshare:+testfile
	+/home/nonuser:+testfile
	@/nfsshare/share1:+testfile
)

for key in "${!tests[@]}"; do
	read sharepath files <<<"${tests[$key]/:/ }"
	echo "Test $key: export $sharepath" | GREP_COLORS='ms=44' grep --color=always .

	#server side
	[[ $sharepath = +* ]] && {
		sharepath=${sharepath#+}
		vm -v exec $vmnfsserv -- mkdir -p $sharepath
	}
	[[ $sharepath = @* ]] && {
		sharepath=${sharepath#@}
		vm -v exec $vmnfsserv -- mkdir -p $sharepath
		vm -v exec $vmnfsserv -- dd if=/dev/zero of=/nfsshare.img bs=1M count=500
		vm -v exec $vmnfsserv -- mkfs.xfs -f /nfsshare.img
		vm -v exec $vmnfsserv -- mount -oloop /nfsshare.img $sharepath
	}
	vm -vx exec $vmnfsserv -- "echo '$sharepath *(rw,no_root_squash,security_label)' >/etc/exports"
	vm -vx exec $vmnfsserv -- systemctl restart nfs-server
	for f in ${files//,/ }; do
		[[ $f = +* ]] && vm -vx exec $vmnfsserv -- touch $sharepath/${f#+}
		vm -vx exec $vmnfsserv -- ls -ldZ $sharepath/${f#+}
	done

	#client side
	nfsmp=/mnt/nfsmp$key
	vm -vx exec $vmnfsclnt -- mkdir -p $nfsmp
	vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$sharepath $nfsmp -overs=4.2,actimeo=1,sync

	echo
	for f in ${files//,/ }; do
		vm -vx exec $vmnfsclnt -- ls -ldZ $nfsmp/${f#+}
	done
	echo
	vm -v exec $vmnfsclnt -- sleep 1
	for f in ${files//,/ }; do
		vm -vx exec $vmnfsclnt -- ls -ldZ $nfsmp/${f#+}
	done
	echo
	for f in ${files//,/ }; do
		scontextServ=$(vm -v exec $vmnfsserv -- stat -c %C $sharepath/${f#+})
		scontextClnt=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsmp/${f#+})
		vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'"
	done

	echo
	vm -vx exec $vmnfsclnt -- umount $nfsmp
	echo
	echo
done

