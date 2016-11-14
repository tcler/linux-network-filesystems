# NFS procedures - NFS 协议包类型

NFS 基于网络过程，因此NFS 中本地与远端的所有交互都可以通过观察NFS 包中的数据和交互模式找到问题，无论是权限还是性能问题，最基础的部分是RFC 中定义的NFS 特有的RPC 过程，这些过程是理解export-mount 交互模式和各个选项的基础。

NFS 于OSI 分层模型中的位置：

OSI Model | OSI 模型 | NFS Architecture | NFS 结构 |
----------|------|--------------|----------|----------|
Application | 应用层 | NFS built-in procedures | NFS 内建过程
Presentation | 表现层  | XDR - Extended Data Representation | （通用）扩展数据表示
Session | 会话层  | RPC - Remote Procedure Calls | 远程过程调用
Transport | 传输层  | TCP(v4,v3) or UDP(v3) | NFSv4 指定TCP，NFSv3 可使用TCP 或UDP
Network | 网络层  | Not Specified | 不指定
Data Link | 数据链路层  | Not Specified | 不指定
Physical | 物理层  | Not Specified | 不指定
* Mount 为NFSv3 的配套协议，NFSv4 改为内置
    * BPF - NFS: rpc.program == 100003
    * BPF - Mount: rpc.program == 100005

## XDR - Extended Data Representation - 扩展数据表示

XDR 同于描述传输的数据，在网络包出现于RPC 以及NFS 层中，是数据成功传输的关键标志，XDR 具有和C 语言相似的基本数据结构，在数据传输中这些基本结构很少涉及，一般的以黑盒的方式传输数据块：

| XDR 数据格式 | BPF | 描述 |
|------|------|------|
|opaque|rpc.fill_bytes == 00:00:00|opaque data 是在NFS write 中最常见的格式，代表NFS 不解析内容，整体传输

## NFSv3 procedures - NFSv3 过程

| 编号 | procedure | short Description | 描述
|------|------|------|------|
| 0 | null | Do Nothing | 空白过程，用于测试是否可连接
| 1 | getattr | Get a File Attribute | 本地获取远端一个共享文件的属性
| 2 | setattr | Set a File Attribute | 本地设定（改变）远端一个共享文件的属性
| 3 | lookup | Look Up Filename | 获取File Handle(FH) 用于描述将操作的远端文件
| 4 | access | Check Access Permission | 检查现有会话下对某FH 对应的文件具有何种权限
| 5 | readlink | Read from　Symbolic Link | 读取一个符号链接的文件名
| 6 | read | Read | 从远端读
| 7 | write | Write | 向远端写
| 8 | create | Create a File | 在远端创建文件
| 9 | mkdir | Make a Dir | 在远端创建路径
|10 | symlink | Create a Symbolic Link | 在远端创建符号链接
|11 | mknod | Create a Special File | 用于创建特殊文件（如命名管道）
|12 | remove | Remove a File | 从远端删除文件
|13 | rmdir | Remove a Dir | 从远端删除目录
|14 | rename | Rename a File | 在远端重命名一个文件
|15 | link | Create a Hard Link | 在远端创建一个硬链接
|16 | readdir | Read from a Dir | 从远端目录中读取内容
|17 | readdirplus | Read More from a Dir | 从远端目录中读取额外内容
|18 | fsstat | Get Dynamic File System Information | 返回现有会话所在远端文件系统的剩余空间等动态数据
|19 | fsinfo | Get Statis File System Information | 返回现有回话所在远端文件系统的静态数据，例如该文件系统下支持的最大的文件体积
|20 | pathconf | Retrieve POSIX Information | 进一步获取目的路径的POSIX 信息，这是对上两者的补充
|21 | commit | Commit Cached Data | 强制要求远端将所有缓存数据向下级存储写入

### Mount procedures - Mount 过程

Mount 作为NFSv3 的配套协议用于进行挂载过程

| 编号 | procedure | short Description | 描述
|------|------|------|------|
| 0 | null | Do Nothing | 空白过程，用于测试是否可连接
| 1 | mnt | Add Mount Entry | 挂载，将一个远端路映射为File Handle 以供使用
| 2 | dump | Return Mount Entries | 返回一个远端的挂载表
| 3 | umnt | Remove Mount Entry | 反向挂载，将一个已激活的FH 反注册
| 4 | umntall | Remove All Mount Entry | 反向挂载全部会话，将该会话内的全部FH 反注册
| 5 | export | Return Export List | 返回远端的挂载广播列表并包含挂载权限

## NFSv4 procedures - NFSv4 过程

| 编号 | procedure | short Description | 描述
|------|------|------|------|
|0  | null | Do Nothing | 空白过程，用于测试是否可连接 |
|1  | compound | Compound | NFSv4 采用复合过程，将几个相关过程绑定在一起向远端发送 |
|3  | access | Check Access Rights | 检查现有会话下对某FH 对应的文件具有何种权限 |
|4  | close | Close a File | 关闭一个文件 |
|5  | commit | Commit Cached　Date | 强制要求远端将所有缓存数据向下级存储写入 |
|6  | create | Create a Nonregular File Object | 用于创建特殊文件（如命名管道），常规文件依靠open 创建 |
|7  | delepurge | Purge Delegations　Awaiting Recovery | 远端可以使请求端对某些文件暂时提权（委派），该过程要求清除这种委派 |
|8  | delegreturn | Return Delegation | 返回委派结果（远端同意委派） |
|9  | getattr | Get Attributes | 获取该文件对象的属性 |
|10 | getfh | Get a File Handle | 获取一个用于操作的File Handle |
|11 | link | Create Hard Link to a File | 向文件创建硬链接 |
|12 | lock | Create a Lock on a File | 向文件加锁，保证文件的一致性，例如避免多端同时修改一个文件造成的不一致性 |
|13 | lockt | Test a Lock on a File| 测试锁的存在性，返回锁的性质 |
|14 | locku | Unlock a File | 解锁一个文件 |
|15 | lookup | Lookup a File | 查询一个文件对象的存在性 |
|16 | lookupp | Lookup the Parent Dir of a File | 查询一个文件对象的上级目录的FH |
|17 | nverify | Verify Difference in Attributes | 校对本地缓存的文件性质是否与远端相同（确定是否有改动） |
|18 | open | Open a File | 打开一个文件，如果请求目标不存在则创建 |
|19 | openattr | Open the Attributes Related to a File | 打开文件的相应属性（如果存在记录的话） |
|20 | open_confirm | Confirm open | 确定一个打开状态文件的性质 |
|21 | open_downgrade | Reduce Open File Access | 降低一个已经打开文件的访问权限 |
|22 | putfh | Set Current File Handle | 将现有的File Handle 替代为新的确定值 |
|23 | putpubfh | Set Public File Handle | 设定公共File Handle |
|24 | putrootfh | Set Root File Handle | 设定现有的File Handle 为远端该会话的根目录 |
|25 | read | Read from a File | 从远端文件中读取 |
|26 | readdir | Read Dir | 读取路径内的内容 |
|27 | readlink | Read s Symbolic Link | 读取一个符号链接 |
|28 | remove | Remove a File System Object | 删除一个远端的文件对象 |
|29 | renmae | Rename a File | 重命名一个文件 |
|30 | renew | Renew a Delegation | 更新一个委派（续约） |
|31 | restorefh | Restore a Saved File Handle | 恢复一个保存的File Handle 继续使用 |
|32 | savefh | Save Current File Handle | 保存现有的File Handle 以供未来使用 |
|33 | secinfo | Security Info | 现会话的安全属性 |
|34 | setattr | Set Attribute | 设定（改变）文件属性 |
|35 | setclientid | Negotiate Client ID | 本地向远端服务器请求使用特殊的Client ID 用于进行某些操作的提权（和安全相关） |
|36 | setclientid_confirm | Confirm a Client ID | 服务器肯定并给予Client ID 使得客户端可以特定的提权 |
|37 | verify | Verify Same Attributes | 本地向远端确认特定属性 |
|38 | write | Write to a File | 向远端文件中写入 |
|39 | release_lockowner | Release Lock Owner State | 用于本地向远端请求清除特定锁 |

## Reference

- [https://tools.ietf.org/html/rfc5661](NFS: Network File System Protocol Specification)
- [https://tools.ietf.org/html/rfc1813](NFS Version 3 Protocol Specification)
- [https://tools.ietf.org/html/rfc3530](Network File System version 4 Protocol)
