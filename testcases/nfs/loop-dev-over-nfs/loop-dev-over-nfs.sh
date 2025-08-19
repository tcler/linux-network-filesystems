#!/bin/bash

#https://github.com/tcler/kiss-vm-ns/blob/master/utils/make-nfs-server.sh
#please run make-nfs-server.sh first

mkdir -p /product /product_nfs
mount -v localhost:/var/nfsshare/rw /product_nfs || exit
dd if=/dev/zero of=/product_nfs/loop_fs bs=1024K count=20000 status=progress
losetup /dev/loop0 /product_nfs/loop_fs
mkfs -t xfs /dev/loop0
mount -v /dev/loop0 /product
uname -r

largf=~/ora.tgz
dd if=/dev/urandom of=$largf bs=1M count=9000 status=progress
cksum ora.tgz | awk '{ printf("%s %s\n",$1,$2) }' >cksum.txt
counter=0
for ((i=0; i<32; i++)); do
	printf "loop %02d: " $i

        echo -n "a. copy to /product/${largf##*/}. "
        rm -rf /product/ora.tgz; cp -p $largf /product

        echo    "b. generate cksum of /product/${largf##*/} and diff with orig"
        cksum /product/ora.tgz > /tmp/test.cksum
        cat /tmp/test.cksum | awk '{ printf("%s %s\n",$1,$2) }' > test.cksum
        diff test.cksum cksum.txt
        retval=$?
        #debug
        if [ $retval -gt 0 ]; then
                echo "  checksum error in copied file retval=$retval"
                exit 1
        fi
        sleep 5
        #echo "echo 3 > /proc/sys/vm/drop_caches"
        #echo 3 > /proc/sys/vm/drop_caches
done
