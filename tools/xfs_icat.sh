#!/bin/bash
#auth: yin-jianhong@163.com
#just for learning xfs and funny
#test pass on RHEL-7.3,RHEL-7.4,RHEL-7.9,RHEL-8.2,RHEL-8.3
#
#ref: https://xfs.org/docs/xfsdocs-xml-dev/XFS_Filesystem_Structure/tmp/en-US/html/Data_Extents.html
#ref: https://righteousit.wordpress.com/2018/05/23/xfs-part-2-inodes

dev=$1
inum=$2
debug=$3
realsize=$4

ftypes[1]=fifo
ftypes[2]=chardrv
ftypes[4]=dir
ftypes[6]=blkdev
ftypes[8]=file
ftypes[10]=symlink
ftypes[12]=socket
bmxField=u3.bmx
dataForkOffset=176

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
g_iver=$(inode_ver $dev $inum)
test -n "$debug" && echo "core.version = $g_iver" >&2
[[ "$g_iver" != 3 ]] && {
	bmxField=u.bmx
	dataForkOffset=100
}

_startblock2fsblock() {
	local startblock=$1
	local agshift=$2

	[[ "${g_iver:-3}" != 3 ]] && {
		echo -n "$startblock"
		return
	}

	local startblockB=$(echo "obase=2; ibase=A; $startblock"|bc|xargs printf "%52s"|sed s/\ /0/g)
	local agnumLen=$((52-agshift))
	local agnum=$(echo "ibase=2;obase=A;${startblockB:0:${agnumLen}}"|bc)
	local relativeblock=$(echo "ibase=2;obase=A;${startblockB:${agnumLen}:${agshift}}"|bc)
	echo -n $((agnum*agblocks+relativeblock))
}
startblock2fsblock() {
	local startblock=$1
	local dev=$2

	local agblocks=
	local sbINFO=$(xfs_db -r $dev -c "inode 0" -c "type sb" -c 'print agblocks' 2>/dev/null)
	read key eq agblocks < <(grep agblocks <<<"$sbINFO")
	local agblocksB=$(echo "obase=2;$agblocks"|bc)
	local agshift=${#agblocksB}

	_startblock2fsblock $startblocks $agshift
}

inode_extent_array() {
	#ref: https://xfs.org/docs/xfsdocs-xml-dev/XFS_Filesystem_Structure/tmp/en-US/html/Data_Extents.html
	local _dev=$1
	local _inum=$2

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

		startblock=$(echo "ibase=2;obase=A;${extent1B:56:52}"|bc)

		blockcount=$(echo "ibase=2;obase=A;${extent1B:108:21}"|bc)

		echo " ${i}:[$startoff,$startblock,$blockcount,$flag]"
	done
}

inode_extent_btree() {
	local _dev=$1
	local _inum=$2

	local fsblocks
	btree_node=$(xfs_db -r $_dev -c inode\ $_inum -c p\ u3.bmbt 2>/dev/null)
	read key eq fsblocks < <(egrep 'ptrs\[[0-9-]+] =' <<<"$btree_node")

	walkbtree() {
		local nodeinfo=
		local fsblock=

		for _fsblock; do
			read idx fsblock <<<"${_fsblock/:/ }"
			nodeinfo=$(xfs_db -r $_dev -c fsblock\ $fsblock -c type\ bmapbta -c p)
			if echo "$nodeinfo"|grep -q 'level = 0'; then
				echo "$nodeinfo"|egrep '^[0-9]+:'
			else
				walkbtree $(echo "$nodeinfo"|sed -rn '/ptrs\[[0-9-]+] =/{s///; p}')
			fi
		done
	}
	walkbtree $fsblocks
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

ftype=${ftypes[$ftypenum]}
[[ -z "$ftype" ]] && ftype="\033[41mnil\033[m"
echo -e "core.format: $coreformat, ftype: $ftype($ftypenum), fsize: $fsize, iver: $g_iver, fsver: $fsver" >&2
echo >&2

extents_cat() {
	local _dev=$1
	local _fsize=$2
	shift 2

	local sbINFO=$(xfs_db -r $_dev -c "inode 0" -c "type sb" -c 'print blocksize agblocks' 2>/dev/null)
	read key eq blocksize < <(grep blocksize <<<"$sbINFO")
	read key eq agblocks < <(grep agblocks <<<"$sbINFO")
	local agblocksB=$(echo "obase=2;$agblocks"|bc)
	local agshift=${#agblocksB}

	local left=$_fsize
	while read line; do
		for extent in $line; do
			test -n "$debug" && echo "{extexts_cat} extent: $extent" >&2
			read idx startoff startblock blockcount extentflag orig_startblock <<< "${extent//[:,\][]/ }"
			[[ $startblock =~ ^[0-9]+$ ]] || continue
			startblock=$(_startblock2fsblock $startblock $agshift)
			extentSize=$((blockcount * blocksize))
			ddcount=$blockcount


			if [[ $extentSize -gt $left ]]; then
				ddcount=$((left/blocksize))
				mod=$((left%blocksize))

				test -n "$debug" && echo "{extexts_cat} left=$left, extentSize=$extentSize; ddcount=$ddcount, mod=$mod" >&2
				echo dd status=none if=$_dev bs=$blocksize skip=$startblock count=$ddcount >&2
				dd status=none if=$_dev bs=$blocksize skip=$startblock count=$ddcount
				[[ $mod != 0 ]] && {
					echo dd status=none if=$_dev bs=1 skip=$(((startblock+ddcount)*blocksize)) count=$mod >&2
					dd status=none if=$_dev bs=1 skip=$(((startblock+ddcount)*blocksize)) count=$mod
				}
				break 2
			else
				[[ $ddcount != 0 ]] &&
					dd status=none if=$_dev bs=$blocksize skip=$startblock count=$ddcount
			fi

			((left-=(ddcount*blocksize)))
		done
	done
}

case $coreformat in
3)
	size=4096
	[[ -n "$realsize" ]] && size=$fsize
	extents_cat $dev $size < <(inode_extent_btree $dev $inum)
	;;
2)
	extentINFO=$(inode_extent_array $dev $inum)
	read key eq sum extents < <(sed -rn '/bmx|BMX/,${p}' <<<"$extentINFO"|xargs)
	test -n "$debug" && echo "$extentINFO" >&2

	#output file content to stdout
	case $ftype in
	dir)
		extents_cat $dev $fsize <<<"$extents" | hexdump -C;;
	file|symlink)
		extents_cat $dev $fsize <<<"$extents";;
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
