<autofs/automounter 概览>

# 0 Automounter  (http://en.wikipedia.org/wiki/Automounter)
## 0.1 SunOS automounter
Tom Lyon developed the original automount software at Sun Microsystems: SunOS 4.0 made automounting available in 1988.[1] Sun Microsystems eventually licensed this implementation to other commercial UNIX distributions. Solaris 2.0, first released in 1992, implemented its automounter with a pseudofilesystem called autofs, which communicates with a user-mode daemon that performs mounts. Other Unix-like systems have adopted that implementation of the automounter - including AIX, HP-UX, and Mac OS X 10.5 and later.

## 0.2 Linux automounter
Linux has an independent implementation of an autofs-based automounter; version 5 of that automounter generally operates compatibly with the Solaris automounter.

## 0.3 Berkeley automounter (http://www.am-utils.org)
In December 1989 Jan-Simon Pendry released amd, an automounter "based in spirit" on the SunOS automount program.[2] amd has also become known as the Berkeley Automounter.

## 0.4 Local media auto mount(e.g. linux udev)
Some operating systems also support automatic mounting of external drives (such as disk drives or flash drives that use FireWire or USB connections) and removable media (such as CDs and DVDs). This technology differs from the automounting described here; it involves mounting local media when the user attaches them to or inserts them into the system, rather than mounting directories from remote file servers when a reference is made to them. Linux currently (as of Linux 2.6) uses the user-space program udev for this form of automounting. Some automounting functions have been implemented in the separate program HAL, but As of 2010 are being merged[by whom?] into udev. OpenBSD has hotplugd(8) which triggers special scripts on attach or detach of removable devices, so that user can easily add mounting of removable drives. In Mac OS X, diskarbitrationd carries out this form of automatic mounting.


# 1 autofs
## 1.1 Design

```
    # mount | grep autofs
    /etc/auto.direct on /junk type autofs (rw,relatime,fd=7,pgrp=11722,timeout=300,minproto=5,maxproto=5,direct)
                                                          |
                                                          `-----------------.
                   (ls /junk)                                               | autofs_init_ap() autofs_point->pipefd,kpipefd
                     ^ v                                                    |
                     | |           +----------------+                       | mount(autofs) save the kpipefd info in mountOpt:
                     | |           |  automount[d]  | -> automount -.       |   fd=<>,pgrp=<>
                     | |           +----------------+               |       |
                     ^ v                  ^  %----------------------%       |
    user space       | |                  |  |                              |
                     | |openat            |  |pipe[2] <---------------------%
    =================|=|==================|==|==================================
                     | |                  |  |
    kernel space     | |                  ^  v
                  +--|-|------------------|--|-------+
                  |  | |                  |  |       |            +---------
                  |  | |lookup            |  `-->nfs_rpc_call()-----.
                  |  | `-------->---------%          |            | | nfs_server
                  |  `----------<-----------------------------------%
                  |  /junk                 autofs    |            +---------
                  +----------------------------------+
```

```
* init_ioctl_ctl()
*  if CONTROL_DEVICE accessible use { ctl.ops = &dev_ioctl_ops; }
*  else { ctl.ops = &ioctl_ops; /* open /tmp/autoXXXXXX and mount with autofs */ }
```

## 1.2 Complete

```
    1. fs/autofs (delete since RHEL-7 kernel)
       autofs_root_lookup
         autofs_revalidate
           try_to_fill_dentry
             autofs_wait
               autofs_notify_daemon
    
    2. fs/autofs4 (complete the standard dentry.d_automount)
       Introduce automount support in the VFS (from http://lwn.net)
       -- http://lwn.net/Articles/407940/
       -- http://lwn.net/Articles/422625/
     
       lookup-->lookup_fast or do_last or ...
         follow_managed
           follow_automount
             path->dentry->d_op->d_automount = autofs4_d_automount
               autofs4_mount_wait
                 autofs4_wait
                   autofs4_notify_daemon

    2.1. Documentation/filesystems/vfs.txt : d_automount
    2.2. NFS: Use d_automount() rather than abusing follow_link()
       https://lists.samba.org/archive/samba-technical/2010-July/072253.html
```

## 1.3 Guide
    6 https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Storage_Administration_Guide/nfs-autofs.html
    6 https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/6/html/Identity_Management_Guide/configuring-automount.html
    7 https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Storage_Administration_Guide/nfs-autofs.html

## 1.5 Misc
*    Developer Ian Kent <ikent@redhat.com>  #a nice guy
*    sorece code: https://www.kernel.org/pub/scm/linux/storage/autofs/autofs.git

# 2 AMD
## 2.0 Automounters: Amd vs. Autofs (http://archive09.linux.com/articles/113603)
## 2.1 Design  *why AMD was know as a pure user space complete?

```
*a user space nfs server*
                   (ls /junk)  (localhost:/a/junk)
                     ^ v
                     | |       +-------------------------+
                     | |       |         AMD             |-> automount --.
                     | |       | a user space nfs server |-<-------------%
                     | |       +-------------------------+
                     ^ v                  ^ %
    user space       | |                  | |
                     | |                  | |
    =================|=|==================|=|===================================
                     | |                  | |
    kernel space     | |                  ^ v
                  +--|-|------------------|-|-------+
                  |  | |                  | |       |            +---------
                  |  | | RPC_open         | `-->nfs_rpc_call()-----.       
                  |  | `-------->---------%         |            | |  nfs_server
                  |  `----------<----------------------------------%       
                  |  /junk                   nfs    |            +---------
                  +---------------------------------+
```

# 3 Communication between kernel and user space.
## 3.0 syscall? no, here we talk about the kernel as the initiator
## 3.1 Open a pipe, and transfer the pipefd to kernel by mount option, or autofs_dev_ioctl

```
    /etc/auto.direct on /junk type autofs (rw,relatime,fd=7,pgrp=11722,timeout=300,minproto=5,maxproto=5,direct)
      pipe = fget(pipefd);  //<<<--- #match_table_t
      sbi->pipe = pipe;
```

## 3.2 Open special character device, used as channel, also transer the fd by mount option

```
    FUSE  fd=open("/dev/fuse", ...);    #Documentation/filesystems/fuse.txt #struct fuse_conn
      fc = kmalloc(sizeof(*fc), GFP_KERNEL);
      file = fget(d.fd);  //<<<--- #match_table_t
      file->private_data = fuse_conn_get(fc);
```

## 3.3 SUN_RPC rpc-cache  #Documentation/filesystems/nfs/rpc-cache.txt
*    /proc/net/rpc/auth.rpcsec.context/channel
*    /proc/net/rpc/auth.rpcsec.init/channel
*    /proc/net/rpc/auth.unix.gid/channel
*    /proc/net/rpc/auth.unix.ip/channel
*    /proc/net/rpc/nfs4.idtoname/channel
*    /proc/net/rpc/nfs4.nametoid/channel
*    /proc/net/rpc/nfsd.export/channel
*    /proc/net/rpc/nfsd.fh/channel

## 3.4 AF_NETLINK  Documentation/connector/connector.txt

## 3.x any more ???
*  file map  
*  ntop 
