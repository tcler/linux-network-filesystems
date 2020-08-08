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


[[ -z "$inum" ]] && {
        echo "Usage: sudo xfs_icat <dev> <inum>" >&2
}

#get super block info: blocksize, $inum core.size and extents list
{
read key eq coreformat desc
read key eq mode desc
read key eq fsize
read key eq iver
read key eq fsver
} < <(xfs_db -r $dev -c "inode $inum" -c "print core.format core.mode core.size core.version" -c "version")
ftypenum=${mode%????}
ftypenum=$((8#$ftypenum))

: <<\COMM
#work around for xfs_db bug
inode_v3() {
        local _dev=$1
        local _inum=$2
        IFS=' ()' read ioffsetX ioffsetD < <(xfs_db -r $_dev -c "convert inode $_inum fsbyte" -c "inode $_inum")

	local _mode=$(dd status=none if=$_dev bs=1 skip=$((ioffsetD+2)) count=2 | hexdump -e '1/1 "%02x"')
	local _ftypenum=${_mode%???}
	local _fsize=$(dd status=none if=$_dev bs=1 skip=$((ioffsetD+56)) count=8 | hexdump -e '8/1 "%02x"')
	echo ftypenum = $((16#$_ftypenum))
	echo fsize = $((16#$_fsize))
}
[[ "$iver" = 3 ]] && {
	{
	read key eq ftypenum
	read key eq fsize
	} < <(inode_v3 $dev $inum)
}
COMM

ftype=${ftypes[$ftypenum]}
echo -e "core.format: $coreformat, ftype: $ftype($ftypenum), fsize: $fsize, iver: $iver, fsver: $fsver" >&2
echo >&2

extents_cat() {
        local _fsize=$1
        shift

        left=$_fsize
        for extent; do
                echo "extent: $extent" >&2
                read idx startoff startblock blockcount extentflag  <<< ${extent//[:,\][]/ }
                extentSize=$((ddcount * blocksize))
                ddcount=$blockcount

                if [[ $extentSize -gt $left ]]; then
                        ddcount=$((left/blocksize))
                        mod=$((left%blocksize))

                        echo "left=$left, extentSize=$extentSize; ddcount=$ddcount, mod=$mod" >&2
                        dd status=none if=$dev bs=$blocksize skip=$startblock count=$ddcount
                        dd status=none if=$dev bs=1 skip=$(((startblock+ddcount)*blocksize)) count=$mod
                        break
                else
                        dd status=none if=$dev bs=$blocksize skip=$startblock count=$ddcount
                fi

                ((left-=(ddcount*blocksize)))
        done
}

case $coreformat in
2)
        INFO=$(xfs_db -r $dev \
                -c "inode 0" -c "type sb" -c 'print blocksize' \
                -c "inode $inum" -c "type inode" -c "print u.bmx")
        {
        read key eq blocksize
        read key eq sum extents
        } <<< "$INFO"

        #output file content to stdout
        case $ftype in
        dir)
                extents_cat $fsize $extents | hexdump -C;;
        file|symlink)
                extents_cat $fsize $extents;;
        esac
        ;;
1)
        case $iver in (1) localoffset=100;; (2) localoffset=100;; (3) localoffset=176;; esac
        INFO=$(xfs_db -r $dev -c "convert inode $inum fsbyte" -c "inode $inum")
        IFS=' ()' read ioffsetX ioffsetD <<<"$INFO"
        echo "inode_offset: $INFO" >&2
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
