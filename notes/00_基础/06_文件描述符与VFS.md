# 06 文件描述符与 VFS

## 1 一句话

**文件描述符是一个下标，不是指针。** 内核不肯把自己的数据结构地址交给用户态，
就在每个进程里放一张数组，把地址填进去，只把数组下标给你。
`open` 返回的那个 `3`，就是这张数组的第 3 格。

## 2 和你已知的东西对照

如果你在 ysyx 里写过 nanos-lite 的 `fs.c`，这套东西你其实已经写过一遍了：

```c
    /* nanos-lite 的形状 */
    typedef struct {
      char *name;
      size_t size;
      size_t disk_offset;
      size_t open_offset;      /* 读到哪了 */
    } Finfo;

    static Finfo file_table[] = { ... };

    int fs_open(const char *pathname, int flags, int mode);   /* 返回下标 */
    size_t fs_read(int fd, void *buf, size_t len);            /* 拿下标查表 */
```

`fd` 是 `file_table` 的下标，`open_offset` 记着读到哪了。Linux 的形状一样，
只是把一张表拆成了三张。**先记住哪一处不一样：`open_offset` 在 nanos-lite 里
和文件信息放在同一个结构体里，Linux 把它挪出去了。** 第 3 节讲为什么必须挪。

另一处对照：你在 NPC 里做过特权级，知道 M 态能看见全部物理地址、U 态不能。
`fd` 就是这条边界的产物 —— 内核那边有一个 `struct file`，
但它的地址不能交给用户态，交出去等于把内核内存的写权限送出去了。
所以给一个下标：**下标是无害的，越界了内核自己查得出来，
而指针一旦交出去就没法验证了。**

## 3 三张表

`fd = open("1.txt", O_RDONLY)` 之后，内核里长这样：

```text
   进程 A 的 task_struct
        |
        +-- files_struct                  第 1 张: fd 表, 每个进程一份
              fd[0] --> ...
              fd[1] --> ...
              fd[2] --> ...
              fd[3] ------------+
                                |
                                v
                        struct file        第 2 张: 打开文件表, 每 open 一次一个
                          f_pos   = 0        <-- 读写位置在这一层
                          f_flags = O_RDONLY <-- O_APPEND 之类的标志也在这一层
                          f_op    -------+   <-- 该调谁的 read/write
                          f_inode ----+  |
                                      |  |
                                      v  v
                              struct inode      第 3 张: 每个文件一个
                                大小、权限、时间戳、数据块在磁盘哪里
```

### 3.1 为什么中间那张表非有不可

假设把 `f_pos` 塞进 `inode`（也就是 nanos-lite 那种两层结构），
那么同一个文件被打开两次，两个 `fd` 会共用一个读写位置：
A 读一个字节，B 接着读就跳过了那个字节。这显然不对 —— 
**"读到哪了"是"这一次打开"的属性，不是"这个文件"的属性。**

所以 `f_pos` 必须待在一个"每 open 一次就新建一个"的结构里，这就是 `struct file`。

反过来，文件大小、权限这些属于文件本身，打开多少次都是同一份，
它们待在 `inode` 里。

### 3.2 dup 复制的是哪一层

三张表决定了三种"复制"的语义完全不同：

```text
    open 两次        fd 表加两格, 各指向一个新的 struct file, 两个 f_pos 独立
                       fd[3] --> file(pos=0)  --+
                       fd[4] --> file(pos=0)  --+--> 同一个 inode

    dup / dup2       fd 表加一格, 指向同一个 struct file, f_pos 共享
                       fd[3] --+
                               +--> file(pos=0) --> inode
                       fd[5] --+

    fork             整张 fd 表复制给子进程, 但指向的还是父进程那些 struct file
                       父 fd[3] --+
                                  +--> file(pos=0) --> inode
                       子 fd[3] --+
```

`dup2(fd, 2)` 就是"把 2 号那一格改成指向 `fd` 指的那个 `struct file`"。
它先把 2 号原来指的那个关掉，再填新的。所有对 `stderr` 的写从此都落到新地方，
而写的人（`fprintf(stderr, ...)`）一个字都不用改 —— **它只认 2 这个数字。**

`close(fd)` 关掉的是 fd 表里的那一格，不是 `struct file`。
`struct file` 上有引用计数，减到 0 才真的关。所以 `dup2` 之后 `close(fd)` 是安全的。

### 3.3 O_APPEND 在哪一层生效

`O_APPEND` 是 `struct file` 的 `f_flags` 里的一位。带着它的 `write` 在内核里是：

```text
    拿到 inode 的锁
      f_pos = inode 当前大小        <-- 这两步在锁里面, 中间插不进别人
      写数据
    放锁
```

自己写 `lseek(fd, 0, SEEK_END)` 再 `write` 是两次系统调用，
两次之间别的进程可以插进来，插进来之后你手里那个"末尾"就过期了。
02 章第 3.2 节把这件事量出来了：两个进程各写 2000 条，
`O_APPEND` 版每次都是 68000 字节一字不差，`lseek` 版每次丢的量都不一样。

## 4 VFS：同一个 read 怎么会有两种下场

`f_op` 那个指针是整套机制的枢纽。它指向一张函数指针表：

```c
    struct file_operations {
        ssize_t (*read)  (struct file *, char __user *, size_t, loff_t *);
        ssize_t (*write) (struct file *, const char __user *, size_t, loff_t *);
        int     (*mmap)  (struct file *, struct vm_area_struct *);
        long    (*unlocked_ioctl)(struct file *, unsigned int, unsigned long);
        ...
    };
```

`open` 的时候，内核看这个路径是什么东西，往 `f_op` 里填不同的表：

```text
                        用户态: read(fd, buf, n)
                                   |
                                   v  svc/ecall
                        内核: sys_read -> f_op->read()
                                   |
              +--------------------+--------------------+
              |                                         |
     路径是普通文件                              路径是 /dev 下的设备节点
     f_op = ext4_file_operations                f_op = 驱动自己注册的那张表
              |                                         |
     文件系统算出数据在第几个块                 驱动直接读寄存器 / DMA
              |                                         |
     块设备驱动                                        硬件
```

**这就是"一切皆文件"的实现方式。** 它不是一句口号，
是 `f_op` 这一个函数指针的替换。第 2 阶段写驱动，你要做的核心工作
就是填一张 `file_operations` 出来。

也是为什么第 03 章操作 framebuffer 用的是 `open("/dev/fb0")` 而不是 `fopen`：
`/dev/fb0` 的 `f_op` 是显示驱动的表，标准 IO 那一层缓冲夹在中间只会碍事。

## 5 亲手验证

内核把这三张表的内容直接开在 `/proc` 里，不用 gdb 也能看。

写一个程序：把同一个文件 `open` 两次得到 `fd1`、`fd2`，再 `dup(fd1)` 得到 `fd3`，
只从 `fd1` 读一个字节，然后 `pause()` 挂住不退出。另开一个终端：

```bash
ls -l /proc/<pid>/fd            # 看第 1 张表: 哪个编号指向哪个文件
cat /proc/<pid>/fdinfo/3        # 看第 2 张表: 这个 fd 背后 struct file 的 pos 和 flags
```

- `/proc/<pid>/fd` 下每一项是一个符号链接，链接名是 fd 编号，目标是打开的文件。
- `/proc/<pid>/fdinfo/<n>` 是文本，`pos` 就是 `f_pos`，`flags` 是 `f_flags` 的八进制。

**本机实测**（Ubuntu 26.04 on WSL2，内核 6.6.114.1）：

```text
    lr-x------ ... 3 -> /home/glorinz/fio-lab/data.txt
    lr-x------ ... 4 -> /home/glorinz/fio-lab/data.txt
    lr-x------ ... 5 -> /home/glorinz/fio-lab/data.txt

    fd 3:  pos: 1   flags: 0100000
    fd 4:  pos: 0   flags: 0100000
    fd 5:  pos: 1   flags: 0100000
```

三个编号指向同一个文件，但 `pos` 是 **1 / 0 / 1**：
只读了 `fd1` 一个字节，`fd3` 的位置跟着动了，`fd2` 没动。
**第 2 张表的存在被内核自己报出来了。**

## 6 被哪些章节用到

| 章节 | 用到什么 |
|---|---|
| [02 文件 IO](../01_应用编程/02_文件IO.md) 第 2 节 | 三张表、dup2、O_APPEND 原子性 |
| [02 文件 IO](../01_应用编程/02_文件IO.md) 第 6 节 | `project/` 用 dup2 把日志接到文件 |
| 03 Framebuffer | 为什么 `/dev/fb0` 要用系统调用 IO 而不是标准 IO |
| 第 2 阶段驱动开发 | 写驱动就是填一张 `file_operations` |

相关：[05 系统调用与用户内核态](05_系统调用与用户内核态.md) 讲 `read` 怎么进内核，
本篇讲进去之后查的是哪张表。
