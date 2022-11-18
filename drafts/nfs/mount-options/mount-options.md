# 本文介绍 linux mount.nfs[4] 各选项的功能和作用

#Options supported by all versions

nfsvers=n || vers=

	nfs 协议版本

soft / hard

	Determines the recovery behavior of the NFS client after an NFS request
	times out. If neither option is specified (or if the hard option is specified),
	NFS requests are retried indefinitely. If the soft option is specified, 
	then the NFS client fails an NFS request after retrans retransmissions have been sent, 
	causing the NFS client to return an error to the calling application.

	hard: 死循环，不退出
	soft: 超时退出

softreval / nosoftreval

	In cases where the NFS server is down, it may be useful to allow the NFS client to 
	continue to serve up paths and attributes from cache after retrans attempts to revalidate 
	that cache have timed out. This may, for instance, be helpful when trying to unmount a 
	filesystem tree from a server that is permanently down.
	#在server没有应答的情况下还可以从cache里获取路径和属性信息，主要应用场景是 server down 了后能 umount
	
	It is possible to combine softreval with the soft mount option, in which case operations 
	that cannot be served up from cache will time out and return an error after retrans attempts. 
	The combination with the default hard mount option implies those uncached operations will 
	continue to retry until a response is received from the server.
	
	Note: the default mount option is nosoftreval which disallows fallback to cache when revalidation 
	fails, and instead follows the behavior dictated by the hard or soft mount option.

intr / nointr

	This option is provided for backward compatibility. It is ignored after kernel 2.6.25.

timeo=n

	客户端等待服务端响应的超时时间，单位是1/10秒。如果传输层协议为TCP的话，
	客户端执行线性回退策略: 即 每次超时后把timeo时间翻一翻，直到最大值600秒

retrans=n

	"attempts further recovery" action 之前的重试次数，默认3次；
	如果超过最大次数，client会生成"server not responding"消息，然后 
	"attempts further recovery" (depending on whether the hard mount option is in effect) 

rsize=n / wsize=n

	最小值1024，最大值1048576；而且必须是1024的整数倍；如果指定数值不是1024整数倍，会向下取整为1024的整数倍

	include/linux/nfs_xdr.h:
	/*
	 * To change the maximum rsize and wsize supported by the NFS client, adjust
	 * NFS_MAX_FILE_IO_SIZE.  64KB is a typical maximum, but some servers can
	 * support a megabyte or more.  The default is left at 4096 bytes, which is
	 * reasonable for NFS over UDP.
	 */
	#define NFS_MAX_FILE_IO_SIZE    (1048576U)
	#define NFS_DEF_FILE_IO_SIZE    (4096U)
	#define NFS_MIN_FILE_IO_SIZE    (1024U)

sync / async  #mark: 新版 man page 已删除

	这个影响的是客户端的IO策略，exportfs 的sync/async影响的是服务端的IO，不存在冲突

ac / noac

	Selects whether the client may cache file attributes. default is ac.
	the noac option forces application writes to become synchronous so that local changes to a file
	become visible on the server immediately

	其他 ac 相关选项:
	acregmin=n
	acregmax=n
	acdirmin=n
	acdirmax=n
	actimeo=n
	acdirmin=n

bg / fg

	bg mount 的使用场景是系统初始化时 防止 /etc/fstab 中的 nfs mount 问题导致系统启动缓慢或无法启动

nconnect=n

	When using a connection oriented protocol such as TCP, it may sometimes be advantageous to set up 
	multiple connections between the client and server. For instance, if your clients and/or servers 
	are equipped with multiple network interface cards (NICs), using multiple connections to spread 
	the load may improve overall performance. In such cases, the nconnect option allows the user to 
	specify the number of connections that should be established between the client and server up to 
	a limit of 16.

	Note that the nconnect option may also be used by some pNFS drivers to decide how many connections 
	to set up to the data servers.

max_connect=n

	While nconnect option sets a limit on the number of connections that can be established to a given 
	server IP, max_connect option allows the user to specify maximum numner of connections to different 
	server IPs that belong to the same NFSv4.1+ server (session trunkable connections) up to a limit of 
	16. When client discovers that it established a client ID to an already existing server, instead of 
	dropping the newly created network transport, the client will add this new connection to the list of 
	available transports for that RPC client.

rdirplus / nordirplus

	Selects whether to use NFS v3 or v4 READDIRPLUS requests.

retry=n

	The  number of minutes that the mount(8) command retries an NFS mount operation in the foreground or background before giving up.

sec=flavors

	A colon-separated list of one or more security flavors.
	Valid flavors are: none, sys, krb5, krb5i, and krb5p.

sharecache / nosharecache

	mount -t nfs -o context=system_u:object_r:user_home_dir_t:s0,sharecache localhost:/exportdir-foo /mnt/nfsmp-foo
	mount -t nfs -o context=system_u:object_r:xferlog_t:s0,sharecache localhost:/exportdir-foo /mnt/nfsmp-foo2  #will get fail

resvport / noresvport

	Specifies whether the NFS client should use a privileged source port when communicating with an NFS server for this mount point.
	"privileged source port" 通常默认值 < 1024; see exportfs option: "secure / insecure"

lookupcache=mode

	设置内核管理给定挂载点的目录项缓存方式。其中包括all/none/pos几种方式。客户端缓存LOOKUP命令字请求结果。
	如果请求的目录项在服务器上，则返回结果为正，否则为负。
	 all的管理方式是在父目录缓存的属性失效前客户端缓存这两种目录项；
	 pos是在父目录缓存的属性失效前客户端缓存结果为正的查询结果，总是重新验证结果为负的查询结果。
	 none总是重新验证目录缓存项。
	默认为all管理方式，内核2.6.28及以后版本支持。

	LOOKUP命令字的作用是将文件名转换文件句柄。对于多个客户端经常创建或删除文件的情况，建议使用none。其它情况选用all或者pos。

fsc / nofsc

	Enable/Disables the cache of (read-only) data pages to the local disk using the FS-Cache facility.
	See cachefilesd(8) and <kernel_soruce>/Documentation/filesys‐tems/caching for detail on how to configure 
	the FS-Cache facility. Default value is nofsc.

sloppy

	The sloppy option is an alternative to specifying mount.nfs -s option.


#Options for NFS versions 2 and 3 only

proto=netid

	确定与NFS Server 通信的传输层协议，由于NFSv3 版本没有强制要求TCP 所以可选为TCP/TCPv6/UDP/UDPv6/RDMA

udp

	alias of proto=udp

tcp

	alias of proto=tcp

rdma

	alias of proto=rdma

port=n

	指定 NFS 协议使用的端口，如果不指定或指定为0 则使用rpcbind 返回的服务端NFS 端口

mountport=n

	指定 mount 协议使用的端口，如果不指定或指定为0，则使用rpcbind 返回的服务器端mount 端口

mountproto=netid

	指定 mount 协议通信的传输层协议，可选项为TCP/UDP/RDMA(如果有TI-RPC 支持，可选择TCP/UDP 的IPv6 版本)

mounthost=name

	指定 mountd deamon 所在的host，如果不指定，那么认为 mount host 是NFS Server
	#也就是说支持 nfsd 和 mountd 不在同一台主机的场景?!

mountvers=n

	指定与 mountd 服务通信的 RPC 协议版本号

namlen=n

	指定在本次挂载过程中服务端最大的路径名长度

lock / nolock

	确定是否（默认是）使用锁协议，如果不使用，本地应用程序只能在本地锁定文件，于远程无效

cto / nocto

	enable/disable 缓存一致的特性。通常客户端打开文件时检查是否存在以及是否有权限，当关闭文件时刷新更改。
	当设置为nocto时，客户端使用非标准的试探来检查服务器上文件是否改变，对于只读或文件更改较少时情形有助于提高性能。

	对于文件内容改变很少的场景，如服务器提供只读共享，建议使用nocto选项，这样可以提高性能。对于文件内容经常改变，
	客户端对文件缓存一致性要求较高，建议使用cto参数。

acl / noacl

	指定 NFSACL 协议是否使用，默认的该协议的使用与否由客户端向服务端确定（保持一致）

local_lock=mechanism

	Specifies  whether  to  use local locking for any or both of the flock and the POSIX locking mechanisms.  mechanism can be one of all, flock, posix, or none.  This
	option is supported in kernels 2.6.37 and later.

	The Linux NFS client provides a way to make locks local. This means, the applications can lock files, but such locks provide exclusion only against other  applica‐
	tions running on the same client. Remote applications are not affected by these locks.

	If this option is not specified, or if none is specified, the client assumes that the locks are not local.

	If all is specified, the client assumes that both flock and POSIX locks are local.

	If flock is specified, the client assumes that only flock locks are local and uses NLM sideband protocol to lock files when POSIX locks are used.

	If posix is specified, the client assumes that POSIX locks are local and uses NLM sideband protocol to lock files when flock locks are used.

	To  support  legacy  flock behavior similar to that of NFS clients < 2.6.12, use 'local_lock=flock'. This option is required when exporting NFS mounts via Samba as
	Samba maps Windows share mode locks as flock. Since NFS clients > 2.6.12 implement flock by emulating POSIX locks, this will result in conflicting locks.

	NOTE: When used together, the 'local_lock' mount option will be overridden by 'nolock'/'lock' mount option.



#Options for NFS version 4 only

proto=netid

	确定与 NFS Server 通信的传输层协议，由于 NFSv4 版本强制要求TCP 所以可选为TCP/TCPv6/RDMA

port=n

	指定 NFSv4 协议使用的端口，如果不指定使用默认的2049端口，如果指定为0使用rpcbind 返回的服务端 NFS 端口

cto / nocto

	跟v2/v3的有什么不同? TBD

clientaddr=n.n.n.n

	only affect nfs4.0, no use for nfs4.1 or later

migration / nomigration

	only affect nfs4.0, no use for nfs4.1 or later

