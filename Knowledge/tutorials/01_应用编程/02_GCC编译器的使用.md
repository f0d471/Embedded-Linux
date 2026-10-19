# 02 GCC 编译器的使用

    原书    第四篇 第 2 章，PDF 143-153 页（145 页往后是选项清单，已提取为
            fundamentals/04_GCC的选项.md，本章正文只讲原理）
    视频    4_2-1（17 分）、4_2-2（23 分）——知识已全部融入本篇，不必再看
    源码    $Q\04_嵌入式Linux应用开发基础知识\source\02_options\
    实验    Knowledge/labs/02_gcc/（本篇所有"本机实测"均为 2026-10-16 在
            WSL Ubuntu 26.04 / gcc 15.2.0 真跑）

---

**前置基础**：看懂本篇需要下面的底子。开读前扫一眼，缺哪条先补哪条；
标了"用到再读"的可以等正文引用时再翻。

- 前一章 [01 HelloWorld 背后没那么简单](./01_HelloWorld背后没那么简单.md)：
  §1 的停点实验接着 01 章"中间产物都能要下来"往下走，§4.3 的
  `GLIBC_2.34 not found` 直接回指 01 章 4.4 的板上实测
- 先读 [00 从源码到运行](../../fundamentals/00_从源码到运行.md)：本篇把四个
  步骤各自停在中间看产物（`-E`/`-S`/`-c`），四步叫不出名字读不动 §1
- 用到再读 [05 静态库动态库与符号](../../fundamentals/05_静态库动态库与符号.md)：
  §4.3 讲静态/动态库与 GLIBC 版本关卡时引用
- 用到再读 [07 系统调用与用户内核态](../../fundamentals/07_系统调用与用户内核态.md)：
  §6 讲 `printf` 不是系统调用、`write` 才是时引用
- 清单 [04 GCC 的选项](../../fundamentals/04_GCC的选项.md)：
  选项清单已全部提出来，正文只讲原理，用到去查

**这一章在整机里的位置**：上接 01 篇（一条命令编出三种产物），下接 03 篇（把命令
写进 Makefile）。它补的零件是"把编译拆成四步、知道每步的输入输出与搜索路径"；
后面所有第三方库（libjpeg-turbo、FreeType、sqlite3）的交叉编译都是这四步加参数。

**不学它会怎样**：交叉编第三方库时，头文件找不到、链接报 undefined reference、
运行时 GLIBC not found 三种错误分不清，只能瞎试；`-static` 放到 `-o` 后面
产物会悄悄变回动态版（坑 2），上板才发现起不来。

## 0 这一章解决什么问题

### 0.1 先看结果：19 行，848 行，63 行

同一份 `hello.c`，四个停点各留下一个产物。本机实测（2026-10-16）：

```text
$ wc -l hello.c hello.i hello.s
   19 hello.c
  848 hello.i
   63 hello.s

$ ls -l hello.o hello
 1640 hello.o
15992 hello
```

19 行预处理成 848 行，编译成 63 行汇编，汇编成 1640 字节目标文件，链接成
15992 字节可执行文件。本章就是把这条链拆开：每一步是谁做的、产物里有什么、
以及"头文件找不到 / 符号未定义 / 运行时库找不到"分别卡在哪一步。

### 0.2 这一章为什么存在

一句话：**四个步骤是每一层抽象各自留下的一道翻译。**

Windows 上点一下按钮就能编译，Visual Studio 背后就是这一章的这些命令行；
嵌入式 Linux 没有"点鼠标"，命令行就是编译本身。把 gcc 当黑盒用，遇到
"头文件找不到""符号未定义""运行时库找不到"就只剩搜索报错；知道它在做什么，
每个报错都能立刻定位到某一步的某个动作。

视频 4_2-1 的开头五分钟没有从名词讲起，而是反过来推。程序员的历史：

| 演进阶段 | 解决了什么 | 又留下什么问题 | 对应术语 |
|---|---|---|---|
| 开关和电线 | 直接控制机器 | 操作太累，像电工 | — |
| 纸带机器码 | 把操作记录下来 | 仍要记住每条机器码的每一位 | — |
| 英文助记符 | 用人能读的名字表示机器码 | 汇编指令仍太多、太琐碎 | 助记符 → 机器码叫"**汇编**" |
| C / C++ | 用更高层的表达描述程序 | 需要翻译成汇编 | 高级语言 → 汇编叫"**编译**" |
| 多文件组装 | 把各文件的机器码合成一个程序 | 要处理跨文件的地址和符号 | 多个 `.o` → 一个 app 叫"**链接**" |
| 预先处理源码 | 展开 `#include`、替换 `#define` | 交给后续编译 | `.c + .h` → `.i` 叫"**预处理**" |

四个步骤和它们的工具、输入输出：

| 步骤 | 工具 | 输入 → 输出 | 关键变化 |
|---|---|---|---|
| 预处理 | `cpp`（实际由 cc1 代做） | `hello.c` → `hello.i` | 展开 `#include`、替换 `#define`、按 `#if` 裁剪；结果仍是 C |
| 编译 | `cc1` | `hello.i` → `hello.s` | C 变为汇编助记符 |
| 汇编 | `as` | `hello.s` → `hello.o` | 变为机器码；地址未定，外部符号仍为空 |
| 链接 | `ld`（由 collect2 调用） | 多个 `.o` + 库 + 启动代码 → `hello` | 生成完整可执行文件 |

反方向也有名字：机器码变回汇编叫**反汇编**，调试时常用（本章 2.6 就用）。

**"编译"这个词在中文里有三个范围**，视频 4_2-1 的 16:17 专门提了：

    窄义   .i -> .s 那一步（真正"编"的部分）
    中义   预处理 + 编译 + 汇编（gcc -c 干的事,产物 .o）
    宽义   四步全部（gcc 一条命令干的事）

读文档看上下文。本教程需要精确区分时写全称。

### 0.3 怎么读这一章

    只想先看见结果   0.1 → 1.1（四个停点）→ 1.2（gcc 内部三个程序）
    完整学一遍       1 → 2 → 3 → 4；5、6 是代价实验，7 是查选项清单
    选读，第二轮再看 2.2（一条命令编两个文件的代价）、4.2（execve 到 main）、
                     5（-static 的代价）、6（绕过 libc）、7（选项清单去哪查）

---

## 1 [做 L1] 亲手拆开四步，并看见 gcc 内部的三个程序

### 1.1 停在中间的四个停点

gcc 一条命令编完，但每个中间产物都能要下来。三个选项各对应一个停点：

```bash
cd /mnt/e/Workspace/Embedded-linux/Knowledge/labs/01_hello

gcc -E hello.c -o hello.i    # 只预处理。-E 后产物仍是 C 文本
gcc -S hello.i -o hello.s    # 只编译到汇编。产物是汇编助记符
gcc -c hello.s -o hello.o    # 只汇编。产物是机器码(目标文件)
gcc    hello.o -o hello      # 不加编译选项就是链接
```

- `-E`：预处理后即停，结果默认送往标准输出，`-o` 存成文件。
- `-S`：编译后即停，不汇编。
- `-c`：汇编后即停，不链接，`.o` 就是这一步的产物。
- 都不指定时，gcc 会**按输入文件的后缀决定做到哪一步**：给 `.c` 走全程，
  给 `.s` 只汇编，给 `.o` 只链接。这就是"gcc 非常聪明"的含义。

产物规模本机实测（2026-10-16）：

```text
$ wc -l hello.c hello.i hello.s
   19 hello.c
  848 hello.i
   63 hello.s

$ ls -l hello.o hello
 1640 hello.o
15992 hello
```

**19 行变 848 行再变 63 行**，这三个数把预处理在干什么讲清楚了：它把
`stdio.h` 的全部内容原样贴进来，而头文件里绝大部分是声明和类型定义，
不产生任何机器码，所以编译出来的 `.s` 又变短了。

`hello.i` 里值得看两处：

```bash
head -20 hello.i
# 开头是一堆 # 1 "xxx.h" 的行标记:告诉编译器"下面这些行来自哪个文件的第几行",
# 你在报错里看到的文件名和行号就是从这来的
grep -n 'int main' hello.i
# main 被挤到了最后面,前面全是展开进来的声明
```

### 1.2 gcc 的内部是三个程序

```bash
gcc -v -o hello_x86 hello.c 2>&1 | grep -E 'cc1|/as |collect2'
#   ^^ 把内部调用的每一条命令都原样打出来(信息走 stderr,要 2>&1)
```

本机实测，从满屏输出里挑出调用了谁（路径已缩短）：

```text
x86 :  /usr/libexec/gcc/x86_64-linux-gnu/15/cc1        (hello.c -> /tmp/ccXXXX.s)
       as --64 -o /tmp/ccXXXX.o /tmp/ccXXXX.s
       /usr/libexec/gcc/x86_64-linux-gnu/15/collect2 ... (最后链接)
ARM :  /usr/libexec/gcc-cross/arm-linux-gnueabihf/15/cc1
       /usr/lib/gcc-cross/arm-linux-gnueabihf/15/.../arm-linux-gnueabihf/bin/as
       /usr/libexec/gcc-cross/arm-linux-gnueabihf/15/collect2
```

**四个逻辑步骤，三个实际程序：`cc1` 一个程序干了预处理和编译两件事。**
gcc 是个前端，它按需调 cc1 / as / collect2。

collect2 那一长串命令还泄露了一个秘密，链接时被塞进去的不止你的 `.o`：

```text
collect2 ... -o hello_x86 .../Scrt1.o .../crti.o .../crtbeginS.o
             /tmp/ccXXXX.o -lgcc ... -lc .../crtendS.o .../crtn.o
```

`Scrt1.o / crti.o / crtbeginS.o / crtendS.o / crtn.o` 是 C 运行时的**启动文件**
（你没写，链接器自己加的，负责在 main 之前铺好运行环境）；`-lc` 就是 libc。
原书 2.7 节的 `-nostartfiles` / `-nostdlib` 选项就是把这些"自动塞入"关掉——
编 bootloader 和内核时才用，详见 04 篇。

### 1.3 语法错误在哪一步被发现

预处理只做文本替换，它需要理解 C 语法吗？不用猜，验：

```bash
cp hello.c hello_bad.c
echo 'this is not c' >> hello_bad.c     # 往结尾塞一行不是 C 的东西
gcc -E hello_bad.c -o /dev/null; echo "预处理 exit=$?"
gcc -S hello_bad.c -o /dev/null; echo "编译   exit=$?"
rm hello_bad.c
```

本机实测（2026-10-16）：

```text
预处理 exit=0
编译   exit=1
hello_bad.c:20:1: error: unknown type name 'this'
```

`-E` 一声不吭，`-S` 才报错。**语法错误是编译（cc1）阶段发现的。**
以后看到报错，看它发生在哪个阶段，就知道该回头检查什么。

---

## 2 多个文件：一条命令的方便，与它的代价

### 2.1 一条命令编两个文件

实验代码在 `Knowledge/labs/02_gcc/`。`main.c` 调用 `sub.c` 里定义的函数：

```bash
cd /mnt/e/Workspace/Embedded-linux/Knowledge/labs/02_gcc
gcc -o test main.c sub.c
./test
```

它内部做的是：每个 `.c` 各自走预处理、编译、汇编，在 `/tmp` 下生成临时的
`.o`（用完就删），最后一起链接成 `test`。

### 2.2 为什么必须分开编：一千个文件的问题

把上面那条命令推到极端：一千个 `.c` 一条命令编。改了其中一个，重跑时
**另外 999 个也要从头再处理一遍**。文件少时无所谓，文件一多就是在烧时间。

分开编再链接：

```bash
gcc -c -o main.o main.c        # -c 编译不链接,产物留下来
gcc -c -o sub.o  sub.c
gcc -o test main.o sub.o       # 只链接
```

改了 `main.c` 之后，只需要重跑第一条和第三条，前提是**有东西替你判断
"哪些需要重跑"**。手工判断，文件一多就判断不过来。
这就是 make 存在的理由，第 03 章的全部起点。

---

## 3 四个"去哪找"

视频 4_1-2、4_2-2 反复讲的是同一件事的四个实例，一张表压完：

    找什么                 谁去找       默认去哪找                怎么加自己的
    ---------------------  -----------  ------------------------  ------------------
    头文件 <stdio.h>       预处理器     工具链的 include 目录      -I<目录>
    头文件 "myhead.h"      预处理器     先当前目录,再同上          -I<目录>
    库文件 libsub.so       链接器       工具链的 lib 目录          -L<目录> 加 -l<名>
    动态库(运行时再找)     ld.so        /lib、/usr/lib 等          LD_LIBRARY_PATH

`-l` 的名字规则：`-lsub` 找的是 `libsub.so` 或者 `libsub.a`，
前面的 `lib` 和后面的后缀都省略。

三个最常见报错，各对应表里一行：

    fatal error: xxx.h: No such file or directory       头文件没找到   -> 加 -I
    undefined reference to `xxx'                         符号没找到     -> 补 .o 或 -l
    error while loading shared libraries: libxxx.so      运行时没找到   -> LD_LIBRARY_PATH

### 3.1 [做 L2] 现场做一个静态库和一个动态库

两个文件（在 `Knowledge/labs/02_gcc/`，`main.c` 里用的是**声明**而不是
include——编译 main.c 时编译器只需要知道 `sub_func` 长什么样，
"在哪"是链接器的事，这正是 01 章 1.3 的分工）：

```bash
cd /mnt/e/Workspace/Embedded-linux/Knowledge/labs/02_gcc

# 先各自编成 .o
gcc -c -o main.o main.c
gcc -c -o sub.o  sub.c

# 静态库:本质就是一堆 .o 打包成一个文件
ar rcs libsub.a sub.o
#  ^^^ archive。r 插入或替换,c 不存在就创建且不警告,s 建符号索引
gcc -o test_static main.o libsub.a

# 动态库:要位置无关代码
gcc -shared -fPIC -o libsub.so sub.c
#   ^^^^^^^ 产物是共享库不是可执行文件
#           ^^^^ position independent code,
#                动态库被加载到什么地址运行时才知道,所以代码本身要能"搬家"
gcc -o test_shared main.o -L. -lsub
#                          ^^ 去当前目录找库
#                              ^^^^ 找 libsub.so 或 libsub.a
```

本机实测（2026-10-16）：

```text
 1352  main.o
 1480  sub.o
 1626  libsub.a          静态库 = sub.o 加一点索引开销
15536  libsub.so         动态库大得多,它自带一套完整 ELF 结构

16016  test_static       (libsub 静态,libc 仍然动态)
15944  test_shared       两个只差 72 字节
```

**这个例子里静态和动态几乎一样大**——`sub.c` 只有一行代码，复制进去也没多少。
视频 4_2-2 的 13:58 处也说了同一件事："小了若干个字节而已，这很正常"。
体积差异要在库大的时候才显现，第 5 节把整个 libc 静态链进来，差的就是 7 倍。

**跑一下，第三种报错来了：**

```text
$ ./test_static
sub
$ ./test_shared
./test_shared: error while loading shared libraries: libsub.so:
cannot open shared object file: No such file or directory
$ echo $?
127
$ LD_LIBRARY_PATH=. ./test_shared
sub
```

链接时你用 `-L.` 告诉了**链接器**库在哪，但那个信息**没有写进可执行文件**。
运行时是另一个程序（`ld.so`）按另一套规则找，当前目录不在它的列表里，
所以要 `LD_LIBRARY_PATH` 现场补。这就是表格最后一行那句话的全部内容：
**链接时找得到，不代表运行时找得到。**

再看"符号没找到"长什么样（故意不链 sub）：

```text
$ gcc -o t main.c
/usr/bin/x86_64-linux-gnu-ld.bfd: /tmp/ccXXXX.o: in function `main':
main.c:(.text+0x9): undefined reference to `sub_func'
collect2: error: ld returned 1 exit status
```

注意报错的是 **ld 不是 cc1**：编译 main.c 完全没问题（它只需要那句声明），
是链接这一步找不到实现。

**[判] 3.1 节的判据**

    [ ] ar -t libsub.a 能列出里面有 sub.o
    [ ] nm test_static | grep sub_func 是 T(有实现)
        nm test_shared | grep sub_func 是 U(未定义,运行时才填)
    [ ] ./test_shared 直接跑失败(exit 127),加 LD_LIBRARY_PATH=. 后成功
    [ ] readelf -d test_shared | grep NEEDED 能看到 libsub.so
    [ ] 说得出三个报错各属于"去哪找"表里哪一行

    注错见红:把 libsub.so 删掉,./test_static 照样能跑,./test_shared 跑不了。
    这一条最直观地说明"静态库在链接时被抄进了程序,动态库运行时才去借"。

---

## 4 printf 到底是谁在干活

`gcc -o hello hello.c` 编出来的 hello 里，**没有 printf 的代码**。
（符号、PLT/GOT 的机制，[fundamentals/05](../../fundamentals/05_静态库动态库与符号.md)
有完整的反汇编实测。）

### 4.1 [做 L1] 把 printf 的去向查出来

```bash
cd /mnt/e/Workspace/Embedded-linux/Knowledge/labs/01_hello

arm-linux-gnueabihf-nm hello_arm_dynamic | grep -i printf
#  ^^ 列符号表:地址、类型字母、符号名。U = undefined(这个文件里没有它)

readelf -p .interp hello_arm_dynamic
#       ^^ 把某个 section 的内容当字符串打出来

readelf -d hello_arm_dynamic | grep NEEDED
#       ^^ 读 .dynamic 段:动态链接的全部信息都在这
```

本机实测（2026-10-16）：

```text
$ arm-linux-gnueabihf-nm hello_arm_dynamic | grep -i printf
         U printf@GLIBC_2.4          <-- U:文件里没有 printf,运行时去 libc 借

$ readelf -p .interp hello_arm_dynamic
String dump of section '.interp':
  [     0]  /lib/ld-linux-armhf.so.3

$ readelf -d hello_arm_dynamic | grep NEEDED
  0x00000001 (NEEDED)    Shared library: [libc.so.6]
```

### 4.2 从 execve 到 main，中间还插了一个程序

`.interp` 段里那个路径不是注释，是内核真的会去读、去加载的文件：

| 顺序 | 执行者 | 动作 |
|---|---|---|
| 1 | 内核 `load_elf_binary()` | 发现 `PT_INTERP`，读出 `/lib/ld-linux-armhf.so.3`，把 ld.so 映射进地址空间 |
| 2 | 内核 | 跳到 ld.so 的入口 |
| 3 | 用户态 ld.so | 读 hello 的 `.dynamic`，发现 `NEEDED libc.so.6`，把 libc 映射进来 |
| 4 | 用户态 ld.so | 重定位：把 GOT 里的 `printf` 表项填成 libc 中的真实地址 |
| 5 | 用户态 ld.so | 跳到 hello 的入口 |
| 6 | 用户态 hello | `_start → __libc_start_main → main()` |

**动态链接器先于你的 main 运行。** 01 章注错实验里"骗过 arch 检查之后
卡在找 ld.so"卡的就是这个位置。

### 4.3 这对嵌入式意味着一条硬约束

你交叉编译时链接的 libc，必须和板子 rootfs 里那份 libc 兼容：

| 位置 | 库 | 结果 |
|---|---|---|
| Ubuntu 开发机 | apt 工具链配的新版 glibc（本机 libc.so.6 实测 1188008 字节） | 生成的 hello 记录 `printf@GLIBC_2.4` 等版本要求 |
| 板子 rootfs | Buildroot glibc 2.30（板上 `/lib/libc-2.30.so`） | 满足不了 `GLIBC_2.34`，启动即失败 |

01 章 4.4 已经在板上得到过原样报错：`GLIBC_2.34 not found`，退出码 1。
这是 sysroot 不匹配的问题。两个解法：

    A（本阶段用这个）  加 -static,把 libc 静态链进去,不依赖板上的库
    B（第 2 阶段换）   板子 BSP 的 arm-buildroot-linux-gnueabihf-gcc,
                       它配的就是板上那份 glibc

---

## 5 [做 L2] -static 的代价

```bash
cd /mnt/e/Workspace/Embedded-linux/Knowledge/labs/01_hello
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra hello.c -o hello_arm_static
#                       ^^^^^^^ 注意位置:放在 -o 前面,
#                       放到 -o 后面会被当成输出文件名(常见错误)
ls -l hello_arm_dynamic hello_arm_static
readelf -p .interp hello_arm_static
readelf -h hello_arm_static | grep Type:
```

本机实测（2026-10-16）：

| 项目 | 动态 `hello_arm_dynamic` | 静态 `hello_arm_static` |
|---|---|---|
| 体积 | 69,284 字节 | 487,028 字节（**7.03 倍**） |
| ELF 类型 | `ET_DYN`（PIE） | `ET_EXEC` |
| `.interp` | `/lib/ld-linux-armhf.so.3` | **没有**（readelf: Section '.interp' was not dumped because it does not exist） |
| `.dynamic` | `NEEDED libc.so.6` | 没有运行时库依赖 |
| 上板 | 依赖板上 libc，版本不符报 `GLIBC_x.xx not found` | 自包含，拷过去就能跑 |

**量级要记住：一个 hello world，为了自带 libc，从 6.9 万字节涨到 48.7 万，
7.0 倍。** 板子上放几十个这样的程序 rootfs 就撑爆了。这就是嵌入式宁可折腾
sysroot 也要用动态链接的原因。对照 3.1 节只差 72 字节的实验：
静态链接的代价取决于库有多大，libsub.a 只有一行代码，libc.a 是整个 C 标准库。

一个新鲜发现，也是"别背符号名"的教训（2026-10-16，工具链 glibc 2.41）：

```text
$ arm-linux-gnueabihf-nm hello_arm_dynamic | grep -i printf
         U printf@GLIBC_2.4

$ arm-linux-gnueabihf-nm hello_arm_static | grep -w printf
(没有输出!静态版里根本没有叫 printf 的符号)
```

反汇编 main 看它到底调了谁：

```text
bl  1c648 <___printf_chk>     %s 分支: fortify 加固版 printf
bl  10cc4 <_IO_puts>          无格式符分支: gcc 把 printf 优化成了 puts
```

两件事叠加：`-O2` 下 gcc 把无格式符的 `printf` 改写成 `puts`；Ubuntu 默认
开 fortify（`_chk` 后缀的加固版）。**上一台机器上这门课的实测是 `T printf`**——
符号名随工具链版本变，不变的是判别方法：动态版符号是 `U`（借），
静态版能看到 printf 家族的完整实现（有）。判据写 U/T 的区别，不写符号名。

**[判] 第 4、5 节的判据**

    [ ] 动态版 nm 里 printf 是 U;静态版能看到 printf 族的实现符号(名字随版本变)
    [ ] 动态版有 .interp,静态版没有
    [ ] 静态版体积是动态版的 5 倍以上(本机 7.03 倍;别背绝对数字)
    [ ] 静态版 e_type 是 EXEC,说得出为什么(没有 ld.so 来做重定位了)
    [ ] readelf -d 动态版有 NEEDED libc.so.6

    注错见红:把 -static 拼成 -Static 或放到 -o 后面,两条判据同时翻车
    (.interp 还在、体积没涨),报错却不明显——这正是它成为常见坑的原因。

---

## 6 [做 L2] 绕过 libc，直接跟内核说话

视频 4_1-2 画过三层图：你的 app、库、内核。本节把中间那段展开：
`printf` 不是系统调用，`write` 才是。

| 顺序 | 所在层 | 动作 |
|---|---|---|
| 1 | 用户态 libc | printf 调 vfprintf，解析 `%s` 拼出 `hello, world\n` |
| 2 | 用户态 libc | 字符串进 stdout 缓冲区（终端行缓冲，文件全缓冲，stderr 无缓冲） |
| 3 | 用户态 libc | 冲刷时调 `write(1, "hello, world\n", 13)` |
| 4 | 用户态 → 内核态 | ARM 执行 `svc #0`，`r7=4`(write 的系统调用号)、`r0=1`、`r1=buf`、`r2=13` |
| 5 | 内核态 | `sys_write()` → tty 驱动 → 串口 → 你屏幕上的一行字符 |

这张图解释一个嵌入式调试天天遇到的现象：**程序跑飞了，printf 的内容一个字
都没出来，好像那行代码没执行。** 其实执行了——字符串还躺在缓冲区里，
程序一崩缓冲区就没了。所以调试打印要么加 `\n`，要么 `fflush(stdout)`，
要么直接用 write。上板调试这一条会救你好几次。

（用户态怎么请内核干活、`svc` 做了什么，见
[fundamentals/07](../../fundamentals/07_系统调用与用户内核态.md)；
跟 ysyx 的对照：ARM 的 `svc` 就是你实现过的 riscv `ecall`。）

实验代码 `Knowledge/labs/02_gcc/hello_write.c`，不用 printf，用 write
打同一句话：

```c
#include <unistd.h>

int main(void)
{
    write(1, "hello, world\n", 13);
    /*   ^  1 是标准输出 stdout,2 是标准错误 stderr
     *                    ^^^ 字节数,必须数对 */
    return 0;
}
```

`write` 三个参数的去处：`man 2 write`（2 = 系统调用手册；printf 在 man 3，
是库函数；man 1 是命令）。编译与验证：

```bash
cd /mnt/e/Workspace/Embedded-linux/Knowledge/labs/02_gcc
gcc -Wall hello_write.c -o hello_write
./hello_write
strace -e trace=write ./hello_write
#     ^^^^^^^^^^^^^^^ 只跟踪 write,不然满屏都是加载动态库的调用

arm-linux-gnueabihf-objdump -d ../01_hello/hello_arm_static | grep -c svc
arm-linux-gnueabihf-objdump -d ../01_hello/hello_arm_dynamic | grep -c svc
```

本机实测（2026-10-16）：

```text
$ ./hello_write
hello, world
$ strace -e trace=write ./hello_write
write(1, "hello, world\n", 13)        = 13

$ grep -c svc  (动态版): 0
$ grep -c svc  (静态版): 15
```

动态版是 0 不是 bug：syscall 的封装都在 libc.so.6 里，没链进你的文件；
静态版把 libc 搬进来了，那 15 条就是 write / exit / brk 这些封装的真身。

**[判]**

    [ ] hello_write 的未定义符号里有 write(write 也在 libc 里,
        它是 syscall 的薄封装,不是 syscall 本身)
    [ ] strace 只看到一条 write,字节数 13
    [ ] 说得清 printf 和 write 的分工:printf 在用户态做格式化和缓冲,
        最终也是调 write
    [ ] 静态版反汇编里有 svc,动态版没有,说得出原因

    注错见红:把 write(1, ...) 的 fd 从 1 改成 2,输出改走 stderr。
    验证:./hello_write > /dev/null——改之前屏幕上什么都没有,
    改之后字符串照样出现。这条同时证明你用的确实是 write。

---

## 7 选项清单去哪查

原书 145-153 页把 GCC 的选项按类抄了一大份（总体/警告/调试/优化/链接器/
目录选项），视频原话："这些内容是从以前我写的书里面截取出来的，有需要的人
可以去看"。本仓把它整理成了可检索的选项清单（04 篇），用到再查：

**[fundamentals/04 GCC 的选项](../../fundamentals/04_GCC的选项.md)**

本章正文只用了 `-E -S -c -o -v -static -shared -fPIC -I -L -l` 十一个，
已经覆盖日常九成场景；`-O2 -Wall -Wextra` 的完整语义、`-M` 依赖文件、
`-nostartfiles` 这类进阶项都在 04 篇里。

---

## 8 自检问题

答不上来就回到对应小节重读。这些问题都能用命令验证，不要凭印象答。

    1. gcc 的四个逻辑步骤分别由哪几个内部程序执行？为什么四个步骤
       只有三个程序？链接时链接器还自动塞进了哪些你没写的东西？      (1.2)

    2. 一个 .c 里有语法错误，gcc -E 会报错吗？为什么？               (1.3)

    3. 一条命令编 1000 个文件有什么问题？分开编怎么解决？
       "哪些需要重编"的判断最后是谁做的？                            (2.1 2.2)

    4. 头文件找不到、undefined reference、运行时找不到动态库，
       这三个报错各对应"去哪找"表里哪一行？各用什么选项解决？         (3 3.1)

    5. 链接时用 -L. -lsub 成功了，运行时却报找不到 libsub.so。
       为什么？两个"找"分别由谁、在什么时刻、按什么规则进行？          (3.1)

    6. 一个动态链接的 hello，从 execve 到 main 的第一条指令之间，
       内核和用户态各做了什么？动态链接器是谁加载的？                 (4.2)

    7. 为什么 -static 编出的程序没有 .interp 段，e_type 从 DYN 变回
       EXEC？静态版的代价是多大一个量级？                             (5)

    8. 静态版里 grep 不到叫 printf 的符号，但程序照样打印成功。
       可能是哪两件事造成的？这个现象教你判据应该写什么、不应该写什么？(5)

    9. printf 和 write 的分界线在哪？为什么程序崩溃时 printf 的内容
       可能一个字都看不到？怎么避免？                                 (6)

---

## 9 已知的坑

    坑 1  apt 工具链和本板 glibc 2.30 已实测不匹配:动态 hello 明确报
          GLIBC_2.34 not found、退出 1。本阶段加 -static 规避,
          第 2 阶段换 BSP 工具链。                                    (4.3)

    坑 2  -static 要放在 -o 前面。放到 -o 后面会被当成输出文件名,
          而且没有报错,产物悄悄变成动态版。                          (5)

    坑 3  链接时找得到库,不代表运行时找得到。链接是 ld 按 -L 找,
          运行是 ld.so 按 LD_LIBRARY_PATH 和默认目录找,两套规则。      (3.1)

    坑 4  -l 的名字规则是"去 lib 补后缀":-lsub 找 libsub.so/libsub.a。
          写成 -lsub.so 会找 libsub.so.so,报错很迷惑。                 (3)

    坑 5  -O2 下 gcc 会把无格式符的 printf 优化成 puts、开启 fortify
          (_chk 系列),符号名和旧教材对不上不是你编错了。判据写
          U/T 的区别,不写具体符号名。                                  (5)

    坑 6  交叉编译动态库要带 -fPIC(原书 2.1.4 特别提醒)。缺了它
          链接时可能报 relocation 错误。                               (3.1)

---

## 10 这一章交出了什么

现在能独立做到：

- 用 `-E`/`-S`/`-c` 停在任意一步，说得出 `.i`/`.s`/`.o` 各是什么、谁做的
- 用 `gcc -v` 看出四个逻辑步骤实际只有 `cc1`/`as`/`collect2` 三个程序
- 遇到"头文件找不到 / undefined reference / 运行时库找不到"，分别定位到预处理、
  链接、运行三个阶段，并用 `-I`/`-L`/`-l` 或 `-static` 处理
- 现场做静态库和动态库，解释 `U` 与 `GLIBC_x.xx` 版本要求的含义
- 说得出 `-static` 的代价与 `-O2` 下符号名变化的原因

还不能做：

- 把几十个文件的编译写成 Makefile（第 03 篇）
- 完整交叉构建一个第三方库并部署到板子（fundamentals/14、第 06 篇）
- 编内核模块（第 2 阶段，要 BSP 工具链与内核源码）

这一章在整机里的位置：它把 01 篇的一条命令拆成四步。03 篇把这几条命令写进
Makefile；后面的第三方库（06 篇的 FreeType、刀 2 的 libjpeg-turbo）靠这四步加参数才编得出来。

下一章：[03 Makefile 的使用](03_Makefile的使用.md)。
