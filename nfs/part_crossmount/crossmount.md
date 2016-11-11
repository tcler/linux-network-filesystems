# PART crossmount

This section includes export or mount options below:

| Option             | Obiect        | Default State in NFSv3 | Default State in NFSv4|
|:------------------ |:------------- |:---------------------- |:----------------------|
| nohide             | /etc/exports  | FALSE                  | N/A                   |
| crossmnt           | /etc/exports  | FALSE                  | FALSE                 |
| no\_subtree\_check | /etc/exports  | TRUE                   | TRUE                  |

# OPTION nohide and crossmnt

These two options are similar. An easy experiment may show what does `crossmnt` option controls: 

On server, export its root dir, notice that the `/boot` dir is mounted by `/dev/sda1`:

```
[root@hp-dl360g9-07 /]# mount |grep /boot
/dev/sda1 on /boot type xfs (rw,relatime,seclabel,attr2,inode64,logbsize=256k,sunit=512,swidth=1536,noquota)
[root@hp-dl360g9-07 boot]# cat  /etc/exports
/ 10.73.4.141(rw,no_root_squash)
[root@hp-dl360g9-07 /]# exportfs -arv 
exportfs: No options for / 10.73.4.141: suggest 10.73.4.141(sync) to avoid warning
exporting 10.73.4.141:/
```

On Client:

```
[root@hp-dl360g9-14 mnt]# mount -v $BRO:/ ./nfs_in/
mount.nfs: timeout set for Fri Nov 11 12:32:13 2016
mount.nfs: trying text-based options 'vers=4,addr=10.73.4.163,clientaddr=10.73.4.141'
[root@hp-dl360g9-14 mnt]# ls ./nfs_in/
bin  boot  dev  etc  home  lib  lib64  media  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
[root@hp-dl360g9-14 mnt]# ls -a ./nfs_in/boot/
.  ..
```

It obvious that the `/boot` dir is hide from the Server. When create a file inside `/mnt/nfs_in/boot` from client, this file will not appear in the Server. When `umount` happens, the created file is missed, but with the next `mount`, this file will appear again. 

With the `crossmnt` set, the `/boot` on Server behaves like mounted on the Client:

On server, export its `/` dir again:

```
[root@hp-dl360g9-07 /]# exportfs -arv 
exporting 10.73.4.141:/
[root@hp-dl360g9-07 /]# cat  /etc/exports
/ 10.73.4.141(crossmnt,rw,no_root_squash)
```

On Client:

```
[root@hp-dl360g9-14 mnt]# mount -o vers=3 $BRO:/ ./nfs_in/
[root@hp-dl360g9-14 mnt]# cd ./nfs_in/boot/
[root@hp-dl360g9-14 boot]# ls
config-3.10.0-489.el7.x86_64                             initrd-plymouth.img
grub2                                                    symvers-3.10.0-489.el7.x86_64.gz
initramfs-0-rescue-e13cd4e2400846a1a2b37ef42e6faa2e.img  System.map-3.10.0-489.el7.x86_64
initramfs-3.10.0-489.el7.x86_64.img                      vmlinuz-0-rescue-e13cd4e2400846a1a2b37ef42e6faa2e
initramfs-3.10.0-489.el7.x86_64kdump.img                 vmlinuz-3.10.0-489.el7.x86_64
[root@hp-dl360g9-14 boot]# pwd
/mnt/nfs_in/boot
```

The effection of which is just as described in `man exports`:

```
crossmnt
              This  option  is  similar  to  nohide  but  it  makes it possible for clients to access all filesystems mounted on a filesystem marked with crossmnt.
```

With the descriptions in `man exports`, the `nohide` and `hide` are used to do similar things as `crossmnt`, but with experiments designed by the description, the results are not as expection, due to it is not usable in NFSv4, more testings towards this option is set as TBD:

```
nohide        
              This option is based on the option of the same name provided in IRIX NFS.  Normally, if a server exports two filesystems one of which is mounted on the other, then the client will have to mount both filesystems  explic‐
              itly to get access to them.  If it just mounts the parent, it will see an empty directory at the place where the other filesystem is mounted.  That filesystem is "hidden".
              The option can be explicitly disabled for NFSv2 and NFSv3 with hide.
              This option is not relevant when NFSv4 is use.  NFSv4 never hides subordinate filesystems.  Any filesystem that is exported will be visible where expected when using NFSv4.

```

# OPTION no\_subtree\_check

`subtree_check` and `no_subtree_check` describes whether every file request by the Client is checked to make sure that the requested file is in an exported subdirectory. That is related to the effection of `crossmnt` and `hide`.

With the descriptions in `man exports`, currently the default value is `no_subtree_check`:

```
no_subtree_check

              From release 1.1.0 of nfs-utils onwards, the default will be no_subtree_check as subtree_checking tends to cause more problems than it is worth.
```