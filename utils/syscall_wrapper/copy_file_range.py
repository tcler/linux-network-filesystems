#!/usr/bin/python

import sys
import os
import errno
from ctypes import *

libc = CDLL("libc.so.6", use_errno=True)

if 0:
    SYS_copy_file_range = 326 #syscall number __NR_copy_file_range from usr/include/asm/unistd_64.h
    _copy_file_range_syscall = libc.syscall
    _copy_file_range_syscall.restypes = c_int
    _copy_file_range_syscall.argtypes = c_int, \
                                c_int, POINTER(c_uint64), \
                                c_int, POINTER(c_uint64), \
                                c_uint64, c_int
    def copy_file_range(fd_in, off_in, fd_out, off_out, len, flag=0):
        return _copy_file_range_syscall(SYS_copy_file_range, fd_in, off_in, fd_out, off_out, len, flag)
else:
    _copy_file_range = libc.copy_file_range
    _copy_file_range.restypes = c_int
    _copy_file_range.argtypes = \
                        c_int, POINTER(c_uint64), \
                        c_int, POINTER(c_uint64), \
                        c_uint64, c_int
    def copy_file_range(fd_in, off_in, fd_out, off_out, len, flag=0):
        return _copy_file_range(fd_in, off_in, fd_out, off_out, len, flag)

#__main__
if len(sys.argv) < 3:
    print("Usage: " + sys.argv[0] + " <destination[:offset]> <<source|->[:offset]> [len]")
    print("`note: source is '-' means that 'fd_in' equal 'fd_out' # see copy_file_range(2)")
    print("  e.g1: " + sys.argv[0] + " testfile:256  -  64")
    print("  e.g2: " + sys.argv[0] + " fileout  filein  1024")
    sys.exit(1)

#parse args
dst_file, off_out = sys.argv[1].split(':')
src_file, off_in = sys.argv[2].split(':')

#open test files
fd_out = os.open(dst_file, os.O_RDWR|os.O_CREAT, 0666)
if src_file == "-" or src_file == "":
	fd_in = fd_out;
        src_file = dst_file
else:
	fd_in = os.open(src_file, os.O_RDONLY)

#get offset and len
len = os.stat(src_file).st_size
if (fd_in == fd_out and off_out == ""):
    off_out = len
if (off_out == ""):
    off_out = 0
if (off_in == ""):
    off_in = 0
if (sys.argv >= 4):
    len = long(sys.argv[3])
off_in = c_uint64(long(off_in))
off_out = c_uint64(long(off_out))

#test
while True:
    ret = copy_file_range(
                    c_int(fd_in), POINTER(c_uint64)(off_in),
                    c_int(fd_out), POINTER(c_uint64)(off_out),
                    c_uint64(len), 0);
    if ret < 0:
        print("copy_file_range fail: %s" % os.strerror(get_errno()))
        break
    if ret == 0:
        break
    print("ret=%d" % ret)
    len -= ret

os.close(fd_in)
if fd_in != fd_out:
    os.close(fd_out)
