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
vmnfsserv=nfs-server
vmnfsclnt=nfs-client
trun -tmux vm create $distro -n $vmnfsserv -p nfs-utils --net default --nointeract --saveimage -f $VMOPT "$@"
trun       vm create $distro -n $vmnfsclnt -p nfs-utils --net default --nointeract --saveimage -f $VMOPT "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

vm -v exec $vmnfsserv -- systemctl stop firewalld
vm -v exec $vmnfsclnt -- systemctl stop firewalld

vmnfsservaddr=$(vm if $vmnfsserv)
for ((i=0; i<128; i++)); do
	read sharepath file <<<"/var/crash +testfile"
	read sharepath file <<<"/usr/share +testfile"
	echo "Test $i: export $sharepath" | GREP_COLORS='ms=44' grep --color=always .

	#server side
	[[ $sharepath = +* ]] && { sharepath=${sharepath#+}; vm -v exec $vmnfsserv -- mkdir -p $sharepath; }
	[[ $file = +* ]] && { file=${file#+}; vm -v exec $vmnfsserv -- touch $sharepath/$file; }

	vm -vx exec $vmnfsserv -- exportfs -ua
	vm -vx exec $vmnfsserv -- "echo '$sharepath *(rw,no_root_squash,security_label)' >/etc/exports"
	vm -vx exec $vmnfsserv -- systemctl restart nfs-server
	[[ $f = +* ]] && vm -vx exec $vmnfsserv -- touch $sharepath/${file#+}
	vm -vx exec $vmnfsserv -- ls -ldZ $sharepath/${file#+}

	#client side
	nfsmp=/mnt/nfsmp$key
	vm -vx exec $vmnfsclnt -- mkdir -p $nfsmp
	vm -vx exec $vmnfsclnt -- mount $vmnfsservaddr:$sharepath $nfsmp -overs=4.2,actimeo=1,sync

	echo
	vm -vx exec $vmnfsclnt -- ls -ldZ $nfsmp/${file#+}
	vm -v exec $vmnfsclnt -- "sync; sleep 2; sync"  #seems no effect
	echo
	vm -vx exec $vmnfsclnt -- ls -ldZ $nfsmp/${file#+}
	echo

	#compare the context between server and client
	scontextServ=$(vm -v exec $vmnfsserv -- stat -c %C $sharepath/${file#+})
	scontextClnt=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsmp/${file#+})
	vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'" || {
		for ((j=0; j<32; j++)); do
			sleep 2
			scontextClnt=$(vm -v exec $vmnfsclnt -- stat -c %C $nfsmp/${file#+})
			vm -vx exec $vmnfsclnt -- "test '$scontextServ' = '$scontextClnt'" && break
		done
		#break
	}

	echo
	vm -vx exec $vmnfsclnt -- umount $nfsmp
	echo
	echo
done

