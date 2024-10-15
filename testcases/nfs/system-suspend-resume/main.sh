#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#test for system suspend and resume

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsserv=nfs-suspend-serv
nfsclnt=nfs-suspend-clnt

### __prepare__ test env build
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

trun -tmux vm create -n $nfsserv $distro -p bind-utils,vim,nfs-utils,tmux --nointeract -I=$imgf -f "$@"
trun       vm create -n $nfsclnt $distro -p bind-utils,vim,nfs-utils,tmux --nointeract -I=$imgf -f "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done

_test=suspend
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
#-------------------------------------------------------------------------------
#nfs-serv: start nfs service
vm cpto -v $nfsserv /usr/bin/make-nfs-server.sh /usr/bin/.
vmrunx - $nfsserv -- make-nfs-server.sh
vmrunx - $nfsserv -- dd if=/dev/urandom of=/nfsshare/rw/largefile.img bs=1M count=512

### __main__ test start
## virsh suspend and resume test
#-------------------------------------------------------------------------------
serv_addr=$(vm if $nfsserv)
clnt_addr=$(vm if $nfsclnt)
vmrunx 0 $nfsclnt -- showmount -e ${nfsserv}
vmrunx 0 $nfsclnt -- mkdir /mnt/nfsmp
vmrunx 0 $nfsclnt -- mount $serv_addr:/nfsshare/rw /mnt/nfsmp
vmrunx 0 $nfsclnt -- mount -t nfs4

#suspend server
trun virsh suspend $nfsserv
trun sleep 8

vmrunx 1-255 $nfsclnt -- showmount -e ${nfsserv}
trun virsh resume  $nfsserv
trun port-available.sh $serv_addr 22 -w
vmrunx 0      $nfsclnt -- showmount -e ${nfsserv}

#suspend client
vmrunx 0 $nfsclnt -- tmux new -d "dd if=/mnt/nfsmp/largefile.img of=/home/largefile.img bs=64"
vmrunx 0 $nfsclnt -- 'sleep 3; ps axf|grep -w d[d]'
trun virsh suspend $nfsclnt
trun sleep 8
trun virsh resume  $nfsclnt
trun port-available.sh $clnt_addr 22 -w
vmrunx 0 $nfsclnt -- 'while ps axf|grep -w d[d]; do sleep 30; done'
vmrunx 0 $nfsclnt -- cmp /mnt/nfsmp/largefile.img /home/largefile.img


## systemctl suspend test
#-------------------------------------------------------------------------------
expect -c '
	set timeout 30
	spawn virsh console '"$nfsserv"'
	expect "Escape character is*" { send "\r"; }
	expect {
		"login:" {
			send "root\r";
			expect "*:" { send "redhat\r"; }
		}
		"*# " { send "\r"; }
	}
	expect "*# " { send "uname -r\r"; }
	expect "*# " { send "systemctl suspend\r"; }
	expect {
		"PM: suspend exit" { send "\r"; exit; }
		timeout {
			send_user "\n{INFO} seems systemctl suspend success\n"
			exit 0
		}
	}
'
#resume
vm vnc "$nfsserv" -putln ""

trun port-available.sh $serv_addr 22 -w
vmrunx 1-255 $nfsserv -- 'dmesg|grep Freezing.of.tasks.failed.after'

} |& tee $resdir/std.log

vm stop $nfsserv $nfsclnt
