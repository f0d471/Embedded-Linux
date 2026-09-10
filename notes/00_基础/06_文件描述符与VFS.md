# 06 文件描述符与 VFS

**前置：[05 系统调用与用户内核态](05_系统调用与用户内核态.md)。**
那一篇讲 `read` 怎么进内核，本篇讲进去之后内核查的是哪张表。
没读也能读本篇，只要接受一件事：`open`/`read`/`write` 是**系统调用**，
执行它们的时候 CPU 会切到内核，由内核代你干活。

被 02 章 2、3、6 节用到。

实验目录：`labs/00_basics/02_fd_and_vfs/`
所有输出是 2026-09-08 本机实跑，Ubuntu 26.04 on WSL2，内核 6.6.114.1，gcc 15.2.0。
判据自查：`bash labs/00_basics/02_fd_and_vfs/check.sh`

---

## 没看懂也先记住

三张表暂时画不出来也没关系。先记“编号是入口，读写位置属于一次打开”，
再用下面几条判断谁和谁共享状态。

### 先带走这 5 条

1. **fd（文件描述符）是进程使用的非负整数编号，不是内存指针。** `open` 成功返回当前最小的空闲编号，失败返回 `-1`；`0`、`1`、`2` 也都可以是合法 fd。
2. **同一路径分别 `open` 两次，通常有各自独立的读写位置。** `dup` 得到的新 fd 和旧 fd 则指向同一份“打开文件描述”（内核记录的一次打开状态），共享读写位置和 `O_APPEND` 等文件状态标志。
3. **`dup2(oldfd, newfd)` 让 `newfd` 指向 `oldfd` 对应的那次打开。** 记参数方向：旧入口在前，要改的编号在后；`dup2(logfd, 2)` 把标准错误接到日志目标。
4. **普通 `fork` 后，父子各有 fd 表，但继承的 fd 指向同一批打开文件描述。** 所以它们可以共享读写位置；一方关掉自己的 fd，不会直接关掉另一方的 fd。
5. **VFS 是内核给不同文件系统和设备提供的统一文件接口层。** 同样的 `read`/`write`，背后可能是普通文件、管道或设备的不同实现，不能假定每个 fd 都支持 `lseek`、`mmap` 等全部操作。

### 看到什么，就先想到什么

| 看到的东西 | 第一反应 |
|---|---|
| 判断 `open` 成败 | 检查 `fd < 0`；不能用 `fd <= 0` 或 `!fd`，因为 0 也可能成功 |
| 两个 fd 的读写位置一起变化 | 先查是否来自 `dup`/`dup2` 或 `fork` 继承，别只看文件名是否相同 |
| 关闭复制后的 fd，另一个仍能写 | 关的是自己的入口；还有引用时，那次打开仍然存在 |
| 多个写入者需要往普通文件末尾追加 | 优先用 `O_APPEND`，不要拆成 `lseek` 到末尾再 `write`；它保护单次写入的末尾定位，不把多次 `write` 组成的整条业务记录变成原子操作 |
| `lseek` 报不支持 | 先确认是不是管道等不能定位的对象，不能只按普通磁盘文件理解 |

`O_APPEND` 的追加保证还依赖文件系统，NFS 等场景有额外限制；要写完整数据仍需检查 `write` 返回的实际字节数。
边界见 Linux 手册 [open(2)](https://man7.org/linux/man-pages/man2/open.2.html)。

### 反复看这 3 组问答

- **问：分别 `open` 同一个文件，会自动共享读写位置吗？答：不会；`dup` 或继承同一次打开才是这里的共享来源。**
- **问：把 stderr 接到日志，`dup2` 怎么写？答：`dup2(logfd, 2)`，并检查返回值。**
- **问：`fork` 后父子 fd 编号一样，意味着 fd 表是同一张吗？答：不是，表各有一份，但表项指向的打开状态可以共享。**

想补原理时：fd 和共享关系看第一至三节，重定向看第四节，`fork` 看第五节，追加和 VFS 看第六、七节。

---

## 一、从一个你天天见但没细想的返回值开始

```c
int fd = open("data.txt", O_RDONLY);
```

`fd` 拿到的是个 `3`。为什么是 3？为什么不是一个指针？

**先把问题问准：**内核那边显然要为这次打开记一堆东西 ——
文件在磁盘哪、读到第几个字节了、以只读还是读写方式打开的。
这些必然存在某个内核数据结构里。

那为什么不直接把那个结构的地址返回给你，让你 `read(ptr, ...)`？
这样内核还省一次查表。

**因为交出去就收不回了。** 用户态拿到一个内核地址，就可以：

    随便改它（写坏内核数据结构，整个系统崩）
    伪造一个（传个假地址进来，让内核去访问不该访问的内存）
    偷看它旁边的内存（内核里挨着放的可能是别的进程的数据）

内核没有任何办法验证"你传进来的这个指针是不是我给你的那个"。

**换成下标就全解决了：**

    fd = 3 传进来，内核检查 0 <= 3 < 表的长度，越界就返回 EBADF
    表是内核自己的，用户改不了
    每个进程一张表，你的 3 和我的 3 互不相干

> **文件描述符（file descriptor，fd）**：进程内一张数组的下标。
> 数组的每一格指向内核里描述"一次打开"的结构。
> `open` 返回下标，`read`/`write`/`close` 拿下标回来查。

这不是什么特殊设计，是**内核向用户态交出资源的通用做法** ——
凡是"内核里有个东西、用户要反复引用它"的场合，给的都是个号码而不是地址。

### 1.1 那为什么第一个 fd 是 3，不是 0

因为 0、1、2 已经被占了。

    fd 0   标准输入   stdin
    fd 1   标准输出   stdout
    fd 2   标准错误   stderr

**这三个不是 C 语言规定的，是习惯**：shell 在启动你的程序之前，
已经把这三格填好了（通常都指向终端）。你的程序一上来就有三格是满的，
所以 `open` 只能从 3 开始发。

`printf` 往 1 号写、`fprintf(stderr,...)` 往 2 号写 —— 就这么简单。
第四节会利用这一点做件很有用的事。

---

## 二、实验 1：证明 fd 是下标，且中间还有一层

### 2.1 先自己想

要证明"fd 只是下标、真正的状态在别处"，最直接的办法是：
**让两个不同的 fd 指向同一个文件，然后动其中一个，看另一个跟不跟着动。**

有两种造法，结果应该不一样：

    open 同一个文件两次        -> 两次打开，各自记各自的进度？
    dup(fd) 复制一个 fd        -> 复制的是下标还是背后的东西？

怎么看"进度"？`/proc` 里内核把每个 fd 的内部状态直接开出来了：

    /proc/<pid>/fd/<n>       这一格指向哪个文件（是个符号链接）
    /proc/<pid>/fdinfo/<n>   这一格背后的状态：pos（读到哪了）、flags（打开方式）

    提示：<pid> 写成 self 就是"当前进程自己"，
          所以程序可以读 /proc/self/fdinfo/3 看自己的状态，不用另开终端。

**上一版笔记让你另开一个终端 `cat /proc/<pid>/fdinfo`，还要先 `pause()` 挂住进程 ——
那样很难做下去。改成程序自己读自己。**

### 2.2 动手：完整代码

`labs/00_basics/02_fd_and_vfs/fdshow.c`：

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>

/* 把 /proc/self/fdinfo/<fd> 里的 pos 和 flags 打出来 */
static void show(int fd, const char *tag)
{
	char path[64], line[128];
	FILE *f;

	snprintf(path, sizeof path, "/proc/self/fdinfo/%d", fd);
	f = fopen(path, "r");
	if (!f) { printf("  fd %d (%s): 打不开 %s\n", fd, tag, path); return; }

	printf("  fd %-2d (%-10s)", fd, tag);
	while (fgets(line, sizeof line, f)) {
		line[strcspn(line, "\n")] = 0;          /* 去掉行尾换行 */
		if (!strncmp(line, "pos:", 4) || !strncmp(line, "flags:", 6))
			printf("  %s", line);
	}
	printf("\n");
	fclose(f);
}

int main(void)
{
	int fd1, fd2, fd3;
	char c;

	fd1 = open("data.txt", O_RDONLY);
	fd2 = open("data.txt", O_RDONLY);   /* 同一个文件，第二次 open */
	fd3 = dup(fd1);                     /* 复制 fd1 这一格 */

	printf("open 返回的编号: fd1=%d fd2=%d fd3=%d\n\n", fd1, fd2, fd3);

	printf("[读之前] 三个 fd 的位置：\n");
	show(fd1, "open 1"); show(fd2, "open 2"); show(fd3, "dup fd1");

	read(fd1, &c, 1);                   /* 只从 fd1 读一个字节 */
	printf("\n从 fd1 读了 1 个字节（读到 '%c'）\n\n", c);

	printf("[读之后] 三个 fd 的位置：\n");
	show(fd1, "open 1"); show(fd2, "open 2"); show(fd3, "dup fd1");

	return 0;
}
```

编译运行：

    cd labs/00_basics/02_fd_and_vfs
    printf 'abcdefghij' > data.txt      # 造一个 10 字节的文件
    gcc fdshow.c -o fdshow
    ./fdshow

### 2.3 本机实测

```
open 返回的编号: fd1=3 fd2=4 fd3=5

[读之前] 三个 fd 的位置：
  fd 3  (open 1    )  pos:	0  flags:	0100000
  fd 4  (open 2    )  pos:	0  flags:	0100000
  fd 5  (dup fd1   )  pos:	0  flags:	0100000

从 fd1 读了 1 个字节（读到 'a'）

[读之后] 三个 fd 的位置：
  fd 3  (open 1    )  pos:	1  flags:	0100000
  fd 4  (open 2    )  pos:	0  flags:	0100000
  fd 5  (dup fd1   )  pos:	1  flags:	0100000
```

### 2.4 逐条读，三个结论

**结论 1：编号是 3、4、5，连着发的。** 印证 1.1 节 —— 0/1/2 被占了，
而且内核发号的规则是"给最小的空闲格"。

**结论 2（关键）：读之后 pos 是 `1 / 0 / 1`。**

    fd3（第一次 open）  pos 0 -> 1     我读的就是它，动了
    fd4（第二次 open）  pos 0 -> 0     没动
    fd5（dup 来的）     pos 0 -> 1     我没碰它，但它跟着动了

**fd5 跟着动，说明 fd5 和 fd3 背后是同一个东西。**
而 fd4 不动，说明它背后是另一个东西。

三个 fd 指向同一个文件，却分成了两组。**"位置"这个状态既不在 fd 里
（否则 dup 出来的 fd5 该独立），也不在文件里（否则 fd4 该跟着动）。
它在中间某一层。**

**结论 3：flags 都是 `0100000`。** 这是八进制，转成十六进制是 `0x8000`，
正是 `O_LARGEFILE`。`O_RDONLY` 的值恰好是 0，所以看不见它。
这一列后面第六节还会用到。

### 2.5 判据

    [ ] fd1/fd2/fd3 是 3/4/5 三个连号
    [ ] 读之前三个 pos 全是 0
    [ ] 读之后 pos 分别是 1 / 0 / 1
    [ ] 能说出哪两个 fd 是一组，依据是什么

    注错见红：把 fd3 = dup(fd1) 改成 fd3 = open("data.txt", O_RDONLY)。
    本机实测这时 pos 变成 1 / 0 / 0 —— dup 那一组消失了。
    如果改完还是 1/0/1，说明你跑的是旧的可执行文件。

---

## 三、三张表：把上面的现象画出来

第二节测出"中间还有一层"。现在把完整结构摆出来。
**内核用三层结构来管这件事**，第二节的现象是这个结构的直接后果。

```
   进程 A 的 task_struct（内核里描述一个进程的结构）
        |
        +-- files_struct                第 1 张表：fd 表，每个进程一份
              fd[0] --> ...             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
              fd[1] --> ...             这张表的下标就是 fd。
              fd[2] --> ...             每一格是个指针，指向第 2 张表的一项
              fd[3] ------------+
              fd[4] ---------+  |
              fd[5] ---------|--+       <-- 注意 fd[3] 和 fd[5] 指向同一处
                             |  |
                             |  v
                             | struct file      第 2 张：打开文件表
                             |   f_pos   = 1      <-- "读到哪了"在这一层
                             |   f_flags = ...    <-- O_APPEND 之类也在这一层
                             |   f_op   ------+   <-- 该调谁的 read/write（第七节）
                             |   f_inode --+  |
                             v             |  |
                            struct file    |  |
                              f_pos   = 0  |  |    每 open 一次，新建一个
                              f_inode --+  |  |
                                        |  |  |
                                        v  v  v
                                    struct inode        第 3 张：每个文件一个
                                      文件大小、权限、时间戳、
                                      数据块在磁盘的哪些位置
```

**第二节的三个 pos 值，现在能一眼解释：**

    fd[3] 和 fd[5] 指向同一个 struct file  -> 共享 f_pos -> 一起变成 1
    fd[4] 指向另一个 struct file           -> 独立 f_pos -> 还是 0
    但两个 struct file 的 f_inode 指向同一个 inode -> 确实是同一个文件

### 3.1 为什么中间那张表非有不可

假设去掉中间层，把 `f_pos` 直接塞进 `inode`（也就是"每个文件一个位置"）：

    进程 A 打开 1.txt 读了 100 字节，位置 = 100
    进程 B 也打开 1.txt，想从头读 —— 但位置已经是 100 了

两个毫不相干的程序会互相干扰。显然不对。

**根本原因是一句话：**

    "读到哪了"是**这一次打开**的属性，不是**这个文件**的属性。

一个属性该放在哪张表，就看它是"每次打开都不同"还是"文件本身就一份"：

    每次打开都不同 -> struct file   f_pos、打开方式（只读还是读写）、O_APPEND
    文件本身一份   -> inode         大小、权限、修改时间、数据在磁盘哪里

### 3.2 三种"复制"，复制的是不同层

三张表结构决定了三种操作的语义完全不同。这是本篇最实用的一张表：

```
    open 两次      fd 表加两格，各指向一个新的 struct file
                     fd[3] --> file(pos 独立) --+
                     fd[4] --> file(pos 独立) --+--> 同一个 inode
                   两个位置互不影响              （第二节的 fd4）

    dup / dup2     fd 表加一格，指向同一个 struct file
                     fd[3] --+
                             +--> file(pos 共享) --> inode
                     fd[5] --+
                   位置共享                        （第二节的 fd5）

    fork           整张 fd 表复制给子进程，
                   但指向的还是父进程原来那些 struct file
                     父 fd[3] --+
                                +--> file(pos 共享) --> inode
                     子 fd[3] --+
                   跨进程共享位置                   （第五节验证）
```

第五节会把 fork 那条也测出来。

---

## 四、实验 2：不改日志语句，让输出从终端改写到文件

### 4.1 先自己想

现在有个实际问题：程序里到处是 `fprintf(stderr, ...)`，
还有别人写的库也往 stderr 写。**现在想把所有这些输出落到一个文件里，
但不许改任何一行 `fprintf`。** 怎么办？

`stderr` 叫“标准错误输出”。程序刚启动时，它通常通向终端，所以
`fprintf(stderr, ...)` 的文字会显示在屏幕上。Linux 同时给它分配了编号 2，
`STDERR_FILENO` 就是这个编号的常量名。

想让所有现有日志进入文件，只需要统一改变 `stderr` 的去向。写日志的代码仍然写
`stderr`，不会知道后面接的是终端还是文件。

    提示：完成这件事的函数叫 dup2(来源, 要改变的目标)。
          来源是已经打开的日志文件，目标是 stderr。
          写成 dup2(fd, STDERR_FILENO)。

### 4.2 动手

`logredir.c`：

```c
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>

static void worker(void)          /* 假装这是别人写的库，只认 stderr */
{
	fprintf(stderr, "worker: 干活中\n");
}

int main(void)
{
	int fd;

	fprintf(stderr, "1. 重定向之前，这行去终端\n");
	worker();

	fd = open("log.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	printf("2. 日志文件拿到的 fd = %d\n", fd);

	dup2(fd, STDERR_FILENO);      /* 让 stderr 以后写进 log.txt */
	close(fd);                    /* fd 已经多余；关掉它不影响 stderr */

	fprintf(stderr, "3. 重定向之后，这行去文件\n");
	worker();                     /* 同一个函数，一个字没改 */

	return 0;
}
```

    gcc logredir.c -o logredir
    ./logredir
    cat log.txt

### 4.3 本机实测

```
$ ./logredir
1. 重定向之前，这行去终端
worker: 干活中
2. 日志文件拿到的 fd = 3

$ cat log.txt
3. 重定向之后，这行去文件
worker: 干活中
```

### 4.4 逐条读

**现象：`worker()` 被调了两次，代码一模一样，第一次去终端、第二次进文件。**

    dup2 之前   fprintf(stderr, ...) -> stderr -> 终端
    dup2 之后   fprintf(stderr, ...) -> stderr -> log.txt

`fprintf(stderr, ...)` 全程只把文字交给 `stderr`。
**它不知道 `stderr` 后面接的目标已经换了。**

**再看那句 `close(fd)`，它是本实验最容易被误解的一行。**

`dup2` 成功后，`fd` 和 `stderr` 都可以通往同一个日志文件。
后续日志只走 `stderr`，`fd` 已经没有用途，所以可以关闭这个多余入口。

    close(fd) 之前：fd 和 stderr 都能通往 log.txt
    close(fd) 之后：只剩 stderr 通往 log.txt，日志仍能继续写

这也是为什么 `dup2` 之后紧跟 `close(fd)`：不保留没有用途的文件编号。
想知道 Linux 内部为什么允许两条入口同时存在，再回看第三节的三张表。

### 4.5 这就是 shell 重定向的实现

你敲的 `./prog > out.txt 2>&1`，shell 干的正是这件事：

    fork 出子进程
    在子进程里 open("out.txt")，让标准输出改写到这个文件
    2>&1 表示让标准错误也使用标准输出当前的去向
    然后 execve 你的程序

数字 1 代表标准输出，数字 2 代表标准错误。`2>&1` 不是“把文字 2 写进文件”，
而是让标准错误跟随标准输出的去向。两路最终通过同一次文件打开结果写入，
因此共用当前写到的位置；如果各自独立打开同一文件，位置可能互相干扰。

`project/` 里的 `log_redirect()` 用的就是这一招，见
[02 章文件 IO](../01_应用编程/02_文件IO.md) 第 6 节。

### 4.6 判据

    [ ] 前两行出现在终端，后两行出现在 log.txt 里
    [ ] worker() 的代码一个字没改，但两次输出去了不同地方
    [ ] open 拿到的 fd 是 3
    [ ] close(fd) 之后，往 stderr 写仍然有效

    注错见红：把 dup2(fd, STDERR_FILENO) 改成 dup2(fd, STDOUT_FILENO)。
    这时改变的是 stdout（标准输出）的去向，本机实测结果反过来：
    "2. 日志文件拿到的 fd = 3" 这行 printf **进了文件**，
    而两行 stderr 全部留在终端。
    改错目标，输出就去错地方 —— 这条直接证明两种标准输出各有自己的去向。

---

## 五、实验 3：fork 之后，父子共享的是哪一层

### 5.1 先自己想

3.2 节说 `fork` 复制整张 fd 表，但指向的还是同一批 `struct file`。
如果这是真的，那么：

**父进程写一段、子进程写一段，两段不会互相覆盖** —— 因为它们共享 `f_pos`，
子进程写完位置前进了，父进程接着往后写。

反过来，如果 fork 给子进程建了新的 `struct file`（各自独立的 `f_pos`），
子进程会从父进程 fork 那一刻的位置重新开始写，**盖掉一部分内容**。

这两种结果在文件内容上完全不同，一眼能分辨。

### 5.2 动手

`forkfd.c`：

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>

int main(void)
{
	int fd = open("shared.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	pid_t pid;

	write(fd, "AAAAA", 5);        /* fork 前先写 5 字节，f_pos = 5 */

	pid = fork();
	if (pid == 0) {
		write(fd, "child", 5);    /* 子进程写 */
		exit(0);
	}
	wait(NULL);                   /* 等子进程写完，避免两边同时写 */
	write(fd, "PAREN", 5);        /* 父进程再写 */
	close(fd);

	printf("文件内容: ");
	fflush(stdout);
	execlp("cat", "cat", "shared.txt", NULL);
	return 0;
}
```

    gcc forkfd.c -o forkfd
    ./forkfd

### 5.3 本机实测

```
文件内容: AAAAAchildPAREN
```

### 5.4 逐条读

15 个字节，三段完整，谁也没盖谁：

    AAAAA        fork 之前写的，位置到 5
    child        子进程写的，从 5 开始，位置到 10
    PAREN        父进程写的，从 10 开始 —— 父进程知道子进程写过了

**父进程从来没执行过任何"把位置挪到 10"的代码。**
它能从 10 开始写，只可能是因为它和子进程用的是同一个 `f_pos`。

**不共享会是什么样？**下一小节的注错见红把它测出来了：让子进程自己
`open` 一次（拿到一个独立的 `struct file`，`f_pos` 从 0 开始），
本机实测结果是 `childPAREN`，10 字节 ——
子进程从 0 写，把 `AAAAA` 盖掉了；父进程的位置仍是 5，接着写 `PAREN`。

    共享 f_pos（fork 继承）    AAAAAchildPAREN   15 字节，谁也没盖谁
    不共享（各自 open）        childPAREN        10 字节，开头被盖掉

结果是 15 字节的那个。3.2 节那张图的第三行验证完毕。

**这条在实际工程里的意义**：父子进程往同一个日志文件写，
只要是 fork 前打开的 fd，就不会互相覆盖。
但如果是 fork 后各自 `open`（两个独立 `struct file`），就会打架 ——
那时要靠第六节的 `O_APPEND`。

### 5.5 判据

    [ ] 文件内容是 AAAAAchildPAREN，共 15 字节
    [ ] 能说清三段各自从哪个位置开始写的（0 / 5 / 10）

    注错见红：让子进程自己 open 一次，不用继承来的那个 fd：

        if (fork() == 0) {
            int f2 = open("shared.txt", O_WRONLY);   /* 不要带 O_TRUNC */
            write(f2, "child", 5);
            exit(0);
        }

    本机实测内容变成 childPAREN，10 字节。
    子进程那个新 struct file 的 f_pos 从 0 开始，把 AAAAA 盖掉了；
    父进程的 f_pos 仍是 5，所以 PAREN 还是落在第 5 字节处。
    **少了 5 个字节，而且没有任何报错。**

---

## 六、实验 4：O_APPEND 的原子性在哪一层生效

### 6.1 先自己想

两个进程同时往一个日志文件追加，怎么保证不互相覆盖？

**朴素做法**：先跳到末尾，再写。

```c
lseek(fd, 0, SEEK_END);      /* 第 1 次系统调用：找末尾 */
write(fd, line, n);          /* 第 2 次系统调用：写 */
```

**看出问题了吗？** 这是两次独立的系统调用。两次之间，内核可能把 CPU 交给别人。
如果另一个进程在这个缝隙里也写了一条，**你手里那个"末尾"就过期了**，
你会写到别人刚写的位置上，把它盖掉。

`O_APPEND` 的做法是把这两步合成一步，在内核里、拿着锁做完：

```
    拿到 inode 的锁
      f_pos = 文件当前大小       <-- 这两步在锁里面，中间插不进别人
      写数据
    放锁
```

**关键：`O_APPEND` 是 `struct file` 的 `f_flags` 里的一位**（第 2 张表），
所以它是"这一次打开"的属性 —— 同一个文件，你用 `O_APPEND` 打开，
我不用，互不影响。

这个差别能量出来吗？能，而且非常明显。

### 6.2 动手

`append.c`（两种模式用命令行参数切换）：

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <sys/wait.h>

#define N     2000                    /* 每个进程写多少条 */
#define LINE  "0123456789abcdef\n"    /* 每条 17 字节 */

static void writer(int use_append)
{
	int fd, i;
	int flags = O_WRONLY | (use_append ? O_APPEND : 0);

	fd = open("out.txt", flags);
	for (i = 0; i < N; i++) {
		if (!use_append)
			lseek(fd, 0, SEEK_END);        /* 自己找末尾：第 1 次系统调用 */
		write(fd, LINE, strlen(LINE));     /* 写：第 2 次 */
	}
	close(fd);
}

int main(int argc, char **argv)
{
	int use_append = (argc > 1 && !strcmp(argv[1], "append"));
	int fd;

	fd = open("out.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	close(fd);

	if (fork() == 0) { writer(use_append); exit(0); }   /* 子进程写 2000 条 */
	writer(use_append);                                  /* 父进程写 2000 条 */
	wait(NULL);

	printf("%-8s 模式：期望 %d 字节，实际 %ld 字节\n",
	       use_append ? "append" : "lseek",
	       2 * N * (int)strlen(LINE),
	       (long)lseek(open("out.txt", O_RDONLY), 0, SEEK_END));
	return 0;
}
```

    gcc append.c -o append
    for i in 1 2 3; do ./append append; done
    for i in 1 2 3; do ./append lseek;  done

**为什么要各跑三轮？** 因为这是竞态，单次结果可能碰巧正确。
竞态问题的判据必须是多轮的。

### 6.3 本机实测

```
append   模式：期望 68000 字节，实际 68000 字节
append   模式：期望 68000 字节，实际 68000 字节
append   模式：期望 68000 字节，实际 68000 字节
lseek    模式：期望 68000 字节，实际 34255 字节
lseek    模式：期望 68000 字节，实际 34204 字节
lseek    模式：期望 68000 字节，实际 34340 字节
```

### 6.4 逐条读

**`O_APPEND` 版：三轮全部精确 68000 字节，一字节不差。**
（2 个进程 x 2000 条 x 17 字节 = 68000）

**`lseek` 版：34255 / 34204 / 34340 —— 三轮三个数，而且都只有一半左右。**

丢了将近一半，因为两个进程有一多半时间在互相覆盖。
**更要命的是每轮的数字都不一样**：这是竞态的典型特征，
它意味着这种 bug **不能靠"我跑了一遍没问题"来排除**。

**注意这个错误的形态：**没有任何一次 `write` 返回失败，
没有任何报错，程序退出码是 0。数据就是悄无声息地少了一半。
**并发写文件不用 O_APPEND，就是这种"全绿但结果错"的 bug。**

### 6.5 判据

    [ ] append 模式连跑三轮，三次都精确等于 68000
    [ ] lseek 模式连跑三轮，三次结果互不相同，且都明显小于 68000
    [ ] 能说出 lseek 版丢数据的那个"缝隙"具体在哪两行代码之间

    注错见红：把 N 改成 5（每个进程只写 5 条）。
    这时 lseek 版很可能也是满的 —— 竞态窗口太小，撞不上。
    **这条本身就是教训：并发 bug 的判据必须把压力加到足够大，
    否则判据会假绿。** 改完记得改回 2000。

---

## 七、VFS：同一个 read，四种下场

前六节讲的是"fd 怎么找到那个文件"。这一节讲进去之后的分岔。

### 7.1 先自己想

Linux 号称"一切皆文件"：`/dev/null`、终端、磁盘文件，全都用
`open`/`read`/`write` 操作。

但它们的行为显然不可能一样 —— 写进 `/dev/null` 的数据会消失，
写进磁盘文件的会留下。**同一个 `write` 系统调用，怎么会有不同的下场？**

回头看第三节那张图，`struct file` 里有个字段还没讲：

    f_op   ------+   <-- 该调谁的 read/write

> **`f_op`（file_operations）**：一张函数指针表。
> 里面是 `read`、`write`、`mmap`、`ioctl` 等一组函数指针。
> **`open` 的时候，内核看你打开的是什么东西，往 `f_op` 里填不同的表。**

```c
struct file_operations {
	ssize_t (*read)  (struct file *, char __user *, size_t, loff_t *);
	ssize_t (*write) (struct file *, const char __user *, size_t, loff_t *);
	int     (*mmap)  (struct file *, struct vm_area_struct *);
	long    (*unlocked_ioctl)(struct file *, unsigned int, unsigned long);
	...
};
```

`sys_read` 的核心只有一句：`f_op->read(...)`。**分岔就在这一个指针上。**

```
                     用户态: read(fd, buf, n)
                                |
                                v  系统调用（见 05 篇）
                     内核: sys_read -> file->f_op->read()
                                |
        +-----------------------+------------------------+
        |                       |                        |
   普通文件               /dev/null              终端 /dev/tty
   f_op = ext4 的表       f_op = null 驱动的表   f_op = tty 驱动的表
        |                       |                        |
   算数据在第几个块        直接返回 0（永远 EOF）    等键盘输入
        |                       |                        |
   块设备驱动 -> 磁盘       什么都不做              串口/终端硬件
```

**这就是"一切皆文件"的实现方式。它不是口号，是一个函数指针的替换。**

怎么验证？**写一段代码，只换路径，其余一个字不改。**

### 7.2 动手

`vfs.c`（完整代码在实验目录，这里是核心部分）：

```c
static void try_path(const char *path)
{
	char buf[8];
	int fd, n;
	struct stat st;
	struct winsize ws;

	fd = open(path, O_RDWR);
	if (fd < 0) { printf("  open 失败: %s\n\n", strerror(errno)); return; }

	fstat(fd, &st);                       /* 先问问这是什么类型 */
	...

	n = write(fd, "hello", 5);            /* 完全相同的 write */
	printf("  write 5 字节 -> 返回 %d\n", n);

	if (isatty(fd)) {                     /* 终端的 read 会一直等键盘，跳过 */
		printf("  read      -> 跳过\n");
	} else {
		lseek(fd, 0, SEEK_SET);
		memset(buf, '.', sizeof buf);
		n = read(fd, buf, 5);             /* 完全相同的 read */
		printf("  read  5 字节 -> 返回 %d, 内容 \"%.5s\"\n", n, buf);
	}

	/* 问一个只有终端才懂的问题：你的窗口多大 */
	if (ioctl(fd, TIOCGWINSZ, &ws) == 0)
		printf("  ioctl(TIOCGWINSZ) -> 成功，%d 行 %d 列\n", ws.ws_row, ws.ws_col);
	else
		printf("  ioctl(TIOCGWINSZ) -> 失败: %s\n", strerror(errno));

	close(fd);
}

int main(void)
{
	try_path("data.txt");
	try_path("/dev/null");
	try_path("/dev/zero");
	try_path("/dev/tty");
	return 0;
}
```

    gcc vfs.c -o vfs
    ./vfs

### 7.3 本机实测

```
--- data.txt ---
  类型      : 普通文件
  write 5 字节 -> 返回 5
  read  5 字节 -> 返回 5, 内容 "hello"
  ioctl(TIOCGWINSZ) -> 失败: Inappropriate ioctl for device

--- /dev/null ---
  类型      : 字符设备
  write 5 字节 -> 返回 5
  read  5 字节 -> 返回 0, 内容 "....."
  ioctl(TIOCGWINSZ) -> 失败: Inappropriate ioctl for device

--- /dev/zero ---
  类型      : 字符设备
  write 5 字节 -> 返回 5
  read  5 字节 -> 返回 5, 内容 ""
  ioctl(TIOCGWINSZ) -> 失败: Inappropriate ioctl for device

--- /dev/tty ---
  类型      : 字符设备
  write 5 字节 -> 返回 5
  read      -> 跳过（终端会一直等你敲键盘）
  ioctl(TIOCGWINSZ) -> 成功，30 行 120 列
```

### 7.4 逐条读，四种下场

**同一段 `write(fd,"hello",5)`，四次都返回 5（都"成功"了），但发生的事完全不同：**

    data.txt    数据落到磁盘，随后 read 把 "hello" 读了回来
    /dev/null   返回 5，但数据被丢弃。随后 read 返回 0（永远是 EOF）
    /dev/zero   返回 5，数据也被丢弃
    /dev/tty    "hello" 直接显示在你的终端上

**再看 read 的三种结果，一个比一个说明问题：**

    data.txt    返回 5，内容 "hello"      -> 真的存了，真的读回来了
    /dev/null   返回 0，内容还是 "....."  -> 返回 0 表示 EOF，
                                            buf 一个字节都没被改
    /dev/zero   返回 5，内容显示为空       -> 读到了 5 个 '\0'。
                                            不是"没读到"，是读到了 5 个 0 字节，
                                            printf 遇到第一个 '\0' 就停了

**`/dev/zero` 那个空字符串最容易误读。** 它返回 5 说明确实读了 5 个字节，
只是内容全是 `\0`。要看清楚就得打十六进制而不是 `%s`。
**这也是个通用教训：用 `%s` 打二进制数据会骗你。**

**最后看 ioctl 那一行，这是最干净的证据：**

    data.txt    失败: Inappropriate ioctl for device
    /dev/null   失败: Inappropriate ioctl for device
    /dev/zero   失败: Inappropriate ioctl for device
    /dev/tty    成功，30 行 120 列

`TIOCGWINSZ` 是"告诉我窗口有几行几列"。这个问题只有终端驱动能回答。
**同一个 `ioctl` 调用，三个路径报"我不懂这个命令"，一个给出了答案。**

报错文字 `Inappropriate ioctl for device`（errno 是 `ENOTTY`）
字面意思就是"这个设备不适用这个 ioctl" —— 也就是
**那张 `f_op` 表里没有能处理它的函数**。

### 7.5 这条对第 2 阶段驱动开发意味着什么

**写一个字符设备驱动，核心工作就是填一张 `file_operations` 出来：**

```c
static const struct file_operations my_fops = {
	.owner   = THIS_MODULE,
	.open    = my_open,
	.read    = my_read,           /* 用户 read 我的设备时，调这里 */
	.write   = my_write,
	.unlocked_ioctl = my_ioctl,
};
```

填完注册进内核，用户态就能用 `open("/dev/mydev")` + `read` 操作你的硬件了。
**第七节这四个路径的行为差异，全部来自这张表里填的是不同的函数。**

也是为什么 03 章操作 framebuffer 用 `open("/dev/fb0")` 而不是 `fopen`：
`/dev/fb0` 的 `f_op` 是显示驱动的表，标准 IO 那层缓冲夹在中间只会碍事
（见 02 章第 4 节）。

### 7.6 判据

    [ ] 四个路径的 write 全部返回 5
    [ ] data.txt 的 read 返回 5 且内容是 "hello"
    [ ] /dev/null 的 read 返回 0，且 buf 保持原样（还是那些点）
    [ ] /dev/zero 的 read 返回 5，但内容全是 '\0'
    [ ] 只有 /dev/tty 的 ioctl(TIOCGWINSZ) 成功，另外三个报 ENOTTY
    [ ] 能说出这四种差异来自 struct file 的哪一个字段

    注错见红：把 /dev/tty 那行改成 /dev/null 跑两遍。
    本机实测两行输出完全相同，ioctl 都失败 ——
    路径变了行为就变，路径一样行为就一样。**行为跟着路径走，不跟着代码走。**

---

## 八、顺带一提：和 nanos-lite 的对照

**没写过 nanos-lite 也不影响，跳过即可，本篇不依赖它。**

如果你在 ysyx 里写过 `fs.c`，那套东西和本篇是同一件事的简化版：

```c
    /* nanos-lite 的形状 */
    typedef struct {
      char *name;
      size_t size;
      size_t disk_offset;
      size_t open_offset;      /* 读到哪了 */
    } Finfo;

    static Finfo file_table[];
    int fs_open(const char *pathname, int flags, int mode);   /* 返回下标 */
```

`fd` 是 `file_table` 的下标 —— 和本篇第一节完全一致。

**但有一处关键差异，正是第三节讲的那件事：**
`open_offset` 在 nanos-lite 里和文件信息放在同一个结构体里（两层结构），
Linux 把它单独拆到了 `struct file`（三层结构）。

    nanos-lite   fd 表 -> Finfo（位置和文件信息在一起）
    Linux        fd 表 -> struct file（位置） -> inode（文件信息）

nanos-lite 能这么简化，是因为它是单进程玩具系统，
不会出现"同一个文件被打开两次"。真跑起来多进程就不行了 ——
这正是 3.1 节论证的内容。

另一处对照：你在 NPC 里做过特权级，知道 M 态能看见全部物理地址、U 态不能。
第一节讲的"为什么不返回指针"就是这条边界的直接后果。

---

## 九、被谁用到

| 章节 | 用到什么 |
|---|---|
| [02 文件 IO](../01_应用编程/02_文件IO.md) 第 2 节 | 三张表、dup2、O_APPEND 原子性 |
| [02 文件 IO](../01_应用编程/02_文件IO.md) 第 6 节 | `project/` 用 dup2 把日志接到文件 |
| 03 Framebuffer | 为什么 `/dev/fb0` 要用系统调用 IO 而不是标准 IO |
| 第 2 阶段驱动开发 | 写驱动就是填一张 `file_operations`（7.5 节） |

相关：
[05 系统调用与用户内核态](05_系统调用与用户内核态.md) 讲 `read` 怎么进内核，
本篇讲进去之后查的是哪张表；
[07 虚拟内存与 mmap](07_虚拟内存与mmap.md) 讲 `f_op->mmap` 那一格。
