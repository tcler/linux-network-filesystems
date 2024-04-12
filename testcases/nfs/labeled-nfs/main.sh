#!/bin/bash

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

argv=()
for arg; do
	case "$arg" in
	-upk) VMOPT+=" --brewinstall=upk";;
	-h)   echo "Usage: $0 [-h] [distro] [-upk] [-force|-f]"; exit;;
	-*)   echo "{WARN} unkown option '${arg}'";;
	*)    argv+=($arg);;
	esac
done
set -- "${argv[@]}"

distro=${1:-9}; shift

#---------------------------------------------------------------
#create nfs server and client VMs
vmnfsserv=labeled-nfs-serv
vmnfsclnt=labeled-nfs-clnt

stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

trun -tmux vm create $distro -n $vmnfsserv -p nfs-utils --net default --nointeract -I=$imgf -f $VMOPT "$@"
trun       vm create $distro -n $vmnfsclnt -p nfs-utils --net default --nointeract -I=$imgf -f $VMOPT "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm -v exec $vmnfsserv -- systemctl stop firewalld
vm -v exec $vmnfsclnt -- systemctl stop firewalld
vm -v exec $vmnfsserv -- ln -sf /opt /optlink

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

vmnfsservaddr=$(vm if $vmnfsserv)

distro=$(vm homedir $vmnfsclnt|awk -F/ 'NR==1{print $(NF-1)}')
distrodir=$distro; [[ -n "${SUFFIX}" ]] && distrodir+=-${SUFFIX}
resdir=~/testres/$distrodir/nfs-function
mkdir -p $resdir
{
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
	vm -v exec $vmnfsclnt -- "sync; sleep 2; sync"
	for f in ${files//,/ }; do
		vm -vx exec $vmnfsclnt -- ls -ldZ $nfsmp/${f#+}
	done
	echo
	for f in ${files//,/ }; do
		for ((i=0; i<32; i++)); do
			scontextServ=$(vm -v exec $vmnfsserv -- stat -c %C $sharepath/${f#+})
			scontextClnt=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsmp/${f#+})
			vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'" && break || sleep 2
		done
	done

	echo
	vm -vx exec $vmnfsclnt -- umount $nfsmp
	echo
	echo
done

} |& tee $resdir/labeled-nfs.log

vm stop $vmnfsserv $vmnfsclnt
