# 04 GCC 的选项

    实验    Knowledge/labs/00_basics/12_gcc_make_options/
    电脑    WSL Ubuntu 26.04，gcc 15.2.0，arm-linux-gnueabihf-gcc 15.2.0
            GNU ld 2.45（本篇"本机实测"均为 2026-10-20 实跑）

这一篇是清单型篇目：gcc 的选项有上千个，全背不现实，用到哪组查哪组。
正文按"这组选项要解决什么问题"分成七组，每组先给问题，再给能跑通的最小
演示和真实输出，最后给本组的完整清单。清单里每一条标注依据：
"实测 2026-10-20" 是本机跑过的，"man gcc" 是查手册登记的。

例子默认用电脑上的 `gcc`。交叉编译时把命令名换成
`arm-linux-gnueabihf-gcc`，选项完全通用，第 5.1 节有实测。

---

## 你会在哪里撞见它

- 教程 02 篇[02 GCC 编译器的使用](../tutorials/01_应用编程/02_GCC编译器的使用.md)第 1.1 节里，`-v` 打印出 cc1、as、collect2 三条命令，
  每个名字后面拖着一长串参数，那些参数全是这里登记的选项。
- 本仓 [Project/Makefile](../../Project/Makefile) 第 62 行写着
  `CFLAGS := -Wall -Wextra -Werror -O2`，第 102 行写着 `-MMD -MP`，
  不加这几行，工程的纪律和头文件依赖都没有着落。
- 交叉编译报 `greet.h: No such file or directory`，或者链接时报
  `undefined reference to 'sub_fun'`，或者程序在板子上报
  `error while loading shared libraries`：分别对应第 4、6 节的三套路径。

## 这篇要回答的问题

1. 编译四步各停在哪个选项上？怎么看见 gcc 每一步在干什么？
2. 头文件找不到、链接时库找不到、运行时库找不到，是三件不同的事，
   分别归哪组选项管？
3. 警告、优化、调试信息这三组开关各怎么取舍，组合错了会怎样？

## 0 先查三条

清单型篇目，不设起步实验。先按要解决的问题定位到某一节：

| 你要解决 | 去第几节 |
|---|---|
| 只想预处理 / 只要汇编 / 只编不链 / 看 gcc 内部动作 | 1 |
| 有警告要不要管、想让警告变错误 | 2 |
| 开优化、留调试信息、两者冲突 | 3 |
| 头文件找不到、想知道 gcc 默认去哪找 | 4 |
| 交叉编译、Thumb 指令、浮点 ABI 对不上 | 5 |
| undefined reference、静态还是动态、找不到共享库 | 6 |
| 命令行定义宏、自动生成 .d 依赖文件 | 7 |
| 直接抄一套本仓常用组合 | 8 |

---

## 1 控制编译停在哪一步：-E -S -c -o -v

一个 `.c` 文件变成可执行文件要走预处理、编译、汇编、链接四步
（推导见 [00 从源码到运行](00_从源码到运行.md)）。gcc 默认一口气走完，
这组选项让它停在中途，把中间产物留下来。

### 1.1 -v：先看 gcc 每一步叫的是谁

实验文件用 labs 里的 `main.c`、`sub.h`、`sub.c`（见文末"实验文件"一节）。
给一条最普通的编译命令加上 `-v`：

```bash
cd Knowledge/labs/00_basics/12_gcc_make_options
gcc -o /dev/null main.c sub.c -v 2>&1 | grep -E 'cc1|[-/]as |collect2'
```

- `-o /dev/null`：产物直接扔掉，这里只关心过程。
- `-v`：让 gcc 把内部调用的每条命令打印出来（打在标准错误上，所以 `2>&1`）。
- `grep -E 'cc1|[-/]as |collect2'`：只留三行关键的。`as` 这个名字太短，
  前面限定一个 `-` 或 `/`，免得误中别的词。

本机实测（每行截短到 110 列）：

```text
 /usr/libexec/gcc/x86_64-linux-gnu/15/cc1 -quiet -v -imultiarch x86_64-linux-gnu main.c -quiet -dumpdir a- -du
 /usr/bin/x86_64-linux-gnu-as -v --64 -o /tmp/cckE2HcO.o /tmp/cc1x2wLb.s
 /usr/libexec/gcc/x86_64-linux-gnu/15/cc1 -quiet -v -imultiarch x86_64-linux-gnu sub.c -quiet -dumpdir a- -dum
 /usr/bin/x86_64-linux-gnu-as -v --64 -o /tmp/ccN6nDBk.o /tmp/cc1x2wLb.s
 /usr/libexec/gcc/x86_64-linux-gnu/15/collect2 -plugin /usr/libexec/gcc/x86_64-linux-gnu/15/liblto_plugin.so -
```

五行正好对应"两个源文件各自走前三步，最后拼一次"：

    main.c --> [cc1] --> /tmp/ccXXX.s --> [as] --> /tmp/ccYYY.o --+
                                                                  +--> [collect2] --> 可执行文件
    sub.c  --> [cc1] --> /tmp/ccXXX.s --> [as] --> /tmp/ccZZZ.o --+

- `cc1` 是 C 编译器本体，预处理加编译都由它做，产出临时 `.s` 汇编文件。
- `as` 是汇编器，把 `.s` 翻成机器码，产出临时 `.o`。
- `collect2` 是 gcc 包在链接器 ld 外面的一层，由它去叫 ld，把两个 `.o`、
  启动文件（crt1.o 等）和 C 库拼成可执行文件。
- 临时文件都在 `/tmp` 下，链接完就被删掉。想留下它们，用 `-save-temps`
  （见本组清单）。

gcc 自己只是个调度员。任何一步出问题，把 `-v` 的输出翻出来，就知道
该去查哪个程序。

### 1.2 -E -S -c：把四步手工走一遍

```bash
gcc -E -o main.i main.c     # 只预处理，结果存 main.i
gcc -S -o main.s main.i     # 只编译（读 .i），产出汇编 main.s
gcc -c -o main.o main.s     # 只汇编（读 .s），产出目标文件 main.o
gcc -c -o sub.o sub.c       # sub.c 一条命令走到 .o
gcc -o test main.o sub.o    # 只链接
./test
```

本机实测：

```text
$ wc -l main.c main.i
    9 main.c
  849 main.i
$ wc -l main.s
46 main.s
$ file main.o
main.o: ELF 64-bit LSB relocatable, x86-64, version 1 (SYSV), not stripped
$ ./test
Main fun!
Sub fun!
```

三处值得停下来看：

1. **预处理把 9 行撑成 849 行。**`#include <stdio.h>` 把几百行声明插了进来，
   `main.i` 才是编译器真正读的东西。想知道某个宏展开成什么、某个头文件
   到底包没包进来，看 `.i` 文件最直接。
2. **gcc 按输入文件的后缀决定从哪一步开始。**`.i` 是"已预处理过的 C"，
   跳过头文件展开直接编译；`.s` 是汇编，直接送 as。同一份源码从中间任意
   一步接着走，都不影响最后的结果。
3. **`.o` 是"可重定位"（relocatable）的 ELF**：里面的地址还没定，要等
   链接时拼。`file` 说的 relocatable 就是这个意思。

**多文件的两种编法。**文件少时一条命令走全程：

```bash
gcc -o test main.c sub.c
```

文件多时先各自编成 `.o`，改谁重编谁，最后只链接：

```bash
gcc -c -o main.o main.c
gcc -c -o sub.o  sub.c
gcc -o test main.o sub.o
```

第二种是 Makefile 存在的前提：03 篇[03 Makefile 的使用](../tutorials/01_应用编程/03_Makefile的使用.md)第 0 节就是从这个
对比出发的。

### 1.3 不给 -o 时产物叫什么

```bash
gcc main.c sub.c     # 可执行文件叫 a.out
gcc -c main.c        # 目标文件叫 main.o（源名换后缀）
gcc -S main.c        # 汇编文件叫 main.s
gcc -E main.c        # 不产文件，结果全部打到标准输出
```

本机实测前三条依次产出 `a.out`、`main.o`、`main.s`。规律只有一条：
**不给 `-o` 时，gcc 把源文件名的后缀换成当前停点对应的后缀**；停无可停
（链接完成）时叫 `a.out`；`-E` 没有约定俗成的后缀，送 stdout。

### 1.4 本组清单

| 选项 | 作用 | 缺省产物 | 依据 |
|---|---|---|---|
| `-E` | 预处理后即停 | 结果送 stdout；配 `-o x.i` 存文件 | 实测 2026-10-20 |
| `-S` | 编译后即停，不汇编 | `source.c` → `source.s` | 实测 2026-10-20 |
| `-c` | 汇编后即停，不链接 | `source.c` → `source.o` | 实测 2026-10-20 |
| `-o file` | 指定输出文件名 | 不给时：可执行 `a.out`，其余按源名换后缀 | 实测 2026-10-20 |
| `-v` | 打印 gcc 配置与内部调用的每条命令 | 打在标准错误上 | 实测 2026-10-20 |
| `-save-temps` | 中间产物（.i/.s）不删，留在当前目录 | 文件名按 `-o` 的名字推导 | 实测 2026-10-20 |
| `-x c` | 强制把后面的输入当 C 语言（不管后缀或管道） | 配管道读源码时用 | 实测 2026-10-20 |
| `-###` | 与 `-v` 类似但只打印不执行 | 排查用 | man gcc |

`-save-temps` 实测补充：`gcc -save-temps -c opt.c -o opt_st.o` 之后，
目录里留下 `opt_st.i`、`opt_st.s`、`opt_st.o`，中间文件跟着 `-o` 的
名字走，不是跟着源文件名。

**这一节搭好的积木**：gcc 是调度四个程序的驱动，`-E`/`-S`/`-c` 是三个
停点，`-v` 看见每一步。下一组问题：编译器发现的"语法没错但很可疑"的
地方，怎么让它说出来。

---

## 2 管警告：-Wall -Wextra -Werror

### 2.1 现象：同一份代码，四种编法四种反应

labs 里的 `warn.c` 故意留了三处"能编过但可疑"的写法：一个定义了没用的
变量 `i`，一次 `unsigned` 和 `-1` 的比较。分别用四种警告级别编：

```bash
gcc -c warn.c -o /dev/null; echo "exit=$?"
gcc -Wall -c warn.c -o /dev/null; echo "exit=$?"
gcc -Wall -Wextra -c warn.c -o /dev/null; echo "exit=$?"
gcc -Wall -Wextra -Werror -c warn.c -o /dev/null; echo "exit=$?"
```

本机实测：

```text
exit=0                                     <-- 什么都不加：一声不吭
warn.c:10:9: warning: unused variable 'i' [-Wunused-variable]
exit=0                                     <-- -Wall：说了，但放行
warn.c:14:11: warning: comparison of integer expressions of different signedness: 'unsigned int' and 'int' [-Wsign-compare]
warn.c:10:9: warning: unused variable 'i' [-Wunused-variable]
exit=0                                     <-- -Wextra：多说了一条，仍放行
warn.c:14:11: error: comparison of integer expressions of different signedness: ...
warn.c:10:9: error: unused variable 'i' [-Werror=unused-variable]
cc1: all warnings being treated as errors
exit=1                                     <-- -Werror：全部升级成错误，编不过
```

逐条读：

- **什么都不加，gcc 对可疑写法保持沉默**，exit 0，产物正常。警告不是错误，
  默认连提都不提。
- **`-Wall`** 开一批"八成是写错了"的检查。注意它名字里虽然有 All，
  实际只开了一部分：这里的符号比较（`-Wsign-compare`）它就没管。
- **`-Wextra`** 在 `-Wall` 之上再开一批，符号比较由它补上。每条警告末尾
  方括号里是它的开关名，想单独关掉某一条就用 `-Wno-名字`。
- **`-Werror`** 把所有警告升级成错误：警告还在原地，但级别变成 error，
  编译失败，exit 1。最后那行 `cc1: all warnings being treated as errors`
  是 cc1 在说明"这不是普通的错，是你让我把警告当错的"。

符号比较那条不是小题大做：`n < -1` 里 `n` 是 `unsigned int`，`-1` 会被
转成很大的无符号数，这个比较恒为假，里面的代码是死代码。警告替你看见了
一处逻辑错误。

### 2.2 本仓的纪律

本仓所有 labs 的 check.sh 与 [Project/Makefile](../../Project/Makefile)
（第 62 行）都开 `-Wall -Wextra`；Project 进一步加 `-Werror`，有警告就
编不过。这样警告永远不会积累成"几百条没人看"的状态。

容易以为 `-Wall` 是"全部警告"；实测它只是一批常用的，`-Wextra` 补的
那一批里就有符号比较、未用参数这些高频坑。两组一起开才算基本盘。

### 2.3 本组清单

| 选项 | 作用 | 依据 |
|---|---|---|
| `-Wall` | 打开常用警告（未用变量、声明前使用、格式串不符等） | 实测 2026-10-20 |
| `-Wextra` | 再开一批（符号比较、未用参数等） | 实测 2026-10-20 |
| `-Werror` | 所有警告升级为错误 | 实测 2026-10-20 |
| `-Werror=名字` | 只把某一种警告升级为错误 | man gcc |
| `-Wno-名字` | 单独关掉某一种警告 | man gcc |
| `-w` | 关掉全部警告（本仓不用） | man gcc |

**这一节搭好的积木**：警告分 `-Wall`、`-Wextra` 两层，`-Werror` 决定
它们是提示还是拦路。下一组：优化级别和调试信息怎么选。

---

## 3 管优化与调试信息：-O 与 -g

### 3.1 -O0 到 -Os：同一份代码的五种下场

`opt.c` 里有一个 `square` 函数和两次 `printf`。分别用五个级别编成 `.o`，
看代码段大小：

```bash
for o in O0 O1 O2 O3 Os; do gcc -$o -c opt.c -o sz_$o.o; done
size sz_O0.o sz_O1.o sz_O2.o sz_O3.o sz_Os.o
```

本机实测：

```text
   text    data     bss     dec     hex filename
    225       0       0     225      e1 sz_O0.o
    193       0       0     193      c1 sz_O1.o
    187       0       0     187      bb sz_O2.o
    187       0       0     187      bb sz_O3.o
    181       0       0     181      b5 sz_Os.o
```

`text` 是机器码的字节数。级别越高，编译器越肯花力气压缩代码：`-O0` 是
照源码直译（225 字节），`-O2` 少了 38 字节。`-Os` 以体积为目标，最小。

差别具体到指令层面，用 `objdump -r` 看 `.o` 里"要从外面找的函数"
（重定位项）：

```bash
gcc -O0 -c opt.c -o o0.o; objdump -r o0.o
gcc -O2 -c opt.c -o o2.o; objdump -r o2.o
```

本机实测（符号名列）：

```text
-O0: puts  square  printf
-O2: puts  __printf_chk
```

两个变化：

1. **`square` 消失了**：`-O2` 把它内联展开，省掉一次函数调用。
2. **`printf` 变成了 `__printf_chk`**：Ubuntu 的 gcc 在优化打开时默认加
   fortify 加固，把格式串函数换成带缓冲区检查的版本。

容易以为"无格式符的 `printf` 改写成 `puts`"也是 `-O2` 的功劳；实测
`-O0` 的重定位项里就已经是 `puts` 了。这个改写太便宜（格式串是常量，
直接少传一个参数），gcc 不优化也做。真正随 `-O2` 出现的是 fortify 的
`__printf_chk`。对比符号表时看到这两个名字都不要慌，行为不变。

### 3.2 多个 -O 同时给：最后一个生效；超出范围不报错

```bash
gcc -O0 -O2 -c opt.c -o a.o    # 谁生效？
gcc -O2 -O0 -c opt.c -o b.o
gcc -O9    -c opt.c -o c.o     # 没有 -O9 这个级别
```

本机实测（与只给一个级别的产物逐字节比较）：

```text
-O0 -O2 的产物 == 只给 -O2 的产物
-O2 -O0 的产物 == 只给 -O0 的产物
-O9     的产物 == 只给 -O3 的产物
```

**多个 `-O` 同时出现时，最后一个生效，前面的被静默覆盖。**
**`-O9` 不报错，被静默按最高的 `-O3` 处理。**两条都是"不报错但容易想错"
的典型，脚本里拼 CFLAGS 时尤其要留意覆盖顺序。

### 3.3 -g：调试信息是另加的段，不动代码

```bash
gcc -O0 -g -c opt.c -o opt_g.o
gcc -O0    -c opt.c -o opt_ng.o
ls -l opt_g.o opt_ng.o
readelf -S opt_g.o | grep -c debug
readelf -S opt_ng.o | grep -c debug
```

本机实测：

```text
4096  opt_g.o
1736  opt_ng.o
9     <-- opt_g.o 里的 .debug 段数量
0     <-- opt_ng.o
```

`-g` 按系统的本地格式（Linux 上是 DWARF）生成调试信息，存进一批 `.debug`
开头的段：哪条机器码对应源码哪一行、变量叫什么、类型是什么，全在里面，
gdb 靠它们工作。它只是往文件里**加**内容，不改生成的机器码，所以
`-g` 可以和任何 `-O` 组合。

但组合了不等于好用：`-O2` 会把代码重排、内联，单步执行时行号会跳、
变量会被优化掉。**要单步调试就 `-O0 -g`，要发布就 `-O2`**，这是本仓的
默认取舍（labs 用 `-O2`，需要查问题时临时换 `-O0 -g` 重编）。

### 3.4 本组清单

| 选项 | 作用 | 代价 | 依据 |
|---|---|---|---|
| `-O0` | 不优化（缺省） | 代码直白，最好调试 | 实测 2026-10-20 |
| `-O` / `-O1` | 基础优化 | 编译稍慢 | 实测 2026-10-20 |
| `-O2` | 几乎全部不含"空间换时间"激进项的优化 | 编译更慢；调试时行号跳 | 实测 2026-10-20 |
| `-O3` | 在 -O2 之上再开函数内联、循环展开等 | 体积可能变大 | 实测 2026-10-20 |
| `-Os` | 以体积为目标的 -O2 | 极端场景可能更慢 | 实测 2026-10-20 |
| `-Og` | 为调试体验优化的轻量级别 | 优化有限 | man gcc |
| `-g` | 生成 DWARF 调试信息 | 文件变大，不改机器码 | 实测 2026-10-20 |
| `-ggdb` / `-g3` | 更全的 gdb 专用信息 / 含宏定义 | 更大 | man gcc |
| `-gstabs+` 等 | 老式调试格式 | 一般用不到 | man gcc |

规则回顾：**多个 `-O` 最后一个生效；`-O` 后面跟的超范围数字按最高级处理
（均实测 2026-10-20）。**

**这一节搭好的积木**：优化级别管"代码变成什么样"，`-g` 管"文件里带不带
地图"，两者可组合但有最佳拍档。下一组：gcc 去哪找头文件和库。

---

## 4 管头文件与库的搜索路径

### 4.1 现象：`<greet.h>` 找不到

labs 里 `use_greet.c` 用尖括号包含 `hdr/greet.h`（里面只定义了一个宏
`GREETING`）。直接编：

```bash
gcc -c use_greet.c -o /dev/null
```

本机实测：

```text
use_greet.c:2:10: fatal error: greet.h: No such file or directory
    2 | #include <greet.h>
      |          ^~~~~~~~~
compilation terminated.
```

`fatal error` 表示预处理就死了，后面三步根本没开始。原因要回到
`#include` 的两种写法：

- `#include "..."`：先在**源文件所在目录**找，再按下面的列表找。
- `#include <...>`：只在"gcc 登记的目录列表"里找，不看当前目录。

`hdr/greet.h` 不在列表里。给它加一个目录：

```bash
gcc -Ihdr use_greet.c -o t_greet && ./t_greet
```

```text
hi from header
```

`-Ihdr` 把 `hdr/` 加进搜索列表。`-I` 和目录名之间可以有空格也可以没有，
本仓一律连写。

### 4.2 不问不知道：gcc 默认去哪些目录

不用写 `.c` 文件，从标准输入喂一个空程序，让 `-E -v` 把列表打出来：

```bash
echo 'int main(void){}' | gcc -E -v - 2>&1 | sed -n '/#include <...> search starts here/,/End of search/p'
```

本机实测（本机 gcc）：

```text
#include <...> search starts here:
 /usr/lib/gcc/x86_64-linux-gnu/15/include
 /usr/local/include
 /usr/include/x86_64-linux-gnu
 /usr/include
End of search list.
```

同一条命令换交叉编译器：

```text
 /usr/lib/gcc-cross/arm-linux-gnueabihf/15/include
 /usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/include
 /usr/include
```

第二个条目里 `../../../..` 回退四层，实际指向 `/usr/arm-linux-gnueabihf/
include`：交叉编译器找头文件时去的是 ARM 专属的目录，不是电脑上 x86 的
那套。这就是 01 篇 2.7 节讲的"替身根目录"（sysroot）在起作用。

还有几个"问 gcc"的查询选项：

```bash
gcc -print-file-name=libc.so              # 要链接 libc 时用哪个文件
gcc -print-sysroot                        # 替身根目录在哪
gcc -dumpmachine                          # 目标三元组
gcc -print-search-dirs                    # 库、启动文件、内部工具的全套路径
```

本机实测：

```text
$ gcc -print-file-name=libc.so
/usr/lib/gcc/x86_64-linux-gnu/15/../../../x86_64-linux-gnu/libc.so
$ arm-linux-gnueabihf-gcc -print-file-name=libc.so.6
/usr/lib/gcc-cross/arm-linux-gnueabihf/15/../../../../arm-linux-gnueabihf/lib/libc.so.6
$ gcc -print-sysroot          <-- 本机 gcc：打印空行
$ arm-linux-gnueabihf-gcc -print-sysroot
/
$ arm-linux-gnueabihf-gcc -dumpmachine
arm-linux-gnueabihf
```

交叉编译器的 sysroot 答 `/`，不是错：Ubuntu 把 ARM 的文件直接放进
`/usr/arm-linux-gnueabihf/`，靠目录名区分架构，不需要另立根目录。
sysroot 的完整讨论在 [03 ABI 与 sysroot](03_ABI与sysroot.md)。

### 4.3 三套路径各管一段，别混

容易以为 `-L` 加了的目录，运行时也能找到库。实测不行。头文件、链接时的
库、运行时的动态库是**三套独立的路径**：

| 时刻 | 找什么 | 默认路径 | 自己加目录用 |
|---|---|---|---|
| 编译期 | 头文件 | `gcc -E -v` 列出的目录 | `-I目录` |
| 链接期 | `.a` / `.so` | gcc 与 ld 的内置目录 | `-L目录` + `-l名字` |
| 运行期 | `.so`（动态库） | ld.so 缓存与系统目录 | 环境变量 `LD_LIBRARY_PATH` |

第三行的实测在第 6.3 节：链接时 `-L.` 能找到 `libsub.so`，运行时照样
报找不到，要 `LD_LIBRARY_PATH=.` 才能跑。

### 4.4 -I- 已废弃，-nostdinc 是另一回事

本机实测（2026-10-20）：

```text
$ gcc -I- -c use_greet.c -o /dev/null
cc1: note: obsolete option '-I-' used, please use '-iquote' instead
use_greet.c:2:10: fatal error: greet.h: No such file or directory
```

`-I-` 的作用是"把之前的 `-I` 目录限定为只对引号写法生效"。gcc 15.2
仍然接受它，但直接提示已废弃，替代者是 `-iquote`。老 Makefile 里见到
它认识即可，新写的别用。

`-nostdinc` 是另一件事：把系统默认目录整个删掉，只留 `-I` 给的。本机
实测：

```text
$ gcc -nostdinc -c main.c -o /dev/null
main.c:1:19: error: no include path in which to search for stdio.h
```

报错的措辞都变了：不是"文件找不到"，是"连找的地方都没有"。写裸机程序、
bootloader 时才用它（配 `-ffreestanding`），普通程序不用。

### 4.5 本组清单

| 选项 | 作用 | 依据 |
|---|---|---|
| `-I目录` | 头文件搜索列表加一个目录（`<>` 和 `""` 都生效） | 实测 2026-10-20 |
| `-iquote 目录` | 只对 `#include "..."` 生效的目录 | man gcc（`-I-` 的官方替代） |
| `-isystem 目录` | 当系统头目录用：里面的头不触发警告 | man gcc |
| `-nostdinc` | 删掉全部默认头文件目录 | 实测 2026-10-20 |
| `-I-` | 老写法，分隔引号/尖括号两套 `-I` | 实测 2026-10-20（gcc 15.2 已废弃） |
| `-L目录` | 链接时库搜索路径加一个目录；**对运行时无效** | 实测 2026-10-20 |
| `-l名字` | 链接 `lib名字.so` 或 `lib名字.a`（去 `lib` 加后缀） | 实测 2026-10-20 |
| `--sysroot=目录` | 换替身根目录 | man gcc；[14 篇](14_第三方库的交叉构建与部署.md) |
| `-B前缀` | 指定编译器内部工具（cc1/as/ld）的前缀 | man gcc |
| `-print-file-name=名` | 问某个库/文件的实际位置 | 实测 2026-10-20 |
| `-print-sysroot` | 问 sysroot | 实测 2026-10-20 |
| `-print-search-dirs` | 问库、工具的全套搜索路径 | 实测 2026-10-20 |
| `-print-multiarch` | 问 multiarch 目录名（如 x86_64-linux-gnu） | man gcc |
| 环境变量 `GCC_EXEC_PREFIX` | 作用近似 `-B` | man gcc |

**这一节搭好的积木**：三套路径各管一段，`-I` 管编译、`-L`/`-l` 管链接、
`LD_LIBRARY_PATH` 管运行。下一组：给 ARM 生成代码时和"目标"有关的选项。

---

## 5 管目标架构与 ABI

### 5.1 交叉编译：只换命令名，选项不变

同一套选项原样搬到交叉编译器：

```bash
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra main.c sub.c -o test_arm
file test_arm
```

本机实测：

```text
test_arm: ELF 32-bit LSB executable, ARM, EABI5 version 1 (GNU/Linux), ...
```

前面六节的所有选项（`-E`、`-I`、`-L`、`-l`、`-static`……）对交叉编译器
都成立。区别只在产物里的机器码架构和默认搜索路径（4.2 节那套 ARM 目录）。
编译器名字里 `arm-linux-gnueabihf` 每一段的含义，01 篇 2.5 节拆开讲过。

### 5.2 -marm 与 -mthumb：同一条指令的两种长度

ARM 有两套指令编码：ARM 态每条 4 字节，Thumb 态大多 2 字节。同一个
`f_add` 函数（两个 float 相加）分别编：

```bash
arm-linux-gnueabihf-gcc -O2 -marm   -c f_add.c -o f_arm.o
arm-linux-gnueabihf-gcc -O2 -mthumb -c f_add.c -o f_thumb.o
arm-linux-gnueabihf-objdump -d f_arm.o
arm-linux-gnueabihf-objdump -d f_thumb.o
```

本机实测：

```text
-marm:                      -mthumb:
   0: ee300a20  vadd.f32       0: ee30 0a20  vadd.f32
   4: e12fff1e  bx lr          4: 4770       bx lr
```

做的是同一件事（`s0 = s0 + s1`，然后返回），ARM 态一条指令 4 个字节，
Thumb 态只要 2 个。Thumb 代码更省空间，Cortex-A 系列两种都能执行。
`armv7-a`、`-mcpu=`、`-mfpu=` 这一族选项告诉编译器目标 CPU 有什么指令
可用，[00 篇](00_从源码到运行.md)讲汇编产出时用到过 `-march=armv7-a`、
`-mthumb`；板子这颗 Cortex-A7 对应的完整参数，02 篇[02 GCC 编译器的使用](../tutorials/01_应用编程/02_GCC编译器的使用.md)第 1.1 节
有实测。

### 5.3 -mfloat-abi：对不上，链接器直接拒收

三种浮点 ABI 的差别（参数放通用寄存器还是浮点寄存器）在
[02 ARM 寄存器与调用约定](02_ARM寄存器与调用约定.md)讲过。这里实测
"混用会怎样"。`f_caller.c` 按 softfp 编（不碰系统头，免得被头文件里的
检查先拦下），`f_add.c` 按 hard 编，然后让链接器把两个 `.o` 合并：

```bash
arm-linux-gnueabihf-gcc -O2 -mfloat-abi=softfp -c f_caller.c -o f_caller_soft.o
arm-linux-gnueabihf-gcc -O2 -mfloat-abi=hard   -c f_add.c    -o f_add_hard.o
arm-linux-gnueabihf-ld -r f_caller_soft.o f_add_hard.o -o merged.o
readelf -A f_add_hard.o | grep VFP_args
```

本机实测：

```text
/usr/bin/arm-linux-gnueabihf-ld.bfd: error: f_add_hard.o uses VFP register arguments, merged.o does not
/usr/bin/arm-linux-gnueabihf-ld.bfd: failed to merge target specific data of file f_add_hard.o
exit=1
  Tag_ABI_VFP_args: VFP registers      <-- hard 的 .o 里带这个标记；softfp 的不带
```

每个 `.o` 的属性段里记着它按哪种约定传浮点参数（`Tag_ABI_VFP_args`）。
链接器发现两边的标记对不上，宁可不链也不产出一个"能编过但算错"的程序。
**板子的系统库是 hard-float 的，上板的代码必须用 `gnueabihf` 这一套编**，
这不是性能选项，是对错问题（01 篇 2.6 节）。

### 5.4 本组清单

| 选项 | 作用 | 依据 |
|---|---|---|
| `-march=名` | 目标架构版本（如 `armv7-a`） | man gcc；[00 篇](00_从源码到运行.md)实测 |
| `-mcpu=名` | 目标具体型号（如 `cortex-a7`） | man gcc |
| `-mfpu=名` | 浮点单元型号（如 `neon-vfpv4`） | man gcc |
| `-mfloat-abi=` | `soft` / `softfp` / `hard` 三种浮点 ABI | 实测 2026-10-20 |
| `-marm` / `-mthumb` | 生成 ARM 态 / Thumb 态机器码 | 实测 2026-10-20 |
| `--sysroot=目录` | 指定目标系统的替身根目录 | man gcc；[14 篇](14_第三方库的交叉构建与部署.md) |
| `-static` | 上板产物的标配（见 6.2） | 实测 2026-10-20 |

**这一节搭好的积木**：`-m` 一族决定"生成什么机器码、按什么约定传参"，
ABI 对不上链接器拒收。下一组最重：链接。

---

## 6 管链接

链接是把多个 `.o` 和库拼成一个文件的一步（机制见
[05 静态库、动态库与符号](05_静态库动态库与符号.md)）。gcc 识别不出后缀的
输入文件时按内容判断：是 `.o` 或库就直接交给链接器。

### 6.1 -l 放在哪：归档扫描不回头

把 `sub.c` 打成静态库，再让 `main.o` 链它：

```bash
ar rcs libsub.a sub.o
gcc -o t_ok  main.o -L. -lsub     # -l 在使用者之后
gcc -o t_bad -L. -lsub main.o     # -l 在使用者之前
```

本机实测：第一条成功，`./t_ok` 打印两行；第二条失败：

```text
/usr/bin/x86_64-linux-gnu-ld.bfd: main.o: in function `main':
main.c:(.text+0x18): undefined reference to `sub_fun'
collect2: error: ld returned 1 exit status
```

原因：链接器处理归档（`.a`）时只挑"当前已经出现、还没找到定义"的符号
需要的成员，而且**不回头**。`-lsub` 写在 `main.o` 前面时，处理它的那一刻
还没人用过 `sub_fun`，库里一个成员都没被挑走；等 `main.o` 提出
`sub_fun`，库里已经没有机会了。`-l` 永远放在用它的 `.o` **后面**，
这是 "undefined reference" 最经典的一个来源。

即使不写任何 `-l`，链接时也会自动带上 `-lgcc -lgcc_s -lc`，1.1 节的
`-v` 输出里 collect2 那一行末尾就能看到。

### 6.2 -static：把库整个拷进来

```bash
gcc        -o t_dyn2   main.o sub.o
gcc -static -o t_static main.o sub.o
ls -l t_dyn2 t_static
ldd t_static
```

本机实测：

```text
16016   t_dyn2
816992  t_static
not a dynamic executable
```

静态版把用到的 C 库函数全部拷了进来，体积是动态版的 51 倍，换来的是
运行时不再依赖任何 `.so`。本仓的规矩：**现阶段上板的程序一律 `-static`**
（板子的 glibc 2.30 比电脑上的 2.43 老，动态链接的程序上去就报
`GLIBC_2.34 not found`，完整推导在 01 篇 5.2、5.3 节）。

容易以为 `-static` 必须放在 `-o` 之前、放错位置产物会悄悄变回动态版。
本机实测（gcc 15.2.0 / ld 2.45）：`-static` 写在 `-l` 之后、`-o` 之后，
产物都是全静态。原因是 gcc 驱动把它提到 collect2 命令行的最前面（`-v`
输出里可见 `-static` 排在所有用户输入之前），你在 gcc 命令行上写在哪个
位置都一样。这个选项真正要留意的不是位置，而是**它只管链接期**：
静态产物运行时不再找库，也自然没有了第 4.3 节第三行的问题。

### 6.3 -shared -fPIC：做动态库，运行时又是一套路径

```bash
gcc -shared -fPIC -o libsub.so sub.c
gcc -o t_dyn main.o -L. -lsub
ldd t_dyn
./t_dyn
LD_LIBRARY_PATH=. ./t_dyn
```

本机实测：

```text
        libsub.so => not found
./t_dyn: error while loading shared libraries: libsub.so: cannot open shared object file: No such file or directory
exit=127
Main fun!                                <-- LD_LIBRARY_PATH=. 之后
Sub fun!
```

- `-shared`：产物是共享库而不是可执行文件；可以多个 `.o` 打成一个 `.so`。
- `-fPIC`：位置无关代码，共享库要求（本仓 labs 全部加上；
  [05 篇](05_静态库动态库与符号.md)第 6 节实测过它影响的寻址方式）。
- 链接时 `-L.` 能找到库，运行时就找不到了：运行时归动态链接器管，
  它查自己的缓存和 `LD_LIBRARY_PATH`，不知道编译时的 `-L`。
  找不到时报错的程序退出码是 **127**。
- 把库的路径写进产物本身也行：`-Wl,-rpath,'$ORIGIN'` 让运行时去"程序
  自己所在目录"找（本仓 [labs/00_basics/05_libs_and_symbols/check.sh](../labs/00_basics/05_libs_and_symbols/check.sh)
  用了这个写法）。

### 6.4 -nostartfiles 与 -nostdlib：裸机才用

正常程序链接时会被悄悄拼进一批启动文件（crt1.o 等，里面是从入口
`_start` 到 `main` 的桥）。两个选项分别拆掉它们：

```bash
gcc -nostartfiles -o t_ns main.o sub.o; ./t_ns; echo "exit=$?"
gcc -nostdlib     -o t_nl main.o sub.o
```

本机实测：

```text
/usr/bin/x86_64-linux-gnu-ld.bfd: warning: cannot find entry symbol _start; defaulting to 0000000000001030
Segmentation fault
exit=139
```

```text
... warning: cannot find entry symbol _start; ...
main.c:(.text+0x13): undefined reference to `puts'
sub.c:(.text+0x13): undefined reference to `puts'
collect2: error: ld returned 1 exit status
```

读法：

- `-nostartfiles` 只是警告，链接**成功**了。但入口 `_start` 不存在，
  链接器把入口随便指到 0x1030，程序一跑就段错误（exit 139）。容易以为
  "只是个警告应该能跑"；实测警告的背后是产物根本不能运行。
- `-nostdlib` 连 C 库也不链，`printf`（优化后显示为 `puts`）没人提供，
  一排 undefined reference，直接编不过。

编 bootloader、内核时它们自给自足（自己提供入口、不用 C 库），这两个
选项是给那种场景用的；普通应用不用。

### 6.5 给链接器传话：-Wl, 与 -Xlinker；-u 强拉成员

gcc 不认识的链接器选项，要原样转交给 ld：

```bash
gcc -Wl,-Map,t.map -o t_map main.o sub.o
gcc -Xlinker -Map -Xlinker t2.map -o t_map2 main.o sub.o
```

两种写法等价：`-Wl,` 用逗号分隔可以一次带多个参数；`-Xlinker` 一次只带
一个，带参数的选项要写两遍。产物是 `t.map`：一张符号与段的地址清单，
排查链接结果时用。

`-u 符号名` 解决另一个问题：告诉链接器"假装这个符号有人用"。库里没被
引用的成员不会进产物（6.1 节的扫描规则），`-u` 强行把它拉进来：

```bash
gcc -o t_u0 main.o sub.o -L. -lextra              # extra_fun 没人用
gcc -o t_u1 main.o sub.o -L. -u extra_fun -lextra # 强行拉进来
nm t_u0 | grep -c ' T extra_fun'                  # 0
nm t_u1 | grep -c ' T extra_fun'                  # 1
```

本机实测两次计数分别是 0 和 1。内核里靠构造函数段注册的模块初始化，
就靠类似机制保证不被归档扫描漏掉。

### 6.6 本组清单

| 选项 | 作用 | 依据 |
|---|---|---|
| `xxx.o` / `libxxx.a` 直接写在命令行 | 按内容识别，直接交给链接器 | 实测 2026-10-20 |
| `-l名字` | 链接 `lib名字.a/.so`；**放在使用者之后** | 实测 2026-10-20 |
| `-static` | 全部静态链接；位置不影响结果（gcc 提到最前） | 实测 2026-10-20 |
| `-shared` | 产共享库，配 `-fPIC` | 实测 2026-10-20 |
| `-fPIC` | 位置无关代码 | 实测 2026-10-20；05 篇 |
| `-nostartfiles` | 不链启动文件；产物缺 `_start`，跑不了 | 实测 2026-10-20 |
| `-nostdlib` | 连标准库也不链 | 实测 2026-10-20 |
| `-Wl,选项` | 给 ld 传选项，逗号分隔可多个 | 实测 2026-10-20 |
| `-Xlinker 选项` | 同上，一次一个 | 实测 2026-10-20 |
| `-u 符号` | 强制把提供该符号的库成员拉进来 | 实测 2026-10-20 |
| `-Wl,-rpath,目录` | 把运行时库搜索路径写进产物 | 实测（本仓 05 labs） |
| `-Wl,-Map,文件` | 生成链接地址清单 | 实测 2026-10-20 |
| `-pthread` | 线程库的编译+链接总开关 | man gcc；Project/Makefile 第 68 行 |
| `-rdynamic` | 把符号导出给动态库回调用 | man gcc |
| `-s` | 链接后剥掉符号表 | man gcc |
| `-no-pie` / `-pie` | 关/开位置无关可执行（01 篇 3.7 节实测过 `Type` 变化） | 实测（01 篇） |

**这一节搭好的积木**：链接管三件事：谁进来（扫描顺序与 `-u`）、
静态还是动态（`-static` 与 `-shared`）、给 ld 捎话（`-Wl,`）。
最后一组：预处理和自动依赖。

---

## 7 管预处理与依赖：-D -U -M 一族

### 7.1 -D -U：命令行上开关宏

`ver.c` 里用 `#ifdef VERSION` 包了一行打印：

```bash
gcc ver.c -o t_v0 && ./t_v0
gcc -DVERSION=7 ver.c -o t_v7 && ./t_v7
gcc -DVERSION=7 -UVERSION ver.c -o t_vu && ./t_vu
```

本机实测依次打印：`no version`、`version=7`、`no version`。

`-D名字=值` 等同在源码最前面写 `#define 名字 值`；`-U名字` 取消。
同一个名字先 `-D` 后 `-U`，抵消。用编译选项开关功能块（调试打印、
平台差异），不用改源码，这是命令行定义宏的典型用法。本仓 11、13 篇的
labs 用它注入过测试开关。

想知道"这个宏到底有没有、值是多少"，把所有宏打出来：

```bash
gcc -E -dM -DVERSION=3 ver.c | grep -E '^#define (VERSION|__STDC_VERSION__|__linux__)\b'
```

```text
#define __STDC_VERSION__ 202311L
#define __linux__ 1
#define VERSION 3
```

`-dM` 配 `-E`，把预处理结束时的全部宏（含 gcc 预定义的几百个）倒出来。
前两个是 gcc 自己定义的：默认按 C23 编译、目标是 Linux。

另一个相关选项 `-include 文件`：强制在源码最前面包含一个文件，像
命令行版的 `#include`。本机实测：

```text
$ printf 'const char *s = GREETING;\n' | gcc -Ihdr -include greet.h -E -x c - | tail -1
const char *s = "hi from header";
```

### 7.2 -M 一族：让 gcc 自己写出依赖清单

Makefile 要知道"这个 `.o` 依赖哪些 `.h`"，靠 gcc 自己算：

```bash
gcc -M main.c     # 全部依赖（含系统头）
gcc -MM main.c    # 只列自己的头文件
```

本机实测：

```text
$ gcc -M main.c
main.o: main.c /usr/include/stdc-predef.h /usr/include/stdio.h \
 /usr/include/x86_64-linux-gnu/bits/libc-header-start.h \
 ...（共 27 个头文件）... sub.h
$ gcc -MM main.c
main.o: main.c sub.h
```

输出就是一条现成的 Makefile 规则。**`-M` 的清单只打在标准输出上。**
容易以为 `gcc -M main.c abc.dep` 能把清单写进 `abc.dep`；本机实测：

```text
$ gcc -M main.c abc.dep
main.o: main.c /usr/include/stdc-predef.h ...（清单照常打在 stdout）
gcc: warning: abc.dep: linker input file unused because linking not done
gcc: error: abc.dep: linker input file not found: No such file or directory
exit=1
```

`abc.dep` 被当成一个输入文件，gcc 找不到它，报错退出。要落成文件用
`-MD` 一族，它们**不中断正常编译**，依赖清单顺手写到文件：

| 写法 | 落在哪里 | 实测要点 |
|---|---|---|
| `gcc -MMD -c -o m2.o main.c` | `m2.d`（跟着 `-o` 换后缀） | 内容是 `m2.o: main.c sub.h` |
| `gcc -MMD -MP ...` | 同上，但给每个头文件补一条空规则 | `mmp.d` 里多一行 `sub.h:` |
| `gcc -MD -MF custom.dep ...` | `-MF` 改清单文件名 | `-MD` 含系统头，`-MMD` 不含 |
| `gcc -Wp,-MD,.m3.o.d -c -o m3.o main.c` | 清单文件名直传预处理器 | 见下面的细节 |

两个细节各值一次踩坑：

- **`-MP` 的空规则**（`sub.h:` 后面什么都没有）是为了删掉一个头文件后
  make 不报 `No rule to make target 'sub.h'`。本仓 Project/Makefile
  第 97-98 行的注释写的就是这件事。
- **`-Wp,-MD,文件` 把选项原样塞给预处理器**，编译驱动不知道它的存在，
  所以清单里目标名按**源文件**推导：上面的命令里 `-o m3.o` 被无视，
  清单第一行是 `main.o: main.c ...`。labs/03_makefile/proj/Makefile.build
  第 51 行用的正是这个写法，它能工作是因为那里 `$@` 恰好等于"源文件
  换后缀"。

`.d` 文件怎么被 Makefile 吃回去，是 03 篇[03 Makefile 的使用](../tutorials/01_应用编程/03_Makefile的使用.md)第 5 节的内容。

### 7.3 本组清单

| 选项 | 作用 | 依据 |
|---|---|---|
| `-D名字` / `-D名字=值` | 定义宏 | 实测 2026-10-20 |
| `-U名字` | 取消宏定义（可抵消 `-D`） | 实测 2026-10-20 |
| `-include 文件` | 强制先包含一个文件 | 实测 2026-10-20 |
| `-dM`（配 `-E`） | 倒出全部宏，含预定义 | 实测 2026-10-20 |
| `-M` | 依赖清单（含系统头）打到 stdout，不编译 | 实测 2026-10-20 |
| `-MM` | 同上，只列自己的头文件 | 实测 2026-10-20 |
| `-MD` / `-MMD` | 编译不中断，清单写到 `.d` 文件 | 实测 2026-10-20 |
| `-MP` | 给头文件补空规则 | 实测 2026-10-20 |
| `-MF 文件` | 改清单文件名 | 实测 2026-10-20 |
| `-MT 目标` | 改清单里的目标名 | man gcc |
| `-Wp,选项` | 选项原样传给预处理器 | 实测 2026-10-20 |
| `-fdirectives-only` 等 | 预处理细调 | man gcc |

---

## 8 本仓高频组合与补充选项

### 8.1 高频组合（都出自本仓 labs 或 Project）

```bash
gcc -O2 -Wall -Wextra hello.c -o hello       # 日常编译（labs 约定）
gcc -c -o main.o main.c                      # 只编不链
gcc -o test main.o sub.o                     # 只链
arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra main.c sub.c -o test_arm
                                             # 上板产物（必须静态，01 篇 5.3）
gcc -shared -fPIC -o libsub.so sub.c         # 做动态库
ar rcs libsub.a sub.o                        # 做静态库
gcc -MMD -MP -c -o main.o main.c             # 编译同时生成 .d（03 篇自动依赖）
gcc -E -dM x.c | grep 某宏                   # 查宏
gcc -fsanitize=address -g oob.c -o oob       # 让内存错误现形（Project check 脚本在用）
echo 'int main(){}' | gcc -E -v -            # 查默认搜索路径
```

`-fsanitize=address` 的实测（越界写在运行时才被抓到）：

```text
==5191==ERROR: AddressSanitizer: global-buffer-overflow on address 0x55a67d8840c8 ...
WRITE of size 4 at 0x55a67d8840c8 thread T0
```

### 8.2 补充清单

| 选项 | 作用 | 依据 |
|---|---|---|
| `-std=gnu89` 等 | 按指定 C 标准编译（01 篇 1.4 节用它演示老标准的隐式声明） | 实测（01 篇） |
| `-fsanitize=address/undefined` | 运行时检查内存/未定义行为 | 实测 2026-10-20 |
| `-fno-builtin` | 禁用内建函数改写（如 printf→puts） | man gcc |
| `-ffreestanding` | 声明这是独立环境（无操作系统） | man gcc |
| `-m32` | 生成 32 位 x86 代码 | man gcc（需 multilib，本机未装） |

链接器三兄弟 `ld`、`objdump`、`objcopy` 自己的选项本篇不展开：
`objdump` 在 01、02、05 篇随到随讲，`ld` 脚本和 `objcopy` 到第 2 阶段
写裸机与驱动时再用。

---

## 9 [判] 本篇判据

`Knowledge/labs/00_basics/12_gcc_make_options/check.sh` 前半部分逐条核对
本篇清单里标"实测"的条目（与 06 篇共用一套脚本，2026-10-20 全量通过，
126 条合计数见 06 篇末尾）：

    [ ] gcc -v 的输出里同时出现 cc1、as、collect2
    [ ] 不给 -o 时产物依次叫 a.out、main.o、main.s
    [ ] warn.c:无选项静默通过,-Wall 报 unused variable,
        -Wextra 补 sign-compare,-Werror 退出码 1
    [ ] -O0 -O2 的产物与 -O2 逐字节相同;-O9 与 -O3 相同
    [ ] -g 的 .o 有 .debug 段,没有 -g 的为 0
    [ ] use_greet.c 不加 -I 编不过,加 -Ihdr 能编能跑
    [ ] -l 放 main.o 之前 undefined reference,之后链接成功
    [ ] -static 产物 ldd 说 not a dynamic executable,体积大一个数量级
    [ ] -nostartfiles 链接只报警告,产物一跑 exit 139
    [ ] gcc -M main.c abc.dep 报错退出 1,清单只打 stdout
    [ ] -Wp,-MD 的清单目标名按源文件推导,不理会 -o

    注错见红:把 check.sh 里 subst 的期望结果改一个字母、或把判据命令
    里的 -Wall 去掉,对应判据必须 FAIL(2026-10-20 已逐条验证)。

## 10 回看

| 问题 | 答案 | 证据在哪节 |
|---|---|---|
| gcc 每一步在干什么 | `-v` 看见 cc1、as、collect2 | 1.1 |
| 怎么停在中途 | `-E` / `-S` / `-c`，后缀决定起点 | 1.2、1.3 |
| 警告怎么管 | `-Wall -Wextra` 开检查，`-Werror` 定纪律 | 2 |
| 优化和调试怎么取舍 | 发布 `-O2`，调试 `-O0 -g`；多个 -O 最后一个生效 | 3 |
| 头文件去哪找 | 默认列表 + `-I`；`gcc -E -v` 能问出来 | 4.1、4.2 |
| 交叉编译有什么不同 | 只换命令名；ABI 不对链接器拒收 | 5 |
| undefined reference 从哪来 | `-l` 放错了位置：归档扫描不回头 | 6.1 |
| 上板为什么 `-static` | 板子库版本老；代价是体积 | 6.2 |
| 运行时找不到库归谁管 | 动态链接器和 `LD_LIBRARY_PATH`，不归 `-L` | 4.3、6.3 |
| 依赖清单怎么来 | `-M` 只打 stdout，`-MMD -MP` 落成 `.d` | 7.2 |

## 11 带走

开头三个问题的答案：

1. **停点**：`-E`（预处理）、`-S`（编译）、`-c`（汇编）三个停点，
   不给 `-o` 时产物名按源名换后缀；`-v` 打印内部每一步调用的程序。
2. **三套路径**：`-I` 管编译期头文件，`-L`/`-l` 管链接期库，
   `LD_LIBRARY_PATH` 管运行期动态库。报错对号入座：fatal error 找不到
   头文件是编译期，undefined reference 是链接期，error while loading
   shared libraries 是运行期（退出码 127）。
3. **取舍**：`-Wall -Wextra -Werror` 是纪律组合；发布 `-O2`，调试
   `-O0 -g`；静态链接用 51 倍体积换"不挑板子的库版本"。

看到什么先想到什么：

| 看到 | 先想到 |
|---|---|
| `No such file or directory`（头文件） | `-I`，或去查 4.2 的默认列表 |
| `undefined reference to 'xxx'` | 没链上：库没给、`-l` 位置错、或 `.o` 漏了 |
| `error while loading shared libraries` | 运行时路径：`ldd` 看哪条 not found |
| `cannot find -lxxx` | `-L` 没给对，或库没编出来 |
| `uses VFP register arguments` | 浮点 ABI 混了，5.3 节 |
| `warning: unused ...` | `-Wall` 在干活；本仓 Project 里这会直接编不过 |
| 行号乱跳、变量"optimized out" | 带着 `-O2` 在调试，换 `-O0 -g` |

## 12 接下来

- [02 GCC 编译器的使用](../tutorials/01_应用编程/02_GCC编译器的使用.md)：
  四步的原理与实验，本篇是它的选项索引
- [06 make 的语法与函数](06_make的语法与函数.md)：`-MMD -MP` 生成的
  `.d` 在那里被 `-include` 吃回去
- [00 从源码到运行](00_从源码到运行.md)、[05 静态库、动态库与符号](05_静态库动态库与符号.md)：
  四步与链接的机制本身

## 附：实验文件

本篇所有命令在 `Knowledge/labs/00_basics/12_gcc_make_options/` 下执行，
文件清单：

```text
main.c sub.c sub.h     两文件程序（停点、链接、依赖演示）
warn.c                 未用变量 + 符号比较（警告演示）
opt.c                  square + 两次 printf（优化演示）
hdr/greet.h            只定义一个宏 GREETING（-I 演示）
use_greet.c            #include <greet.h>（-I 演示）
f_add.c f_main.c       浮点加法（-marm/-mthumb/-mfloat-abi 演示）
ver.c                  #ifdef VERSION（-D/-U 演示）
check.sh               全部判据，从源码重建一切再逐条核对
```
