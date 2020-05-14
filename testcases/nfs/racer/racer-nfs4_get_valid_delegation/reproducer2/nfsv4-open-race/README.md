# What is this

- Reproducer of a system crash due to a race condition on NFSv4 file opening.

# How to use

1. Set DEV, MNT, KPROBE_OFFSET in run.sh

  - DEV
    - NFS, such as: DEV=192.168.122.1:/nfs

  - MNT
    - mount point, such as: MNT=/mnt/nfs

  - KPROBE_OFFSET
    - offset from top of nfs4_get_open_state to call to ihold.
    - You may be able to get the offset by crash or gdb or objdump command.
       like as:
                   
        ```
        crash> mod -s nfsv4
        crash> dis nfs4_get_open_state
        ...
        0xffffffffc04f2756 <nfs4_get_open_state+294>:   mov    %rcx,-0x60(%r12)
        0xffffffffc04f275b <nfs4_get_open_state+299>:   mov    %rcx,0x8(%r13)
        0xffffffffc04f275f <nfs4_get_open_state+303>:   mov    %r12,%rdi
        0xffffffffc04f2762 <nfs4_get_open_state+306>:   callq  0xffffffff8132b250 <ihold>
                   
        ```
        For avobe, set KPROBE_OFFSET to 306

2. Run run.sh
  ```
  # ./run.sh
  ```

# Detail of the issue
```
A NULL pointer deference happens when a file on NFSv4 is opened concurrently.
The panic log is as follows:

   BUG: unable to handle page fault for address: ffffffffffffffb0
   ...
   RIP: 0010:nfs4_get_valid_delegation+0x6/0x30 [nfsv4]
   ...
   Call Trace:
    nfs4_open_prepare+0x80/0x1c0 [nfsv4]
    __rpc_execute+0x75/0x390 [sunrpc]
    ? finish_task_switch+0x75/0x260
    rpc_async_schedule+0x29/0x40 [sunrpc]
    process_one_work+0x1ad/0x370
    worker_thread+0x30/0x390
    ? create_worker+0x1a0/0x1a0
    kthread+0x10c/0x130
    ? kthread_park+0x80/0x80
    ret_from_fork+0x22/0x30

The NULL poiner deference happens because:
Task A opens a file and calls list_add_rcu() at nfs4_get_open_state(), then
the task A is stopped because of an interruption. state->inode is NULL here.
Next, Task B opens the same file and goes to nfs4_get_open_state().
__nfs4_find_state_byowner() returns the state because Task A registered
the state to open_states list.
Then, a kworker thread begins to work to handle the open request of Task B.
The kworker refers state->inode at nfs4_get_valid_delegation() but the inode
is still NULL because Task A is stopped.

The diagram is something like as:

   Task A              | Task B               | kworker
   ====================+======================+=========================
   nfs4_get_open_state |                      |
                       |                      |
   list_add_rcu(&state->inode_states,);       |
                       | nfs4_get_open_state  |
                       | state = __nfs4_find_state_byowner 
   (in interrupt...)   |                      |
                       |                      | nfs4_open_prepare
                       |                      | nfs4_get_valid_delegation
                       |                      | NFS_I(inode)->delegation
                       |                      | ^^ PANIC! inode is NULL
   state->inode = inode;                      |
                       |                      |
```
