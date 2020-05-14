#!/bin/bash

#DEV=192.168.122.1:/home/nfs/share1
#MNT=/mnt/nfs
#KPROBE_OFFSET=217

DEV=$1
MNT=$2
KPROBE_OFFSET=$3

DELAY=100

Stop()
{
	killall reader.sh
	rmmod nfsint
}
trap "Stop; exit 3" HUP TERM INT

if [[ -z $DEV ]] || [[ -z $MNT ]] || [[ -z $KPROBE_OFFSET ]]; then
	echo "Error: Set DEV, MNT and KPROBE_OFFSET parameter"
	exit 1
fi	

TOPDIR=`pwd`

mount $DEV $MNT

cd kprobe
make clean
echo "#define OFFSET $KPROBE_OFFSET" > offset.h
make
insmod nfsint.ko delay=$DELAY
if [[ $? -ne 0 ]]; then
	echo "Error: Failed to load the kprobe module to emulate the interrupt."
	echo "Error: Check OFFSET is correct. Current: $KPROBE_OFFSET"
	umount $MNT
	exit 2
fi
cd $TOPDIR

echo hello > $MNT/testfile

taskset -c 0 ./reader.sh $MNT/testfile &
taskset -c 1 ./reader.sh $MNT/testfile &

wait
