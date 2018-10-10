# 本文介绍 linux nfs export 各选项的功能和作用

ro / rw

	顾名思义：只读和可读可写; 默认 ro


sec=

	#"gss/krb5", "gss/krb5i", "gss/krb5p" is deprecated. use sec= since 2.6.23 security flavors;
	用来指定认证方式，如果不指定，默认值为 sec=sys；可选值为 sys krb5 krb5i krb5p，也可以指定多个，用 ':' 分隔


secure / insecure

	secure 选项要求 nfs 客户端 mount 请求源端口小于 1024（然而在使用 NAT 网络地址转换时端口一般总是大于1024的），
	默认情况下是开启这个选项的，如果要禁止这个选项，需要显式指定 insecure 选项。客户端 mount 时可以指定 noresvport
	选项来确保使用 > 1024 的端口来向服务端发起请求。
	如果 server 端导出指定了 secure 选项，而客户端端 mount 指定了 noresvport 选项，会得到如下错误:
	 'mount.nfs: Operation not permitted'


sync / async 和 no_wdelay / wdelay

	如果指定 async 选项，表示允许server端可以无需等待写请求的数据提交到磁盘即可返回。如果指定了 sync 并且指定了
	wdelay 选项会使 nfsd 在提交写操作到磁盘之前执行等待操作，等待其他可能相关的写请求到达后再一起提交，从而减少
	总的写等待(磁盘寻址)时间(具体需要实际测试连续写、随机写在机械硬盘和SSD硬盘的效果)。
	相关代码: fs/nfsd/vfs.c: nfsd_vfs_write()

	```
	use_wgather = (rqstp->rq_vers == 2) && EX_WGATHER(exp);

	if (!EX_ISSYNC(exp))
		stable = 0;

	host_err = vfs_writev(file, (struct iovec __user *)vec, vlen, &pos);

	if (stable) {    //sync
		if (use_wgather) {    //wdelay
			host_err = wait_for_concurrent_writes(file);
		} else {
			if (*cnt)
				end = offset + *cnt - 1;
			host_err = vfs_fsync_range(file, offset, end, 0);
		}
	}
	```


nohide / hide

	该选项只在nfsv2 nfsv3生效；
	如果服务端文件系统/A下面挂载了文件系统/A/B；并同时导出 /A /A/B；在客户端mount /A 之后，默认无法浏览/A/B的内容，
	如果在导出/A/B时添加 nohide 就可以在父文件系统中看到了。

	nfsv4中所有导出的文件系统，都可见；不需要指定 nohide


crossmnt

	crossmnt 的作用是导出文件系统时，将其子、孙文件系统一并导出；
	/A  *(rw,crossmnt)
	等价于
	/A  *(rw)
	/A/B  *(rw,nohide)  # nfsv4 可省略nohide
	/A/C  *(rw,nohide)  # nfsv4 可省略nohide

	实际操作发现执行 ls /A/B 之后，其实会在/proc/mounts里生成一个新的mount point，感觉有点像autofs的挂载过程，
	可以单独 umount 这个子 mount point。

	client 端显示的 mountpoint 跟 export 导出项对应关系:
	  1. 如果导出目录为 /mountpoint/a/b/c ，客户端生成
	    $host:/mountpoint  $nfsmp/mountpoint
	  2. 如果导出的目录 /a/b/c /a/b  /a/b/c/d/e 客户端生成
	    $host:/a  $nfsmp/a
	  3. 如果导出的目录 /a/b/c/mountpoint 客户端生成
	    $host:/a  $nfsmp/a;
	    $host:/a  $nfsmp/a/b/c/mountpoint 两个mount item


*no_subtree_check

	Check whether every file requested by the client is in the exported subdirectory of Server.
	From  release 1.1.0 of nfs-utils onwards, the default will be no_subtree_check as subtree_checking
	tends to cause more problems than it is worth.	


insecure_locks | no_auth_nlm

	不对加锁请求进行认证(检查用户对请求加锁的file是否有读权限)。


mp[=path] | mountpoint[=path]

	要求被 exported 的目录必须是一个 mountpoint ，才能被正确导出


fsid=num|root|uuid

	nfs需要用它来标识导出的文件系统，如果没有指定，默认使用所在分区的UUID；如果被导出的文件系统没有UUID 才需要指定该选项；
	注: 用 exportfs 测试，如果没有指定该选项，而exportfs又没有找到可用的信息；会给出 warning ，提醒用户需要指定 fsid=
	遗留问题: 哪些特殊文件系统，没有UUID or device number ？


nordirplus

	disable READDIRPLUS 请求；只对nfsv3有效；
	READDIRPLUS 作用: 遍历目录时顺便获取文件列表和文件的属性，从而减少 系统/过程 调用次数，提高效率
	待验证: find 性能


refer=path@host[+host][:path@host[+host]]

	$export  \*(rw,refer=$export2@$server2)
	就是你 mount 的src $server:$export 其实在另外一台 nfs server上 $server2:$export2
	#仅V4可用; 便于 NFS server 迁移，类似 HTTP redirect

replicas=path@host[+host][:path@host[+host]]

	该选项使您能够以管理员的身份将数据的副本放置在多个 NFSv4 服务器上并告知 NFSv4 客户机副本所驻留的位置。
	#仅V4可用; 允许 NFS client 从候选中列表中选一个 NFS server（文件复制需要服务端自己实现）
	#refer 只是重定向，而 replicas 会复制文件多个副本到其他机器
	
pnfs / no_pnfs

	enable pnfs, default is no_pnfs


root_squash / no_root_squash

	[安全] 把root用户映射到anonymous用户

all_squash

	[安全] 把所有用户映射到anonymous用户

anonuid & anongid

	定义具体 anonymous uid/gid的值；可以用 all_squash 加 
	anonuid & anongid 选项，将导出目录定义为只有某个用户/组才有权限

Extra Export Tables: /etc/exports.d/\*.exports

	除了/etc/exports，exportfs命令还会试图找所有 /etc/exports.d/*.exports 文件进行解析
