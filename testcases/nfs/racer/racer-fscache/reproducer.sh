#!/bin/bash

server_distro=RHEL-7.8
vm $server_distro -msize=4000 -f -n nfsserver -xdisk 16 --kdump --nointeract
nfsserv=nfsserverX
vm exec $nfsserv -- mkdir /data
vm exec $nfsserv -- mkfs.xfs /dev/vdb
vm exec $nfsserv -- 'echo "/dev/vdb                /data      xfs    defaults        0 0" >>/etc/fstab'
vm exec $nfsserv -- mount /dev/vdb
vm exec $nfsserv -- 'echo "/data *(rw,sec=sys:krb5)" >>/etc/exports'
vm exec $nfsserv -- systemctl restart nfs-server
vm exec $nfsserv -- 'time for i in $(seq 1 4000); do dd if=/dev/zero of=/data/file$i.bin bs=1M count=4; done'

client_distro=${1:-RHEL-7.7}
vm $client_distro -cpus=8 -msize=8000 -f -n nfsclient -xdisk 4 -xdisk 4 --kdump -p "mdadm cachefilesd vim" --nointeract
nfsclnt=nfsclientX
vm exec $nfsclnt -- 'mdadm --create /dev/md0 --level=0 --raid-devices=2 /dev/vd[bc]'
vm exec $nfsclnt -- mkfs -t ext4 /dev/md0
vm exec $nfsclnt -- 'echo "/dev/md0                /var/cache/fscache      ext4    defaults        0 0" >>/etc/fstab'
vm exec $nfsclnt -- mount /dev/md0
vm exec $nfsclnt -- mdadm --detail /dev/md0
vm exec $nfsclnt -- chcon -R system_u:object_r:cachefiles_var_t:s0 /var/cache/fscache/
vm exec $nfsclnt -- systemctl enable cachefilesd
vm exec $nfsclnt -- systemctl start cachefilesd
vm exec $nfsclnt -- systemctl status cachefilesd
vm exec $nfsclnt -- mkdir /mnt/nfs
nfsservip=$(vm ifaddr $nfsserv)
vm exec $nfsclnt -- mount -overs=3,fsc $nfsservip:/data /mnt/nfs
cat <<'EOF' >dd-ioload.sh
NFS_MNT=/mnt/nfs
echo 3 > /proc/sys/vm/drop_caches
for i in $(seq 1 2000); do
        dd if=$NFS_MNT/file$i.bin of=/dev/null bs=28k >/dev/null 2>&1 &
done
wait
EOF
scp -o Batchmode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no dd-ioload.sh root@$nfsclnt:
vm exec $nfsclnt -- "while true; do date; time bash ./dd-ioload.sh; done"

