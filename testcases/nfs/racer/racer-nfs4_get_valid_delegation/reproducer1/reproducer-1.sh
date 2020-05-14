#!/bin/bash

distro=$1

mkdir -p /nfsshare 
echo "/nfsshare *(rw,no_root_squash)" >/etc/exports
systemctl start nfs-server

vm $distro -n nfsclient --kdump -f -p "vim gcc make kernel-devel" --nointeract
vm exec nfsclient -- mkdir /mnt/nfs
vm exec nfsclient -- mount 192.168.122.1:/nfsshare /mnt/nfs

cat <<'EOF' >reproducer.sh
#!/bin/bash

proc1(){
    echo racer | /usr/bin/wc
}

proc2(){
    seq 10 | /usr/bin/wc
}

tcreate(){
    echo racer > testfile$1
}

tremove(){
    rm testfile$1
}

export -f proc1
export -f proc2

filenum=200

cd $1

while true; do
    # filenum value check.
    if test $filenum -eq 200; then
    	filenum=0
    fi

    # Delete testfile$
    tremove $filenum

    sync;
    echo 3 > /proc/sys/vm/drop_caches

    seq 1 2 | xargs -P 2 -I % bash -c "proc%"

    # Create testfile$
    tcreate $filenum

    sync;
    echo 3 > /proc/sys/vm/drop_caches

    # Incrementation
    let filenum++
done
EOF

scp -o Batchmode=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no reproducer.sh root@nfsclient:/mnt/nfs/.
vm exec nfsclient -- bash /mnt/nfs/reproducer.sh /mnt/nfs
