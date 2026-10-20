# 03 ABI 与 sysroot

    实验    Knowledge/labs/00_basics/04_abi_and_regs/（与 02 篇共用一套判据）
    电脑    WSL Ubuntu 26.04，gcc 15.2.0，arm-linux-gnueabihf-gcc 15.2.0，
            两套 glibc 均为 2.43（本篇"本机实测"均为 2026-10-20 实跑）
    板子    100ASK_IMX6ULL Pro，glibc 2.30（本篇只引用已归档的板上实测，不重跑）

---

## 你会在哪里撞见它

教程 01 篇 §2.7 里有一步：交叉编译 ARM 程序时，编译器没有去电脑的
`/usr/include` 找 `stdio.h`，而是去了 `/usr/arm-linux-gnueabihf/include`。
当时只说了句"交叉编译器自带一套给 ARM 用的头文件和库"。这一步为什么必须这样、
拿错了会怎样，就是本篇的事。

另一个常见现场：交叉编译报 `fatal error: stdio.h: No such file or directory`。
`stdio.h` 电脑上明明有，于是很自然会想拿 `-I/usr/include` 指过去。本篇 §6
会亲手做一次这件事，让你看到它的真实后果。

还有一个容易混的词：API 和 ABI。源码对得上，编出来的东西却拼不到一起，
问题就出在后者身上。

## 这篇要回答的问题

1. API 和 ABI 差在哪？为什么源码对得上，二进制还可能拼不上？
2. 交叉编译为什么不能直接用电脑上的头文件和库？sysroot 到底是什么？
3. `-I`、`-L`、`-l` 各管哪一段？链接时找到的库，运行时为什么不一定找得到？

## 0 先动手看一眼

同一行 C 代码，在两个平台上问 `long` 有几个字节。x86 这边直接跑
（`Knowledge/labs/00_basics/04_abi_and_regs/sizes.c`）：

```bash
gcc sizes.c -o sizes_x86 && ./sizes_x86
```

ARM 程序在电脑上跑不了，改用编译期断言问编译器（怎么问，§2.1 讲）：

```bash
for t in 'sizeof(long)==4' 'sizeof(long)==8'; do
    printf '_Static_assert(%s, "no");\nint main(void){return 0;}\n' "$t" > q.c
    if arm-linux-gnueabihf-gcc -c q.c -o /dev/null 2>/dev/null; then
        echo "  ARM: $t   成立"
    else
        echo "  ARM: $t   不成立"
    fi
done
```

本机实测：

```text
=== x86-64 实跑 ===
char=1 short=2 int=4 long=8 longlong=8 ptr=8 time_t=8
struct{char a; int b;} = 8

=== ARM 32 位，用断言问 ===
  ARM: sizeof(long)==4   成立
  ARM: sizeof(long)==8   不成立
```

同一个 `long`，x86-64 上 8 字节，ARM 32 位上 4 字节。`sizeof` 不是 C 语言
规定死的，是 ABI 规定的。本篇把这件事问到底，再回答"编译 ARM 程序时，头文件
和库这套材料从哪来"。

---

## 1 API 与 ABI：两个只差一个字母的词

    API (Application Programming Interface)     源码层面的约定
    ABI (Application Binary Interface)          机器码层面的约定

API 是写代码时看的东西：

```c
int open(const char *path, int flags);
```

这行声明说清了三件事：函数叫 `open`，收一个字符串和一个整数，返回一个整数。
换编译器、换优化等级、换目标架构，这行声明一个字都不用改。

ABI 是编译完之后、字节与寄存器层面的约定。同一次 `open` 调用，编出来的机器码
要遵守的全是另一类问题：

    path 放 r0，flags 放 r1，返回值在 r0           <- 02 篇 §2.3 实测
    r4～r11 调用前后必须保持原值                    <- 02 篇 §3.3 实测
    浮点参数走 s0/s1 还是 r0/r1                     <- 02 篇 §4.2 实测
    long 占 4 字节还是 8 字节                        <- 本篇 §2
    struct { char a; int b; } 占几个字节，怎么填缝   <- 本篇 §2
    栈向低地址生长，公开接口处 sp 保持 8 字节对齐      <- 02 篇 §2.5 实测
    C++ 的函数名怎么修饰（name mangling）            <- 本仓用 C，不展开

写代码时看不见 ABI，但两个 `.o` 要链到一起，ABI 就必须逐条一致。02 篇 §5 已经
实测过其中一条不一致的下场：链接器拒绝，报 `uses VFP register arguments`。
那就是 ABI 冲突被当场拦下的样子；拦不住的那些（类型大小、结构体布局）更麻烦，
本篇 §2、§6 各看一个。

给这两个词各一句定义：**API 规定源码怎么写，ABI 规定编译产物怎么对接。**源码
兼容（API 一致）是两个程序能一起编译的前提，不是它们能拼在一起运行的保证。

**这一节搭好的积木**：ABI 管的七件事里，前四条 02 篇已经实测过，剩下"类型
大小"和"结构体布局"两条由本篇补。接下来的问题：这两条在两个平台上差多少。

---

## 2 实验 1：类型大小是 ABI 定的

### 2.1 怎么问一台跑不了程序的机器：_Static_assert 探针

量 x86-64 的类型大小容易，写个 `printf("%zu", sizeof(long))` 跑一下就行。
ARM 程序在 x86 上跑不了（01 篇 §3.1），板子又不在手边，怎么问？

用一个 C11 的编译期断言：`_Static_assert(条件, "消息")`。条件在编译期就能算
出来：为真，什么都不发生；为假，编译报错。`sizeof` 恰好是编译期常量，所以
断言能让"这个类型是不是这么大"变成"编不编得过"，编不编得过不需要运行。

探针命令（§0 已见过）：

```bash
printf '_Static_assert(%s, "no");\nint main(void){return 0;}\n' "$t" > q.c
arm-linux-gnueabihf-gcc -c q.c -o /dev/null
```

- `printf ... > q.c`：现场生成一个两行的 C 文件。
- `-c -o /dev/null`：只关心编不编得过，产物直接扔掉。
- 退出码 0 就是"成立"，非 0 就是"不成立"。

### 2.2 实测：long、指针、char 的符号

把想问的一次问完：

```bash
for t in 'sizeof(long)==4' 'sizeof(long)==8' 'sizeof(void*)==4' \
         'sizeof(struct{int id; long offset;})==8' '(char)-1 > 0'; do
    printf '_Static_assert(%s, "no");\nint main(void){return 0;}\n' "$t" > q.c
    if arm-linux-gnueabihf-gcc -c q.c -o /dev/null 2>/dev/null; then
        echo "  ARM: $t   成立"
    else
        echo "  ARM: $t   不成立"
    fi
done
```

本机实测：

```text
  ARM: sizeof(long)==4                     成立
  ARM: sizeof(long)==8                     不成立
  ARM: sizeof(void*)==4                    成立
  ARM: sizeof(struct{int id; long offset;})==8   成立
  ARM: (char)-1 > 0                        成立
```

和 §0 的 x86 结果并排：

    类型或表达式                    x86-64     ARM 32 位（armhf）
    ---------------------------     ------     -------------------
    sizeof(long)                    8          4
    sizeof(void *)                  8          4
    sizeof(int)                     4          4
    sizeof(long long)               8          8
    struct{int id; long offset;}    16         8
    (char)-1 > 0（char 无符号？）    不成立      成立

最后一行值得停一下：ARM 上 `char` 默认是**无符号**的（AAPCS32 的规定），x86 上
是有符号的。同一段 `char c = ...; if (c < 0)` 的代码，在两个平台上走的分支
不同。这类差异编译期没有任何警告。

`struct{int id; long offset;}` 两个平台差一倍，下一小节拆开看。

### 2.3 struct{int id; long offset;}：两个平台两种布局

假设有个结构体：

```c
struct config { int id; long offset; };
```

两个平台的编译器对它排出的内存布局：

    x86-64，sizeof = 16              ARM 32 位，sizeof = 8

    偏移  0       4       8       16  偏移  0       4       8
          | int   | 填缝  | long   |          | int   | long   |
          | id    | 4 字节| offset |          | id    | offset |

读法：每个格子 4 字节。x86-64 上 `long` 占 8 字节且必须放在 8 的倍数地址上，
`id` 后面先填 4 字节空缝，`offset` 从偏移 8 开始，总共 16 字节。ARM 上 `long`
只占 4 字节、按 4 对齐，`offset` 紧跟在 `id` 后面，总共 8 字节。

含义很直接：**同一段 C 声明，在两个平台编译出来的机器码按不同的偏移访问同一
个结构体。**如果一边写文件、另一边读（配置文件、共享内存、网络包），读出来的
全是错位的垃圾，而两边各自编译时都安安静静。

§0 里 `struct{char a; int b;} = 8` 也是同一类事：`char` 1 字节加 `int` 4 字节
本是 5 字节，实际占 8，`a` 后面填了 3 字节让 `b` 落在 4 的倍数上。结构体成员
之间怎么填缝、整个结构体按几对齐，都是 ABI 写的，不是编译器的心情。

所以跨平台交换数据的那条规矩：**交换格式自己写死**（固定宽度类型加显式的字节
排布），不要把内存里的结构体直接倒来倒去。

### 2.4 time_t 的新情况：工具链默认 64 位

`time_t`（`time()` 返回的那种时间）本仓 2026-09-08 的旧测量里，ARM 上是 4
字节。2026-10-20 重测，先加一行 `#include <time.h>` 再问：

```text
  ARM: sizeof(time_t)==8   成立
  ARM: sizeof(time_t)==4   不成立
  x86: sizeof(time_t)==8   成立
```

现在是 **8 字节**。变化不是 ARM 的 ABI 改了，是这套工具链的默认配置改了。
查编译器预定义的宏：

```bash
echo | arm-linux-gnueabihf-gcc -dM -E - | grep -E 'TIME_BITS|FILE_OFFSET'
```

- `-dM -E -`：只做预处理，把全部预定义宏打印出来。

```text
#define _TIME_BITS 64
#define _FILE_OFFSET_BITS 64
```

再追一层，这两个宏是谁定义的：

```bash
arm-linux-gnueabihf-gcc -dumpspecs | grep -m1 -o -- '-D_TIME_BITS=64'
```

```text
-D_TIME_BITS=64
```

`specs` 是 gcc 启动时读的内置规则文本，发行版在这里加了一条：只要命令行没有
显式否定，每次编译自动带上 `-D_TIME_BITS=64 -D_FILE_OFFSET_BITS=64`。这是
发行版为 2038 年问题做的迁移：32 位 `time_t` 数到 2038 年 1 月就溢出，glibc
支持把 32 位平台的 `time_t` 拉到 64 位，开关就是这个宏。

这件事对板子有一个直接后果。编一个调 `time()` 的动态链接 ARM 程序，看它要求
的库版本标签（01 篇 §5.2 讲过这套标签机制）：

```bash
arm-linux-gnueabihf-gcc -O2 tm.c -o tm_dyn
arm-linux-gnueabihf-objdump -T tm_dyn | grep time
```

```text
00000000      DF *UND*	00000000 (GLIBC_2.34) __time64
```

`time()` 变成了 `__time64`，要求 `GLIBC_2.34`。板子上是 glibc 2.30（01 篇
§5.2 归档的 `/lib/libc-2.30.so`），没有这个标签。按同一套机制推断，这样的
程序在板子上会报同样的 `version not found`（板子不在线，本条是推断，依据是
01 篇 §5.2 已实测的同类报错）。静态链接的程序把库的实现整个拷进自己体内，
不找板子的库，不受这条影响，01 篇 §5.3 的 `-static` 规矩又多了一个理由。

还有一个探针本身的坑，写判据时踩到的：**用断言问 `time_t` 必须先
`#include <time.h>`。**没 include 时 `time_t` 是个未定义的名字，编译在走到
断言之前就失败了，于是 `==8` 和 `==4` 两个相反的断言会**双双不成立**。
两个相反断言必须一个成立、一个失败；双双失败说明探针没生效，前面的结论全部
作废。这也是 check.sh 里"探针自检"那两条存在的原因。

### 2.5 [判] 类型大小

    [ ] ARM 上 sizeof(long)==4 成立、==8 不成立
    [ ] ARM 上 sizeof(void*)==4 成立
    [ ] ARM 上 struct{char a; int b;}==8、struct{int id; long offset;}==8 成立
    [ ] ARM 上 (char)-1 > 0 成立（char 无符号）
    [ ] ARM 上 sizeof(time_t)==8 成立，能说出是哪个宏把它拉成 64 位
    [ ] 探针自检：sizeof(long)==4 在 x86 上必须编不过；
        x86 上 struct{int;long;}==16 成立

    自动核对：check.sh 的 "03 篇 2.5" 一节，9 条。

    注错见红：把 time_t 那条判据改成 ==4 再跑，必须变红
    （2026-09-08 的旧稿写的是 4，那是旧测量的真实数字，现在变了）。

**这一节搭好的积木**：类型大小、对齐、结构体布局由 ABI 规定，两个平台可以
差一倍；`_Static_assert` 能在编译期问出跑不了的平台上的常量，但探针要先
证明自己是活的。接下来的问题：编译 ARM 程序用的头文件和库，为什么必须也是
ARM 那一套。

---

## 3 sysroot：目标系统的替身根目录

### 3.1 编译要的三类材料，都必须是目标平台的

[00 篇](00_从源码到运行.md) §2.4 讲过，编译一个程序除了翻译你写的代码，还要
三类外来材料：

    头文件      stdio.h 这类，里面有声明，也有 FILE 等结构体的布局
    库文件      libc.so / libc.a，链接时要用
    启动文件    crt1.o 等，00 篇 §4.2 在 app.map 里见过 Scrt1.o，_start 在里面

这三类都必须来自目标平台。头文件那一类最容易被小看，把因果链写完整。假设
交叉编译时拿到了 x86 的 `stdio.h`：

1. x86 的头文件按 x86-64 的 ABI 定义 `FILE` 等结构：`long` 和指针字段各占
   8 字节，字段偏移按 8 字节对齐算。
2. 编译器按这份布局生成 ARM 机器码：访问 `FILE` 的某个字段时，用的是 x86-64
   的偏移。
3. 板子上的 C 库按 ARM 32 位布局解释同一块内存：那些字段各占 4 字节。
4. 程序运行时读到的是错位的内容。编译期一路无警告，因为编译器没有第二份
   布局可对照，它不知道手里这份是错的。

§2.3 已经实测过两个平台的结构体布局可以差一倍，这条链上的第 2、3 步不是
假设。§6 会亲手制造一次这种混用。

材料集中放在哪？给它们一个统一的根：

> **sysroot**：编译时扮演"目标系统的根目录"的那个目录。编译器找
> `/usr/include/stdio.h` 这类路径时，实际找的是 `<sysroot>/usr/include/stdio.h`。

    <sysroot>/
        usr/include/     目标平台的头文件
        usr/lib/         目标平台的库
        lib/             动态链接器（ARM 上是 ld-linux-armhf.so.3）

换一个 sysroot，整套材料库就换了。交叉工具链动辄几百兆，大头就是 sysroot
里这套目标平台的文件，编译器本身没那么大。

### 3.2 动手：问编译器材料在哪

不用猜目录，gcc 有一批 `-print-` 选项专门回答这类问题：

```bash
arm-linux-gnueabihf-gcc -print-sysroot                # sysroot 在哪
arm-linux-gnueabihf-gcc -print-file-name=libc.so      # 链接 -lc 时用哪个文件
arm-linux-gnueabihf-gcc -print-file-name=crt1.o       # 启动文件在哪
gcc -print-sysroot                                    # 对照：本机编译器
```

### 3.3 实测：路径、目录树、-print-sysroot 为什么是 /

本机实测：

```text
=== arm-linux-gnueabihf-gcc ===
-print-sysroot          : /
-print-file-name=libc.so: /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/lib/libc.so
-print-file-name=crt1.o : /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/lib/crt1.o

=== gcc（x86）===
-print-sysroot          : （空行）
-print-file-name=libc.so: /usr/lib/gcc/x86_64-linux-gnu/15/../../../x86_64-linux-gnu/libc.so
```

那串 `../../../..` 看着头晕，用 `readlink -f` 化简，它把路径里的 `..` 和符号
链接全部解开：

```bash
readlink -f "$(arm-linux-gnueabihf-gcc -print-file-name=libc.so)"
readlink -f "$(gcc -print-file-name=libc.so)"
```

```text
/usr/arm-linux-gnueabihf/lib/libc.so
/usr/lib/x86_64-linux-gnu/libc.so
```

`/usr/lib/gcc-cross/arm-linux-gnueabihf/15/` 往上回退四层正好回到 `/`，再接
`arm-linux-gnueabihf/lib/libc.so`。两个编译器各去各的目录，谁也不碰谁：

    /usr/arm-linux-gnueabihf/               ARM 材料区，扮演板子的 /
        include/
            stdio.h                       目标平台的头文件
            bits/                         架构相关的拆分部分
        lib/
            libc.so                       链接脚本，第 4 节拆它
            libc.so.6                     真正的 ARM C 库
            libc.a                        静态库
            crt1.o                        启动文件，_start 在里面
            ld-linux-armhf.so.3           动态链接器
    /usr/lib/gcc-cross/arm-linux-gnueabihf/15/
        include/                          编译器自带的头（stddef.h、stdarg.h）

现在解释那个刺眼的 `/`。`-print-sysroot` 回答 `/`，不是说没有 sysroot，而是
这台电脑的 sysroot 就是系统根目录本身：Ubuntu 用 multiarch 布局，把多个架构
的材料并排装在同一棵树里，靠目录名里的三元组区分（`arm-linux-gnueabihf` 一区、
`x86_64-linux-gnu` 一区，01 篇 §2.5 讲过三元组各段的含义）。x86 那个
`-print-sysroot` 输出空行，意思一样：没有独立 sysroot，就用 `/`。

另一种常见做法是芯片或板卡厂商发布的工具链：自带一个独立的 sysroot 目录，
里面是从板子系统里整套拷出来的 `usr/include`、`usr/lib`，`-print-sysroot`
会打印一个真实的长路径。编内核模块时必须用和板子内核同源的那种工具链，
到第 2 阶段会碰上。两种布局对照：

    Debian/Ubuntu multiarch                    厂商工具链的独立 sysroot
    -----------------------------------        ------------------------------
    /usr/arm-linux-gnueabihf/lib/    ARM       <sysroot>/usr/lib/
    /usr/lib/x86_64-linux-gnu/       x86       <sysroot>/usr/include/
    -print-sysroot 返回 /                      返回一个真实路径
    apt 装交叉工具链就有                       跟着板子的系统一起发布
    应用层实验用这个                           编内核模块必须用这个

### 3.4 [判] sysroot

    [ ] arm-linux-gnueabihf-gcc -print-sysroot 输出 /
    [ ] -print-file-name=libc.so 经 readlink -f 化简后指向
        /usr/arm-linux-gnueabihf/lib/libc.so
    [ ] 能说出 -print-sysroot 为 / 不代表没配 sysroot

    自动核对：check.sh 的 "03 篇 3.5" 一节，2 条。

    注错见红：把期望路径改成 /usr/lib/arm-linux-gnueabihf/ 再跑，必须变红。

**这一节搭好的积木**：交叉编译的三类材料必须是目标平台的，统一放在 sysroot
这棵替身根目录下；本机是 multiarch 布局，sysroot 就是 `/`，靠三元组目录名
分架构。接下来的问题出在材料本身：那份 `libc.so`，真的是个库吗。

---

## 4 实验 2：libc.so 竟然不是一个库

### 4.1 目标与动手

§3.3 找到 `libc.so` 在 `/usr/arm-linux-gnueabihf/lib/libc.so`。按后缀它应该
是个 ARM 的共享库，用 `file` 验证一下：

```bash
file -Lb /usr/arm-linux-gnueabihf/lib/libc.so
```

- `-L`：如果它是符号链接，看它指向的真身。`-b`：只输出类型，不带文件名。

### 4.2 实测

```text
ASCII text
```

**是文本，不是 ELF。**容易以为 `.so` 后缀就是共享库；实测它是一个文本文件。
（这条结论推翻过一条按常理写、从没跑过的判据，那条判据写的是"file 一下是
ELF 32-bit ARM"。遇事先 `file`，别按后缀想。）

### 4.3 逐行读：它是一个链接脚本

既然是文本，直接看内容：

```bash
cat /usr/arm-linux-gnueabihf/lib/libc.so
```

```text
/* GNU ld script
   Use the shared library, but some functions are only in
   the static library, so try that secondarily.  */
OUTPUT_FORMAT(elf32-littlearm)
GROUP ( /usr/arm-linux-gnueabihf/lib/libc.so.6 /usr/arm-linux-gnueabihf/lib/libc_nonshared.a  AS_NEEDED ( /usr/arm-linux-gnueabihf/lib/ld-linux-armhf.so.3 ) )
```

它是写给链接器看的一张单子，三段各有用处：

    OUTPUT_FORMAT(elf32-littlearm)
        产物必须是 32 位小端 ARM 的 ELF。架构信息直接写在这行里，
        01 篇 §3.3 看的 e_machine 那两个字节，源头之一就是这类声明。

    GROUP ( libc.so.6  libc_nonshared.a  ... )
        链接 -lc 时实际要一起用的文件：
          libc.so.6          真正的共享库，绝大部分函数在这里
          libc_nonshared.a   少数只有静态版的函数，开头注释里那句
                             "some functions are only in the static library"

    AS_NEEDED ( ld-linux-armhf.so.3 )
        动态链接器。01 篇 §3.5 里 INTERP 一项写的就是它

所以 `-lc` 的含义是"按这张单子链三样东西"，不是"链一个文件"。真正的库本体
和静态库都在同一目录：

```bash
file -L "$(arm-linux-gnueabihf-gcc -print-file-name=libc.so.6)"
arm-linux-gnueabihf-gcc -print-file-name=libc.a
file -b /usr/arm-linux-gnueabihf/lib/libc.a
```

```text
.../libc.so.6: ELF 32-bit LSB shared object, ARM, EABI5 version 1 (GNU/Linux), dynamically linked, ...
/usr/arm-linux-gnueabihf/lib/libc.a
current ar archive
```

`libc.so.6` 才是 ELF，`ARM`、`32-bit`，和 01 篇 §2.7 看过的对得上；`.a` 是
静态库的打包格式（[05 篇](05_静态库动态库与符号.md)讲怎么打、怎么抽）。

对照本机 x86 的 `libc.so`：

```text
OUTPUT_FORMAT(elf64-x86-64)
GROUP ( /usr/lib/x86_64-linux-gnu/libc.so.6 /usr/lib/x86_64-linux-gnu/libc_nonshared.a  AS_NEEDED ( /lib64/ld-linux-x86-64.so.2 ) )
```

两边都是链接脚本，只有 `OUTPUT_FORMAT` 那一行和路径不同。这一行正好就是
架构标记。

### 4.4 [判] libc.so 是链接脚本

    [ ] file 报 libc.so 是 ASCII text，不是 ELF
    [ ] 内容里有 OUTPUT_FORMAT(elf32-littlearm) 和 GROUP
    [ ] libc.so.6 才是 ELF 32-bit ARM；libc.a 是 ar 打包
    [ ] 能说出 GROUP 里三个文件各是干什么的

    自动核对：check.sh 的 "03 篇 4.4" 一节，5 条。

    注错见红：把判据里的文件换成 libc.so.6 再断言"ASCII text"，必须变红。

**这一节搭好的积木**：`-lc` 展开成一张链接脚本里的单子；判断一个文件是什么，
用 `file` 看内容，不看后缀。接下来的问题：两套材料并排装在系统里，编译器
每次具体去哪些目录找。

---

## 5 实验 3：两个编译器的搜索路径有没有交集

### 5.1 目标与动手

让两个编译器各自把头文件搜索路径列出来，再 diff。01 篇 §1.5 用过同一条命令：

```bash
diff <(echo 'int main(){}' | arm-linux-gnueabihf-gcc -E -v - 2>&1 | sed -n '/search starts/,/End of/p') \
     <(echo 'int main(){}' | gcc                     -E -v - 2>&1 | sed -n '/search starts/,/End of/p')
echo "退出码=$?"
```

- `-E -v -`：只预处理、打印内部动作、源码从标准输入读。
- `2>&1`：这些信息走标准错误，合并过来才能进管道。
- `<(命令)`：进程替换，把命令输出当成一个临时文件交给 diff。

### 5.2 实测

```text
3,4c3,5
<  /usr/lib/gcc-cross/arm-linux-gnueabihf/15/include
<  /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/include
---
>  /usr/lib/gcc/x86_64-linux-gnu/15/include
>  /usr/local/include
>  /usr/include/x86_64-linux-gnu
退出码=1
```

### 5.3 逐行读

`3,4c3,5` 是 diff 的记法：左边第 3～4 行与右边第 3～5 行内容不同（c =
change）；`<` 开头是左边（ARM）独有，`>` 开头是右边（x86）独有。diff 退出码
非 0 表示两边确实不同。

没被列出来的行是两边相同的，其中有一条 `/usr/include`：**这个目录两边共用。**
这不矛盾。`/usr/include` 下放的是架构无关的部分（`stdio.h` 的骨架之类），
架构相关的定义被拆到 `bits/` 子目录里，由各自的 `arm-linux-gnueabihf/include`
或 `x86_64-linux-gnu` 目录提供。这正是 multiarch 的设计：共用的共用，不共用
的按架构分开。§6 的 `-H` 输出能直接看到骨架和 `bits/` 拼起来的过程。

### 5.4 [判] 搜索路径

    [ ] ARM 的列表里有 gcc-cross 和 arm-linux-gnueabihf 的目录
    [ ] x86 的列表里有 x86_64-linux-gnu 的目录
    [ ] diff 退出码非 0
    [ ] 对比方法自检：同一个编译器比自己，diff 为空、退出码 0

    自动核对：check.sh 的 "03 篇 5.4" 一节，4 条。

    注错见红：把 diff 的两边都换成 ARM 编译器，"确实不同"那条必须变红，
    "对比方法自检"必须仍然通过。判据自己要能区分"真的不同"和"对比方法错了"。

**这一节搭好的积木**：两个编译器的搜索路径主体不同，只共用架构无关的
`/usr/include`。接下来做那个危险动作：把 x86 的头文件目录硬塞进 ARM 的搜索
列表。

---

## 6 实验 4：故意混用头文件

### 6.1 现象：它安安静静编过了

按 §3.1 的因果链，把 x86 的头文件目录塞到搜索列表最前面，应该能造出一个
布局错乱的 ARM 程序。但也可能运气好，当场报错。做一次：

```bash
cat > t.c <<'EOF'
#include <stdio.h>
int main(void) { printf("hello\n"); return 0; }
EOF

arm-linux-gnueabihf-gcc -c t.c -o t.o; echo "正常编译: $?"
arm-linux-gnueabihf-gcc -I/usr/include/x86_64-linux-gnu -c t.c -o t_bad.o; echo "混入 x86 头: $?"
```

本机实测：

```text
正常编译: 0
混入 x86 头: 0
```

**编过了，一个字的警告都没有。**这里要交代一句环境差异：在没装 x86 32 位
头文件的机器上，同一条命令会在 include 链深处撞上 `gnu/stubs-32.h` 找不到
而报错中止；本机 2026-10-20 装有这个头文件（`libc6-dev-i386` 包），链条走得
通，于是静默编过。报错才是运气，编译器本身没有任何机制检测"你混用了两个
架构的头文件"。

### 6.2 用 -H 看 include 链：两套头文件在交替出现

混用到底是怎么发生的，让编译器把 include 过程打印出来：

```bash
arm-linux-gnueabihf-gcc -I/usr/include/x86_64-linux-gnu -H -c t.c -o t_bad.o
```

- `-H`：每 include 一个文件打印一行，行首的点数表示嵌套深度。

本机实测（前 12 行）：

```text
. /usr/arm-linux-gnueabihf/include/stdio.h
.. /usr/include/x86_64-linux-gnu/bits/libc-header-start.h
... /usr/arm-linux-gnueabihf/include/features.h
.... /usr/arm-linux-gnueabihf/include/features-time64.h
..... /usr/include/x86_64-linux-gnu/bits/wordsize.h
..... /usr/include/x86_64-linux-gnu/bits/timesize.h
...... /usr/include/x86_64-linux-gnu/bits/wordsize.h
.... /usr/include/x86_64-linux-gnu/sys/cdefs.h
..... /usr/include/x86_64-linux-gnu/bits/wordsize.h
..... /usr/include/x86_64-linux-gnu/bits/long-double.h
.... /usr/include/x86_64-linux-gnu/gnu/stubs.h
..... /usr/include/x86_64-linux-gnu/gnu/stubs-32.h
```

第 1 行是 ARM 的 `stdio.h`（搜索列表里它排在前面的目录先命中）；它 include
`bits/libc-header-start.h` 时，`bits/` 在 ARM 的目录里不存在，轮到被 `-I`
塞到最前面的 x86 目录，于是第 2 行跳进 x86；再往深处，`features.h` 又命中
ARM 目录。两套头文件交替出现，拼出一个谁也没设计过的组合。§5.3 说
"架构无关的骨架共用、架构相关的 bits/ 分开"，这个机制在混用时变成了陷阱：
骨架是 ARM 的，`bits/` 却来自 x86。

### 6.3 证明它已经坏了：sizeof(jmp_buf) 从 392 变成 156

"编过但没报错"和"没坏"是两回事。找一个两边定义不同的类型，让编译器自己把
大小算出来对比。`jmp_buf`（`setjmp.h` 里保存现场用的数组）正合适：

```bash
cat > probe.c <<'EOF'
#include <setjmp.h>
int s_jmp = sizeof(jmp_buf);
EOF

arm-linux-gnueabihf-gcc -S -o - probe.c | grep -A1 '^s_jmp:'
arm-linux-gnueabihf-gcc -I/usr/include/x86_64-linux-gnu -S -o - probe.c | grep -A1 '^s_jmp:'
```

`sizeof` 是编译期常量，编出来的汇编里，变量 `s_jmp` 的初值直接写成数字，
看 `.word` 那行即可。本机实测：

```text
--- 正常 ---
s_jmp:
	.word	392
--- 混入 x86 头文件后 ---
s_jmp:
	.word	156
```

同一行 `sizeof(jmp_buf)`，正常是 392，混入 x86 头文件后变成 156，编译器
一声不吭。如果这段代码编进程序、再把 `setjmp`/`longjmp` 跑起来，程序按 156
字节的布局读写，C 库按 392 字节的布局解释，§3.1 因果链的最后一步就这样
走通了。这类问题在板子上的现象是莫名其妙的数据错乱，回看编译期没有任何
线索可找。

规矩因此是硬性的：

    交叉编译时，永远不要手动加 -I/usr/include 或 -L/usr/lib。
    工具链自己知道去 sysroot 里找，指错方向比不指更糟。

交叉构建第三方库时，`configure` 这类脚本很容易把宿主机的路径混进编译命令，
[14 篇](14_第三方库的交叉构建与部署.md) §2 实测过三个时刻分别会撞出什么错。

### 6.4 一个反向的教训：-I 指到不存在的目录

```bash
arm-linux-gnueabihf-gcc -I/nonexistent -c t.c -o /dev/null; echo "退出码=$?"
```

```text
退出码=0
```

`-I` 指向不存在的目录，gcc 一声不吭地跳过。所以"编译成功"既不能证明 `-I`
写对了，也不能证明没混入别的东西。想确认编译时到底用了哪些头文件，用 §6.2
的 `-H` 看，别拿"编过了"当证据。

### 6.5 [判] 混用头文件

    [ ] 不加 -I 时编译成功
    [ ] 塞入 x86 头文件目录后仍静默编过（本机装有 x86 32 位头；
        没装的机器上撞 gnu/stubs-32.h 报错，check.sh 里那两条相应 SKIP）
    [ ] sizeof(jmp_buf) 正常 392、混用后 156，两个数确实不同
    [ ] -I 指向不存在的目录时 gcc 不报错

    自动核对：check.sh 的 "03 篇 6.5" 一节，4 条。

    注错见红：把判据改成期望两个 sizeof 相等再跑，必须变红。

**这一节搭好的积木**：混用宿主机头文件会静默编出布局错位的程序，编译器不管
这件事，只能靠"不指错目录"这条规矩和 `-H` 这种检查手段。还剩最后一组每天
都在敲的选项没说清：`-I`、`-L`、`-l`。

---

## 7 -I / -L / -l 各管哪一段

三个选项分属编译过程的不同阶段，放一起看：

    选项        管什么              在哪个阶段起作用
    --------    ----------------    ----------------------------
    -I<dir>     加一个头文件目录    预处理阶段，找 #include
    -L<dir>     加一个库目录        链接阶段，找 .so / .a
    -l<name>    链接 lib<name>      链接阶段

一条完整的命令（06 章交叉构建 FreeType 时就是这个形态）：

    arm-linux-gnueabihf-gcc -I./include -L./lib -o app main.c -lfreetype -lm
                            ^^^^^^^^^^^         ^^^^^^^^^^^ 去哪找库文件
                            去哪找 .h                       ^^^^^^^^^^^^^^^^ 链哪些库

三个坑，前两个在本仓已经踩过：

1. **`-l` 要写在源文件和 `.o` 后面。** 链接器从左往右扫，扫到 `-lm` 时如果还
   没人用到 `m` 里的符号，它就跳过去；后面再出现 `sqrt` 的引用，已经没人
   能提供，报 `undefined reference`。[00 篇](00_从源码到运行.md) §3.5 演示过
   这个报错从哪来。
2. **`-lfreetype` 找的是 `libfreetype.so`。** 前缀 `lib` 和后缀 `.so`（或
   `.a`）是链接器自己拼的，命令行上只写中间那截名字。
3. **交叉编译时 `-L` 别指到 `/usr/lib`。** 那里是 x86 的库，§6 的教训原样适用。

头文件的搜索顺序：

    1. -I 指定的目录，按命令行出现的先后
    2. 工具链自带的目录（gcc 内建目录 + sysroot 里的 usr/include 等）
    3. /usr/include（multiarch 布局下两边共用的那一层）

    #include "xxx.h"  引号：先找当前源文件所在目录，再走上面三步
    #include <xxx.h>  尖括号：跳过"源文件所在目录"这一步

最后把第三个问题的另一半回答掉：**链接时找到，不等于运行时找到。** `-L` 只
管链接那一刻；程序在板子上启动后，去哪里找 `.so` 是动态链接器按它自己的一
套路径规则决定的，[05 篇](05_静态库动态库与符号.md)讲那套规则。01 篇 §5.2
的 `GLIBC_2.34 not found` 就是运行时这一步的报错：链接时明明链上了，板子上
库的版本标签对不上，程序以退出码 1 收场。编译时的 `-L` 和 sysroot 帮不了
运行时，两边要各自对齐。

---

## 8 顺带：和 ysyx 的对照

没做过 ysyx 跳过这一节即可，本篇不依赖它。

    ysyx / abstract-machine              Linux 交叉编译
    ---------------------------------    ------------------------------
    没有 sysroot 这个概念                必须有
    libc 是 am 自带的 klib               libc 是别人（glibc）编好的
    头文件就在项目目录里                  头文件在工具链的一棵目录树里
    -I$(AM_HOME)/klib/include            工具链自动带上 sysroot 路径

ABI 其实已经踩过一次：RISC-V 的 `ilp32` / `ilp32f` / `ilp32d` 和 ARM 的
`soft` / `softfp` / `hard` 是同一件事的两套命名（02 篇 §7 有对照表）。改了
它整个 am 要重编，原因和 02 篇 §5.2 讲的完全相同：两边对"参数放哪"的理解
必须字面一致。

---

## 9 速查清单

罗列内容集中在这里，查的时候用。依据列：实测日期为本机 2026-10-20；
AAPCS32 指 ARM 的调用标准文档。

### 基本类型大小与布局

| 类型 / 表达式 | x86-64 | ARM 32 位（本工具链） | 依据 |
|---|---|---|---|
| `char` / `short` / `int` | 1 / 2 / 4 | 1 / 2 / 4 | 实测 §0 |
| `long` | 8 | 4 | 实测 §2.2 |
| `long long` | 8 | 8 | 实测 §0 |
| `void *` | 8 | 4 | 实测 §2.2 |
| `wchar_t` | 4 | 4 | 断言实测；另见 `readelf -A` 的 Tag_ABI_PCS_wchar_t |
| `time_t` | 8 | 8（默认 `-D_TIME_BITS=64`） | 实测 §2.4 |
| `char` 的符号 | 有符号 | 无符号 | 实测 §2.2（AAPCS32 规定） |
| `struct { char a; int b; }` | 8 | 8 | 实测 §0 |
| `struct { int id; long offset; }` | 16 | 8 | 实测 §2.2、§2.3 |
| `FILE`（glibc 2.43） | 216 | 152 | 断言实测 2026-10-20 |

`sizeof(long)`、结构体布局由 ABI 规定，不由 C 语言规定；跨平台交换数据要
自己写死格式。板子（glibc 2.30）上的 `time_t` 是 32 位时代的产物，本工具链
默认 64 位，动态链接会要求 `GLIBC_2.34` 的 `__time64`（实测 §2.4）。

### sysroot 里有什么

    <sysroot>/
        usr/include/     目标平台的头文件
        usr/lib/         目标平台的库
        lib/             动态链接器（ARM 上是 ld-linux-armhf.so.3）

| 位置 | 内容 | 交叉编译时的意义 |
|---|---|---|
| 电脑 `/usr/include/stdio.h` | 给 x86 用的头文件 | 不要拿它编 ARM 程序 |
| `bin/arm-linux-gnueabihf-gcc` | 编译器本体 | 生成 ARM 机器码 |
| `<sysroot>/usr/include/stdio.h` | 目标系统配套的头文件 | 编译时把 `<sysroot>` 当作 `/` |
| `<sysroot>/lib/libc.so` | 链接脚本，指向与目标系统匹配的库 | 链接用的库和板上运行的库版本要对得上 |

本机是 multiarch 布局：sysroot 为 `/`，ARM 材料在 `/usr/arm-linux-gnueabihf/`
（实测 §3.3）。

### 问编译器的 -print 系列（本机实测）

| 命令 | 本机输出 |
|---|---|
| `arm-linux-gnueabihf-gcc -print-sysroot` | `/`（x86 的 gcc 输出空行） |
| `... -print-file-name=libc.so` | `.../arm-linux-gnueabihf/lib/libc.so`（链接脚本，§4） |
| `... -print-file-name=crt1.o` | `.../arm-linux-gnueabihf/lib/crt1.o` |
| `... -print-search-dirs` | programs / libraries 的完整搜索列表 |
| `... -print-multiarch` | `arm-linux-gnueabihf`（multiarch 目录名） |

输出的路径带 `../../../..` 时，用 `readlink -f` 化简再看。

### 搜索路径开关

| 选项 | 管什么 | 哪个阶段 |
|---|---|---|
| `-I<dir>` | 加一个头文件目录 | 预处理，找 `#include` |
| `-L<dir>` | 加一个库目录 | 链接，找 `.so` / `.a` |
| `-l<name>` | 链接 `lib<name>` | 链接 |

头文件搜索顺序：`-I` 目录（按命令行顺序）→ 工具链内建 + sysroot →
`/usr/include`（multiarch 共有层）。`#include "x.h"` 先找源文件所在目录，
`#include <x.h>` 跳过这一步。

三个坑：`-l` 要放在源文件后面；`-lfreetype` 找的是 `libfreetype.so`；交叉
编译时 `-I` / `-L` 别指到宿主机的 `/usr/include`、`/usr/lib`。想核实实际用了
哪些头文件，用 `-H` 打印 include 链（实测 §6.2）。

## 10 回看

| 问题 | 答案 | 证据在哪 |
|---|---|---|
| API 和 ABI 差在哪 | API 管源码怎么写，ABI 管产物怎么对接 | §1 |
| 类型大小谁定 | ABI；long、指针、布局两个平台可以不同 | §2.2、§2.3 |
| 跑不了的平台怎么问 | `_Static_assert` 编译期探针，先做探针自检 | §2.1、§2.4 |
| 材料为什么必须是目标平台的 | 头文件决定结构体布局，拿错就静默错位 | §3.1、§6.3 |
| sysroot 是什么 | 编译时扮演目标系统根目录的那棵树 | §3.1、§3.3 |
| libc.so 是什么 | 一段链接脚本，`-lc` 展开成三个文件 | §4.3 |
| 两套材料会不会串 | 搜索路径主体不同，只共用架构无关层 | §5 |
| 混用头文件会怎样 | 静默编过，sizeof(jmp_buf) 从 392 变 156 | §6.1～§6.3 |
| 链接时找到 = 运行时找到？ | 不等，运行时是动态链接器的另一套规则 | §7 |

## 11 带走

开头三个问题的答案：

1. **API 管源码，ABI 管二进制。** 函数声明长得一样，只保证能一起编译，不
   保证产物能拼到一起；类型大小、对齐、结构体布局、寄存器分工全在 ABI 里。
2. **交叉编译必须用目标平台的头文件和库，sysroot 就是放它们的那棵替身根
   目录。** 拿宿主机的 `/usr/include` 顶上，在这台机器上会安安静静编出布局
   错位的程序。
3. **`-I` 管预处理找头文件，`-L` 管链接找库目录，`-l` 选库名。**三者都只管
   编译链接那一刻；运行时找库是动态链接器的另一套规则。

外加四条实测结论：

4. `sizeof(long)`、结构体填缝由 ABI 定；同一结构体两个平台可以差一倍。
5. 本工具链默认 `-D_TIME_BITS=64`，ARM 的 `time_t` 已是 8 字节，动态链接的
   `time()` 要求 `GLIBC_2.34`。
6. 交叉工具链里的 `libc.so` 是链接脚本不是 ELF；判断文件类型用 `file`。
7. `-print-sysroot` 输出 `/` 不是没配 sysroot，是 multiarch 布局；想知道
   实际用了哪份文件，用 `-print-file-name=` 问，别照目录名猜。

### 看到什么，就先想到什么

| 看到的东西 | 第一反应 |
|---|---|
| 交叉编译报找不到 `stdio.h` | 查 sysroot 配没配对，不要拿宿主机的 `/usr/include` 顶上 |
| 想知道实际用了哪份 `libc.so` | `arm-linux-gnueabihf-gcc -print-file-name=libc.so` |
| `file libc.so` 说是文本 | 链接脚本，打开看 GROUP 里指向哪几个文件 |
| 换平台后结构体读写错位 | 查类型大小、对齐、字节序；交换格式自己写死 |
| 编译过了就觉得头文件没问题 | 用 `-H` 看 include 链；编过什么都证明不了（§6） |
| 开发机链得上，板上报缺库或版本不对 | 链接时和运行时是两套搜索；查板上的动态链接器与库版本 |

## 12 接下来

- [05 静态库、动态库与符号](05_静态库动态库与符号.md)：`.a` / `.so` 的打包
  与符号，运行时搜索路径那一套规则。
- [07 系统调用与用户态/内核态](07_系统调用与用户内核态.md)：系统调用号放
  哪个寄存器，也是 ABI 的一部分。
- [14 第三方库的交叉构建与部署](14_第三方库的交叉构建与部署.md)：sysroot、
  `-I` / `-L` 在真实交叉构建里怎么用，configure 怎么把宿主机路径混进来。
- 教程位置：01 篇 §2.5～§2.7 用本篇的结论讲三元组和 sysroot；教程 02 篇里
  `-I` / `-L` / `-l` 的完整故事见 [02 GCC 编译器的使用](../tutorials/01_应用编程/02_GCC编译器的使用.md)第 2.5 与 6.2 节；06 篇交叉
  构建 FreeType 时的报错对照见 14 篇 §2。
