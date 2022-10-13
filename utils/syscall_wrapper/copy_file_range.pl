#!/usr/bin/perl
#
# a syscall wrapper in perl for copy_file_range(2) test
# author: Jianhong Yin <yin-jianhong@163.com>
#
# ref: https://github.com/tcler/linux-network-filesystems/blob/master/utils/h2ph.sh
require 'syscall.ph';  # may need to run h2ph first ^^^
use POSIX ();

my $argc = @ARGV;
if ($argc < 2) {
	say STDERR "Usage: $0 <destination[:offset]> <<source|->[:offset]> [len]";
	say STDERR "`note: source is '-' means that 'fd_in' equal 'fd_out' # see copy_file_range(2)";
	say STDERR "  e.g1: $0 testfile:256  -  64";
	say STDERR "  e.g2: $0 fileout  filein  1024";
	exit 1;
}

#parse args
my ($dst_file, $off_out) = split(/:/, $ARGV[0]);
my ($src_file, $off_in) = split(/:/, $ARGV[1]);

#open test files
my $fd_in = 0;
my $fd_out = 0;
$fd_out = POSIX::open($dst_file, &POSIX::O_RDWR|&POSIX::O_CREAT, 0666) ||
	die "POSIX::open $dst_file fail: $!";
if ($src_file eq "-" || $src_file eq "") {
	$fd_in = $fd_out;
} else {
	$fd_in = POSIX::open($src_file, &POSIX::O_RDONLY) ||
		die "POSIX::open $src_file fail: $!";
}

#get offset and len
my $len = -s $src_file;
if ($fd_in == $fd_out && $off_out eq "") {
	$off_out = $len;
}
$off_out = 0 if ($off_out eq "");
$off_in = 0 if ($off_in eq "");

$off_in = pack("Q",$off_in);
$off_out = pack("Q",$off_out);
$len = 0+sprintf("%zu", $ARGV[2]) if ($argc >= 3);  #must convert to Integer

say STDOUT "[debug]: fd_in=$fd_in fd_out=$fd_out off_in=$off_in off_out=$off_out len=$len";
#copy_file_range
my $ret = 0;
while (1) {
	$ret = syscall(SYS_copy_file_range(),
			$fd_in, $off_in,
			$fd_out, $off_out,
			$len, 0);
	die "SYS_copy_file_range fail: $!" if ($ret == -1);

	say STDOUT "ret=$ret, len=$len";
	$len -= $ret;
	last if ($len <= 0);
	last if (eof($fd_in));
}

close($fd_in);
close($fd_out) if ($fd_in != $fd_out);
