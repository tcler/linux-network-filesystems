# How does nmap detect the support NFS version of the Server

This is a sample for using `nmap` and `wireshark` to help detecting what happens in network level

## An `nmap` test for nfs:

An nmap test shows an NFS Server surrently supports the version of NFS in 3 and 4, but how does it done?

The packet has been saved as `nmap_detect_nfs_ver.pcapng`.

```
[root@hp-dl360g9-14 ~]# nmap -sV $BRO -p 2049

Starting Nmap 6.40 ( http://nmap.org ) at 2016-11-11 09:02 EST
Nmap scan report for hp-dl360g9-07.rhts.eng.pek2.redhat.com (10.73.4.163)
Host is up (0.00017s latency).
PORT     STATE SERVICE VERSION
2049/tcp open  nfs     3-4 (RPC #100003)
MAC Address: 3C:A8:2A:0D:74:90 (Unknown)

Service detection performed. Please report any incorrect results at http://nmap.org/submit/ .
Nmap done: 1 IP address (1 host up) scanned in 6.66 seconds
```

## Analysis:

With this sample packet, start analysis:

1. Use `strace` to check which files are involved during this testing period, it seems some `nmap` scripts are used during this peroid:

```
[root@hp-dl360g9-14 ~]# strace -e access nmap -sV $BRO -p 2049
...
access("/proc/net", R_OK)               = 0
access("/proc/net/unix", R_OK)          = 0
access("/usr/bin/../share/nmap/nmap-payloads", R_OK) = 0
access("/usr/bin/../share/nmap/nmap-service-probes", R_OK) = 0
access("/usr/bin/../share/nmap/nmap-rpc", R_OK) = 0
access("/usr/bin/../share/nmap/nmap-rpc", R_OK) = 0
...
```

2. Check the packets with display filter `rpc.program`, map these program numbers with the file `/share/nmap/nmap-rpc`, these are the ture programs being detected by `nmap` this time:

```
rpcbind         100000  portmap sunrpc rpcbind pmapprog # portmapper
rstatd          100001  rstat rup perfmeter rstat_svc rstatprog # remote stats
nfs             100003  nfsprog nfsd    # nfs
ypserv          100004  ypprog  # yellow pages (NIS)
mountd          100005  mount showmount mountprog       # mount demon
```

Check the packets related with NFS with display filter `rpc.program == 100003` will see packets with top level procotol in NFS, the respond packet *42* shows, that is the answer of this problem:

```
rpc.programversion.max == 4
rpc.programversion.min == 3
```

3. The packet *42* answers the packet *31*, use display filter `tcp.stream eq 5` to follow the TCP stream of this call-answer trace, investigate packet *31*:

```
Packet 31:

nfs # the top level packet 31 is nfs, but this packet only has the top level as RPC, the part of NFS is blank
rpc # the top complete level of this packet is rpc
    rpc.xid == 0x06322811 # xid is a transaction identifier, identifies the belongings of rpc calls
    rpc.msgtyp == 0 # this packet is an answer to previous packet`
    rpc.version == 2 # this packet brings the answers in rpc version 2 indicates the RFC of rpc v2 will cover these fields
    # the part of NFS starts here
    rpc.program == 100003 # this program number indicates for nfs
    rpc.programversion == 17929067 # 
    # the part of NFS ends here
    rpc.procedure == 0 # procedure 0 of any RPC protocol have the same behaviours and never require any kind of authentication
    rpc.auth.flavor == 0 # no authentication with this rpc call
```

According to the analysis, the answers of `rpc.programversion` maybe caused by `rpc.programversion == 17929067`, according to RFC 5531 section 8.1:

```
   The RPC call message has three unsigned-integer fields -- remote
   program number, remote program version number, and remote procedure
   number -- that uniquely identify the procedure to be called.
   ...
      o  The remote program does not support the requested version number.
      The lowest and highest supported remote program version numbers
      are returned.
```

Then, it is the answer, the *abnormal programversion* in call will cause the answer with the *lowest* and *highest* program version numbers.

## Tips

- This method will not be useful for NFS minor version 4.1
- `nmap` is very useful in testing services currently carried by a server, a really easy approach and some more powerful ones with self customizing:

```
nmap -A -T4 %targetIP # Very handy
nmap --dns-servers [DNS] [target] # Specify DNS servers othr then system default
namp -sS [target] # Scan targets with TCP SYN packets
nmap -sN [target] # Scan targets with TCP NULL packets 
nmap -sF [target] # Scan targets with TCP Finish packets
nmap -sX [target] # Scan targets with TCP special packets like PSH and so on
# There are two powerful ways for scanning
sudo nmap -PU localhost # Scan with UDP Ping, very powerful
nmap -PP localhost # Scan with ICMP timestamp PING, also powerful
```

- `nmap` holds some other interesting scripts on nfs, generally speaking, they are too complicated then just use `bash`, but it shows how to use procedures like `getattr` to detect properties:

```
[root@hp-dl360g9-14 scripts]# ls |grep nfs
nfs-ls.nse
nfs-showmount.nse
nfs-statfs.nse
[root@hp-dl360g9-14 scripts]# pwd
/usr/share/nmap/scripts
```

## Reference

1. [RFC 5531 - RPC: Remote Procedure Call Protocol Specification Version 2](https://tools.ietf.org/html/rfc5531)
2. [Wireshark - Display Filter Reference: Remote Procedure Call](https://www.wireshark.org/docs/dfref/r/rpc.html)