#!/bin/bash
#auth: yin-jianhong@163.com

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
inode_ver() {
	local _dev=$1
	local _inum=$2
	IFS=' ()' read ioffsetX ioffsetD < <(xfs_db -r $_dev -c "convert inode $_inum fsbyte" -c "inode $_inum")
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
}

[[ "$g_iver" = 3 ]] && {
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
	IFS=' ()' read ioffsetX ioffsetD < <(xfs_db -r $_dev -c "convert inode $_inum fsbyte" -c "inode $_inum")
	dd status=none if=$_dev bs=1 skip=$((ioffsetD)) count=256 | hexdump -e '16/1 "%02x " "\n"'
}

#work around for xfs_db bug
inode_info() {
	local _dev=$1
	local _inum=$2
	IFS=' ()' read ioffsetX ioffsetD < <(xfs_db -r $_dev -c "convert inode $_inum fsbyte" -c "inode $_inum")

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

	local left=$_fsize
	for extent; do
		test -n "$debug" && echo "{extexts_cat} extent: $extent" >&2
		read idx startoff startblock blockcount extentflag  <<< "${extent//[:,\][]/ }"
		extentSize=$((blockcount * g_blocksize))
		ddcount=$blockcount
		#[[ $g_iver = 3 ]] && startblock=$((startblock - 12288))

		if [[ $extentSize -gt $left ]]; then
			ddcount=$((left/g_blocksize))
			mod=$((left%g_blocksize))

			test -n "$debug" && echo "{extexts_cat} left=$left, extentSize=$extentSize; ddcount=$ddcount, mod=$mod" >&2
			echo dd status=none if=$_dev bs=$g_blocksize skip=$startblock count=$ddcount >&2
			dd status=none if=$_dev bs=$g_blocksize skip=$startblock count=$ddcount
			echo dd status=none if=$_dev bs=1 skip=$(((startblock+ddcount)*g_blocksize)) count=$mod >&2
			dd status=none if=$_dev bs=1 skip=$(((startblock+ddcount)*g_blocksize)) count=$mod
			break
		else
			dd status=none if=$_dev bs=$g_blocksize skip=$startblock count=$ddcount
		fi

		((left-=(ddcount*g_blocksize)))
	done
}

case $coreformat in
2)
	[[ "$g_iver" = 3 ]] && {
		INFO=$(xfs_db -r $dev \
			-c "inode 0" -c "type sb" -c 'print blocksize' \
			-c "inode $inum"                  -c "print $bmxField")
	} || {
		INFO=$(xfs_db -r $dev \
			-c "inode 0" -c "type sb" -c 'print blocksize' \
			-c "inode $inum" -c "type inode" -c "print $bmxField")
	}
	read key eq g_blocksize < <(grep blocksize <<<"$INFO")
	read key eq sum extents < <(sed -n '/bmx/,${p}' <<<"$INFO"|xargs)
	test -n "$debug" && echo "$INFO" >&2

	#output file content to stdout
	case $ftype in
	dir)
		extents_cat $dev $fsize $extents | hexdump -C;;
	file|symlink)
		extents_cat $dev $fsize $extents;;
	esac
	;;
1)
	case $g_iver in (1) localoffset=100;; (2) localoffset=100;; (3) localoffset=176;; esac
	INFO=$(xfs_db -r $dev -c "convert inode $inum fsbyte" -c "inode $inum")
	IFS=' ()' read ioffsetX ioffsetD <<<"$INFO"
	case $ftype in
	dir)
		dd status=none if=$dev bs=1 skip=$((ioffsetD+localoffset)) count=$((fsize)) | hexdump -C;;
	file|symlink)
		dd status=none if=$dev bs=1 skip=$((ioffsetD+localoffset)) count=$((fsize));;
	symlink2)
		xfs_db -r $dev -c "inode $inum" -c "type inode" -c "print u.symlink";;
	*)
		:;;
	esac
	;;
esac
echo >&2
