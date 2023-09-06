#!/usr/bin/env bash
#author: Jianhong Yin <yin-jianhong@163.com>
#test for NFS4.2 inter-server copy
#ref: https://access.redhat.com/solutions/7027105

. /usr/lib/bash/libtest || { echo "{ERROR} 'kiss-vm-ns' is required, please install it first" >&2; exit 2; }

[[ $1 != -* ]] && { distro="$1"; shift; }
distro=${distro:-9}
nfsservs=nfs-serv-src
nfsservd=nfs-serv-dst
nfsclnt=nfs-client

### __prepare__ test env build
stdlog=$(trun vm create $distro --downloadonly |& tee /dev/tty)
imgf=$(sed -n '${s/^.* //;p}' <<<"$stdlog")

trun -tmux=- vm create -n $nfsservs $distro -p bind-utils,vim,nfs-utils --nointeract -I=$imgf -f
trun -tmux=- vm create -n $nfsservd $distro -p bind-utils,vim,nfs-utils --nointeract -I=$imgf -f
trun         vm create -n $nfsclnt  $distro -p bind-utils,vim,nfs-utils --nointeract -I=$imgf -f
echo "{INFO} waiting all vm create process finished ..."
while ps axf|grep tmux.new.*-d.vm.creat[e]; do sleep 16; done

#-------------------------------------------------------------------------------
#nfs-serv*: start nfs service
vm cpto -v $nfsservs /usr/bin/make-nfs-server.sh /usr/bin/.
vm cpto -v $nfsservd /usr/bin/make-nfs-server.sh /usr/bin/.
vm exec -v $nfsservs -- make-nfs-server.sh
vm exec -v $nfsservs -- dd if=/dev/urandom of=/nfsshare/rw/largefile.img bs=1M count=256
vm exec -v $nfsservd -- make-nfs-server.sh

#enable inter-server copy
modulef=/sys/module/nfsd/parameters/inter_copy_offload_enable
vm exec -vx $nfsservs -- "read val <$modulef; echo -n \$val' - '; echo Y >$modulef; cat $modulef"
vm exec -vx $nfsservd -- "read val <$modulef; echo -n \$val' - '; echo Y >$modulef; cat $modulef"

### __main__ test start
#-------------------------------------------------------------------------------
serv_src_addr=$(vm if $nfsservs)
serv_dst_addr=$(vm if $nfsservd)
vm exec -vx $nfsclnt -- showmount -e ${nfsservs}
vm exec -vx $nfsclnt -- showmount -e ${nfsservd}
vm exec -vx $nfsclnt -- mkdir /mnt/src /mnt/dst
vm exec -vx $nfsclnt -- mount $serv_src_addr:/nfsshare/rw /mnt/src
vm exec -vx $nfsclnt -- mount $serv_dst_addr:/nfsshare/rw /mnt/dst
vm exec -vx $nfsclnt -- mount -t nfs4

vm exec -vx $nfsclnt -- time cp /mnt/src/largefile.img  /mnt/dst/.
vm exec -vx $nfsclnt -- "mountstats mountstats /mnt/src | grep -EA 3 '(^COPY|^READ|^WRITE)'"
vm exec -vx $nfsclnt -- "mountstats mountstats /mnt/dst | grep -EA 3 '(^COPY|^READ|^WRITE)'"

#-------------------------------------------------------------------------------
echo
vm exec -vx $nfsclnt -- rm /mnt/dst/largefile.img
vm reboot $nfsclnt -w
vm exec -vx $nfsclnt -- systemctl start proc-fs-nfsd.mount
vm exec -vx $nfsclnt -- "read val <$modulef; echo -n \$val' - '; echo Y >$modulef; cat $modulef"
vm exec -vx $nfsclnt -- mount $serv_src_addr:/nfsshare/rw /mnt/src
vm exec -vx $nfsclnt -- mount $serv_dst_addr:/nfsshare/rw /mnt/dst
vm exec -vx $nfsclnt -- mount -t nfs4
vm exec -vx $nfsclnt -- time cp /mnt/src/largefile.img  /mnt/dst/.
vm exec -vx $nfsclnt -- "mountstats mountstats /mnt/src | grep -EA 3 '(^COPY|^READ|^WRITE)'"
vm exec -vx $nfsclnt -- "mountstats mountstats /mnt/dst | grep -EA 3 '(^COPY|^READ|^WRITE)'"

vm exec -v $nfsclnt -- "dmesg | grep TECH.PREVIEW /var/log/messages"
