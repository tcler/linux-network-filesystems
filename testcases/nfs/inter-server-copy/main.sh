#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#test for NFS4.2 inter-server copy
#ref: https://access.redhat.com/solutions/7027105

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsservs=nfs-ssc-serverS
nfsservd=nfs-ssc-serverD
nfsclnt=nfs-ssc-client

stopvms() { [[ "${KEEPVM:-${KEEPVMS}}" != yes ]] && vm stop $nfsservs $nfsservd $nfsclnt; }
cleanup() { stopvms 2>/dev/null; }
trap "cleanup" EXIT

### __prepare__ test env build
stdlog=$(trun vm create $distro --downloadonly "$@" |& tee /dev/tty)
imgf=$(sed -rn '${/^-[-rwx]{9}.? /{s/^.* //;p}}' <<<"$stdlog")

trun -tmux vm create -n $nfsservs $distro -p bind-utils,vim,nfs-utils --nointeract -I=$imgf -f "$@"
trun -tmux vm create -n $nfsservd $distro -p bind-utils,vim,nfs-utils --nointeract -I=$imgf -f "$@"
trun       vm create -n $nfsclnt  $distro -p bind-utils,vim,nfs-utils --nointeract -I=$imgf -f "$@"
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*$$-$USER.*-d.vm.creat[e]; do sleep 16; done
timeout 300 vm port-available -w $nfsservs || { echo "{TENV:ERROR} vm port 22 not available" >&2; exit 124; }

#-------------------------------------------------------------------------------
#nfs-serv*: start nfs service
vm cpto -v $nfsservs /usr/bin/make-nfs-server.sh /usr/bin/.
vm cpto -v $nfsservd /usr/bin/make-nfs-server.sh /usr/bin/.
vmrunx - $nfsservs -- make-nfs-server.sh
vmrunx - $nfsservs -- dd if=/dev/urandom of=/nfsshare/rw/largefile.img bs=1M count=256
vmrunx - $nfsservd -- make-nfs-server.sh

### __main__ test start
_test=inter-server-copy
distrodir=$(gen_distro_dir_name $nfsclnt ${SUFFIX})
resdir=~/testres/${distrodir}/nfs/$_test
mkdir -p $resdir
{
trun -tmux=${_test}-console-$nfsservs -logf=$resdir/console.$nfsservs.log vm console $nfsservs
trun -tmux=${_test}-console-$nfsservd -logf=$resdir/console.$nfsservd.log vm console $nfsservd
trun -tmux=${_test}-console-$nfsclnt  -logf=$resdir/console.$nfsclnt.log  vm console $nfsclnt

#-------------------------------------------------------------------------------
#enable inter-server copy
modulef=/sys/module/nfsd/parameters/inter_copy_offload_enable
vmrunx 0 $nfsservs -- "read val <$modulef; echo -n \$val' - '; echo Y >$modulef; cat $modulef"
vmrunx 0 $nfsservd -- "read val <$modulef; echo -n \$val' - '; echo Y >$modulef; cat $modulef"

#-------------------------------------------------------------------------------
serv_src_addr=$(vm if $nfsservs)
serv_dst_addr=$(vm if $nfsservd)
vmrunx 0 $nfsclnt -- showmount -e ${nfsservs}
vmrunx 0 $nfsclnt -- showmount -e ${nfsservd}
vmrunx 0 $nfsclnt -- mkdir /mnt/src /mnt/dst
vmrunx 0 $nfsclnt -- mount -vvv ${nfsservs}:/nfsshare/rw /mnt/src
vmrunx 0 $nfsclnt -- mount -vvv ${nfsservd}:/nfsshare/rw /mnt/dst
vmrunx 0 $nfsclnt -- mount -t nfs4

vmrunx 0 $nfsclnt -- time cp /mnt/src/largefile.img  /mnt/dst/.
vmrunx 0 $nfsclnt -- "mountstats mountstats /mnt/src | grep -EA 3 '(^COPY(_NOTIFY)?|^READ|^WRITE):'"
vmrunx 0 $nfsclnt -- "mountstats mountstats /mnt/src | grep -EA 3 '(^COPY_NOTIFY):'"
vmrunx 0 $nfsclnt -- "mountstats mountstats /mnt/dst | grep -EA 3 '(^COPY|^READ|^WRITE):'"
vmrunx 0 $nfsclnt -- "mountstats mountstats /mnt/dst | grep -EA 3 '(^COPY):'"

#-------------------------------------------------------------------------------
echo
vmrunx 0 $nfsclnt -- rm /mnt/dst/largefile.img
vm reboot $nfsclnt -w
vmrunx 0 $nfsclnt -- systemctl start proc-fs-nfsd.mount
vmrunx 0 $nfsclnt -- "read val <$modulef; echo -n \$val' - '; echo Y >$modulef; cat $modulef"
vmrunx 0 $nfsclnt -- mount -vvv ${nfsservs}:/nfsshare/rw /mnt/src
vmrunx 0 $nfsclnt -- mount -vvv ${nfsservd}:/nfsshare/rw /mnt/dst
vmrunx 0 $nfsclnt -- mount -t nfs4
vmrunx 0 $nfsclnt -- time cp /mnt/src/largefile.img  /mnt/dst/.
vmrunx 0 $nfsclnt -- "mountstats mountstats /mnt/src | grep -EA 3 '(^COPY(_NOTIFY)?|^READ|^WRITE):'"
vmrunx 0 $nfsclnt -- "mountstats mountstats /mnt/src | grep -EA 3 '(^COPY_NOTIFY):'"
vmrunx 0 $nfsclnt -- "mountstats mountstats /mnt/dst | grep -EA 3 '(^COPY|^READ|^WRITE):'"
vmrunx 0 $nfsclnt -- "mountstats mountstats /mnt/dst | grep -EA 3 '(^COPY):'"

vmrunx - $nfsclnt -- "dmesg | grep TECH.PREVIEW /var/log/messages"

trun -x1-255 grep RI[P]: $resdir/console*.log
stopvms
} &> >(tee $resdir/std.log)

tcnt
