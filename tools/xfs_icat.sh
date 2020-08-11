#!/bin/bash
#auth: yin-jianhong@163.com
#just for learn xfs and funny

dev=$1
inum=$2
debug=$3

ftypes[1]=fifo
ftypes[2]=chardrv
ftypes[4]=dir
ftypes[6]=blkdev
ftypes[8]=file
ftypes[10]=symlink
ftypes[12]=socket
bmxField=u.bmx
dataForkOffset=100

inode_ver() {
	local _dev=$1
	local _inum=$2
	IFS=' ()' read ioffsetX ioffsetD < <(xfs_db -r $_dev -c "convert inode $_inum fsbyte")
	local _iver=$(dd status=none if=$_dev bs=1 skip=$((ioffsetD+4)) count=1 | hexdump -e '1/1 "%02x"')
	echo -n $((16#$_iver))
}

[[ -z "$inum" ]] && {
	echo "Usage: sudo xfs_icat <dev> <inum>" >&2
}

#INFO=$(xfs_db -r $dev -c "inode $inum" -c "type inode" -c "print core.version")
#read key eq g_iver <<<"$INFO"
g_iver=$(inode_ver $dev $inum)
test -n "$debug" && echo "core.version = $g_iver" >&2
[[ "$g_iver" = 3 ]] && {
	bmxField=u3.bmx
	dataForkOffset=176
}

inode_extent_array() {
	#ref: https://xfs.org/docs/xfsdocs-xml-dev/XFS_Filesystem_Structure/tmp/en-US/html/Data_Extents.html
	local _dev=$1
	local _inum=$2

	local agblocks=
	local sbINFO=$(xfs_db -r $_dev -c "inode 0" -c "type sb" -c 'print agblocks')
	read key eq agblocks < <(grep agblocks <<<"$sbINFO")
	local _agblocksB=$(echo "obase=2;$agblocks"|bc)
	local agshift=${#_agblocksB}

	IFS=' ()' read ioffsetX ioffsetD < <(xfs_db -r $_dev -c "convert inode $_inum fsbyte")
	local _extentNum=$(dd status=none if=$_dev bs=1 skip=$((ioffsetD+76)) count=4 | hexdump -e '4/1 "%02x"')
	_extentNum=$((16#$_extentNum))

	echo "BMX[0-$((_extentNum-1))] = [startoff,startblock,blockcount,extentflag]"
	local extentX= extent1B= flag= startoff= startblock= blockcount=
	for ((i=0; i<_extentNum; i++)); do
		extentX=$(dd status=none if=$_dev bs=1 skip=$((ioffsetD+dataForkOffset+i*16)) count=16 | hexdump -e '16/1 "%02x"')
		extent1B=$(echo "ibase=16;obase=2;1${extentX^^}"|BC_LINE_LENGTH=256 bc)

		flag=${extent1B:1:1}

		startoff=$(echo "ibase=2;obase=A;${extent1B:2:54}"|bc)

		startblockB=${extent1B:56:52}
		startblock=$(echo "ibase=2;obase=A;${startblockB}"|bc)

		blockcount=$(echo "ibase=2;obase=A;${extent1B:108:21}"|bc)

		[[ "${g_iver:-3}" = 3 ]] && {
			agnumLen=$((52-agshift))
			agnum=$(echo "ibase=2;obase=A;${startblockB:0:${agnumLen}}"|bc)
			relativeblock=$(echo "ibase=2;obase=A;${startblockB:${agnumLen}:${agshift}}"|bc)
			echo " ${i}:[$startoff,$((agnum*agblocks+relativeblock)),$blockcount,$flag,$startblock]"

			test -n "$debug" && echo "agshift: $agshift" >&2
			test -n "$debug" && echo "agnumLen: $agnumLen" >&2
			test -n "$debug" && echo "agnum: $agnum" >&2
			test -n "$debug" && echo "relativeblock: $relativeblock" >&2
		} || {
			echo " ${i}:[$startoff,$startblock,$blockcount,$flag]"
		}
	done
}

[[ "${g_iver:-3}" = 3 ]] && {
	INFO=$(xfs_db -r $dev -c "inode $inum"                 -c "print core.format core.mode core.size" -c "version")
} || {
	INFO=$(xfs_db -r $dev -c "inode $inum" -c "type inode" -c "print core.format core.mode core.size" -c "version")
}

{
read key eq coreformat desc
read key eq mode desc
read key eq fsize
read key eq fsver
} <<<"$INFO"
ftypenum=${mode%????}
ftypenum=$((8#$ftypenum))
test -n "$debug" && echo "$INFO" >&2

: <<\COMM
inode_dump() {
	local _dev=$1
	local _inum=$2
	IFS=' ()' read ioffsetX ioffsetD < <(xfs_db -r $_dev -c "convert inode $_inum fsbyte")
	dd status=none if=$_dev bs=1 skip=$((ioffsetD)) count=256 | hexdump -e '16/1 "%02x " "\n"'
}

#work around for xfs_db bug
inode_info() {
	local _dev=$1
	local _inum=$2
	IFS=' ()' read ioffsetX ioffsetD < <(xfs_db -r $_dev -c "convert inode $_inum fsbyte")

	local _mode=$(dd status=none if=$_dev bs=1 skip=$((ioffsetD+2)) count=2 | hexdump -e '1/1 "%02x"')
	local _ftypenum=${_mode%???}
	local _fsize=$(dd status=none if=$_dev bs=1 skip=$((ioffsetD+56)) count=8 | hexdump -e '8/1 "%02x"')
	echo ftypenum = $((16#$_ftypenum))
	echo fsize = $((16#$_fsize))
}
COMM

ftype=${ftypes[$ftypenum]}
[[ -z "$ftype" ]] && ftype="\033[41mnil\033[m"
echo -e "core.format: $coreformat, ftype: $ftype($ftypenum), fsize: $fsize, iver: $g_iver, fsver: $fsver" >&2
echo >&2

extents_cat() {
	local _dev=$1
	local _fsize=$2
	shift 2

	local sbINFO=$(xfs_db -r $_dev -c "inode 0" -c "type sb" -c 'print blocksize')
	read key eq blocksize < <(grep blocksize <<<"$sbINFO")

	local left=$_fsize
	for extent; do
		test -n "$debug" && echo "{extexts_cat} extent: $extent" >&2
		read idx startoff startblock blockcount extentflag orig_startblock <<< "${extent//[:,\][]/ }"
		extentSize=$((blockcount * blocksize))
		ddcount=$blockcount

		if [[ $extentSize -gt $left ]]; then
			ddcount=$((left/blocksize))
			mod=$((left%blocksize))

			test -n "$debug" && echo "{extexts_cat} left=$left, extentSize=$extentSize; ddcount=$ddcount, mod=$mod" >&2
			echo dd status=none if=$_dev bs=$blocksize skip=$startblock count=$ddcount >&2
			dd status=none if=$_dev bs=$blocksize skip=$startblock count=$ddcount
			echo dd status=none if=$_dev bs=1 skip=$(((startblock+ddcount)*blocksize)) count=$mod >&2
			dd status=none if=$_dev bs=1 skip=$(((startblock+ddcount)*blocksize)) count=$mod
			break
		else
			dd status=none if=$_dev bs=$blocksize skip=$startblock count=$ddcount
		fi

		((left-=(ddcount*blocksize)))
	done
}

case $coreformat in
2)
	extentINFO=$(inode_extent_array $dev $inum)
	read key eq sum extents < <(sed -rn '/bmx|BMX/,${p}' <<<"$extentINFO"|xargs)
	test -n "$debug" && echo "$extentINFO" >&2

	#output file content to stdout
	case $ftype in
	dir)
		extents_cat $dev $fsize $extents | hexdump -C;;
	file|symlink)
		extents_cat $dev $fsize $extents;;
	esac
	;;
1)
	INFO=$(xfs_db -r $dev -c "convert inode $inum fsbyte")
	IFS=' ()' read ioffsetX ioffsetD <<<"$INFO"
	case $ftype in
	dir)
		dd status=none if=$dev bs=1 skip=$((ioffsetD+dataForkOffset)) count=$((fsize)) | hexdump -C;;
	file|symlink)
		dd status=none if=$dev bs=1 skip=$((ioffsetD+dataForkOffset)) count=$((fsize));;
	symlink2)
		xfs_db -r $dev -c "inode $inum" -c "type inode" -c "print u.symlink";;
	*)
		:;;
	esac
	;;
esac
echo >&2
