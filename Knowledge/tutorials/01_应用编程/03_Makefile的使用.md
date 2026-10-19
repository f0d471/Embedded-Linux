# 03 Makefile 的使用

    原书    第四篇 第 3 章，PDF 154-165 页（语法与函数的罗列部分已提取为
            fundamentals/14_make的语法与函数.md，本篇正文只讲原理与实验）
    视频    4_3-1 到 4_3-7 共 7 集——知识已全部融入本篇，不必再看
    源码    $Q\04_...\source\04_2018Makefile（视频 4_3-2 起实际用的目录，不是
            口播的 03_Makefile）、05_general_Makefile（通用 Makefile）
    实验    Knowledge/labs/03_makefile/（本篇所有"本机实测"均为 2026-10-16 在
            WSL Ubuntu 26.04 / gcc 15.2.0 / GNU Make 4.4.1 真跑）

---

**前置基础**：看懂本篇需要下面的底子。开读前扫一眼，缺哪条先补哪条；
标了"用到再读"的可以等正文引用时再翻。

- 前一章 [02 GCC 编译器的使用](./02_GCC编译器的使用.md)：make 规则的原料就是
  02 章 §2.2"分开编再链接"的那三条命令；没读它，§1 的规则在讲什么不知道
- 再往前 [01 HelloWorld 背后没那么简单](./01_HelloWorld背后没那么简单.md)：
  02 章的前置同样适用（四步、退出码、交叉编译）
- 清单 [14 make 的语法与函数](../../fundamentals/14_make的语法与函数.md)：
  语法与函数的罗列已提取出来，正文只讲原理与实验，用到去查

**这一章在整机里的位置**：上接 02 篇（规则的原料就是那三条 gcc 命令），下接 04 篇
（文件 IO 的实验与 Project 的构建）。它补的零件是"多文件构建、只重编该编的"；
Project 的 Makefile 和 check.sh 的构建段就是它。

**不学它会怎样**：手敲 gcc 必漏文件；改了头文件不重编，会编出一个能跑但行为
错误的程序；加一个文件要改多处命令；`clean` 用 wildcard 写会留下孤儿 `.o`/`.d`
（坑 6），下次全量重编还找不到原因。

## 0 这一章解决什么问题

### 0.1 先看结果：三次 make

本机实测（2026-10-16）：

```text
$ make
gcc -c -o main.o main.c
gcc -c -o math_ops.o math_ops.c
gcc -c -o display.o display.c
gcc -o app main.o math_ops.o display.o
$ ./app
1 + 2 = 3
hello, makefile

$ make
make: 'app' is up to date.

$ touch config.h && make          # 只重链接,这正是要治的病
```

第一次四行，第二次一句 `up to date`，碰一下头文件却只重链接。本章三层递进
就是治最后这个病：模式规则解决"文件多"，自动依赖解决"头文件漏编"。

### 0.2 这一章为什么存在

一句话：**make 不理解 C，也不理解编译。它只会做一件事：比较两个文件的时间戳。**

视频 4_3-1 用 Visual Studio 演示了"点鼠标编译、只重编改过的文件、一键清理"，
然后点破：**这些图形工具背后就是 Makefile**。Linux 下没有那层图形外壳，
你要直接面对它。内核三四万个文件，改一个头文件不能全量重编半小时；
改了头文件却不重编，会编出一个能跑但行为错误的程序。make 把这两件事
都变成机械判断。

从"比时间戳"这条公理出发，整章就是三层递进，每一层解决上一层的遗留问题：

| 层次 | 做法 | 解决什么 | 仍有什么问题 |
|---|---|---|---|
| 一 | 手写每一条规则 | make 能按依赖构建 | 一千个文件要写一千条 |
| 二 | 模式规则 `%.o: %.c` + 变量 + 函数 | 一条规则覆盖同类文件 | 依赖表仍漏掉 `.h` |
| 三 | 让编译器吐出依赖（`.d`） | 头文件变化也触发正确重编 | （没有第三层的 Makefile 有隐蔽 bug） |

执行条件永远只有两条：**目标文件不存在，或任意一个依赖比目标新。**

| `main.c`（依赖）mtime | `main.o`（目标）mtime | make 的决定 |
|---|---|---|
| 10:00:05 | 10:00:07 | 依赖比目标旧，不重编 |
| 10:00:09 | 10:00:07 | 依赖比目标新，重编 |

比的是 mtime 不是内容，所以 `touch` 一个没改的文件会触发重编、改了又改回来
照样重编（这也是 ccache 存在的理由：它在 gcc 前面加一层内容哈希缓存，
内容没变直接吐上次的 `.o`；你机器上已装）。

### 0.3 怎么读这一章

    只想先看见结果   0.1 → 1（规则）→ 4（mini_proj 五步）
    完整学一遍       1 → 3 → 4；5 是通用 Makefile，6 对账 Project
    选读，第二轮再看 5（通用递归构建，读懂内核要用）、6（落进 Project，可先跳）

---

## 1 层次一：规则

规则的形状，整个 Makefile 体系只有这一种原子：

```make
目标: 依赖1 依赖2 ...
<TAB>命令
```

**命令前面必须是一个 TAB 字符，不能是空格。** 这是 Makefile 最著名的坑，
报错 `missing separator`；编辑器默认可能把 TAB 转空格，给 Makefile 单独设。

把 02 篇第 2 节"分开编再链接"的三条命令写成规则（mini_proj 第 1 步的雏形，
`Knowledge/labs/03_makefile/mini_proj/`，六个文件：main.c、math_ops.c/.h、
display.c/.h、config.h）：

```make
app: main.o math_ops.o display.o
	gcc -o app main.o math_ops.o display.o

main.o: main.c
	gcc -c -o main.o main.c

math_ops.o: math_ops.c
	gcc -c -o math_ops.o math_ops.c

display.o: display.c
	gcc -c -o display.o display.c
```

`make` 不带参数时生成**第一条规则的目标**，并递归地先满足它的依赖：
要 `app` 先要 `main.o`，要 `main.o` 先看 `main.c` 的时间戳。
`make 目标名` 指定生成谁，`make clean` 就是这么工作的。

本机实测，首次 make 与紧接着再 make：

```text
$ make
gcc -c -o main.o main.c
gcc -c -o math_ops.o math_ops.c
gcc -c -o display.o display.c
gcc -o app main.o math_ops.o display.o
$ ./app
1 + 2 = 3
hello, makefile

$ make
make: 'app' is up to date.
```

改一个源文件再 make，只有它重编（下面改 display.c 同 touch config.h 的效果，
3.3 节有更关键的头文件版本）：

```text
$ touch config.h && make        # 3.4 节之前,这条只会重链接,这正是要治的病
```

---

## 2 层次二：模式规则、自动变量、变量、假想目标

### 2.1 模式规则与三个自动变量

一千个文件写一千条规则显然不行。模式规则用 `%` 通配：

```make
%.o: %.c
	gcc -c -o $@ $<
```

两边的 `%` 匹配同一段文字：要生成 `main.o` 时，`%` 匹配到 `main`，
依赖就是 `main.c`。三个自动变量：

    $@   目标
    $<   第一个依赖
    $^   全部依赖(去重)

**编译用 `$<`、链接用 `$^`**：编译一次只喂一个 `.c`；链接要把所有 `.o`
一起喂。这个区别在 3.4 打开自动依赖之后变成硬约束——那时 `$^` 里会混进
`.h`，喂给 gcc 直接出错。

### 2.2 变量：即时与延时

四种赋值（完整语义见 14 篇）：

    :=    即时变量:定义那一刻求值,以后右边再变也不影响它
    =     延时变量:用到的时候才求值
    ?=    延时变量,且只在该变量从未被定义过时才生效
    +=    追加;是即时还是延时,取决于前面那次定义

即时和延时的差别，一行实验看清（2026-10-16 实测）：

```make
A := $(C)
B  = $(C)
C := abc
all:
	@echo A=$(A) B=$(B) C=$(C)
```

```text
$ make
A= B=abc C=abc
```

A 定义那一刻 C 还是空的，永远空；B 用到时才去取，拿到 abc。make 会先把整个
Makefile 读完再执行，所以 C 写在后面对 B 没影响、对 A 有影响。
`?=` 和 `+=` 同场实测：

```text
D := 100ask
D ?= weidongshan        # 已定义,不生效
E ?= first              # 首次定义,生效
=>  D=100ask E=first

X := abc
X += def
=>  X=abc def
```

**延时变量不能自引用**：`Y = $(Y) foo` 直接炸——

```text
Makefile:1: *** Recursive variable 'Y' references itself (eventually).  Stop.
```

改成 `Y := $(Y) foo` 即可：即时变量求值那一刻用的是旧值。
（视频 4_3-4 的 8:19 和 4_3-5 的 13:18 各踩了一次。）

另外，命令行变量优先于 Makefile 内的赋值（`?=` 挡不住它）：
`make CROSS=arm-linux-gnueabihf-` 能覆盖文件里的 `CROSS ?=`，mini_proj
第 5 步就靠它。命令行加 `@` 前缀的命令不回显（`@echo` 只出结果不出命令）。

### 2.3 假想目标：clean 的那个坑

```make
clean:
	rm -f *.o app
```

平时能用。但目录里若恰好有一个**名字叫 `clean` 的文件**——目标存在、
没有依赖可比、于是"最新"——实测（2026-10-16）：

```text
$ touch clean && make clean
make: 'clean' is up to date.
```

删掉 clean 文件当然可以，正解是声明它**不是文件**：

```make
.PHONY: clean
clean:
	rm -f *.o app
```

```text
$ make clean
cleaning
```

`.PHONY` 告诉 make：别比时间戳，无条件执行。`all` 同理要声明。

---

## 3 层次三：自动头文件依赖（分水岭）

**这一层是全章最重要的一节**，视频 4_3-5 整集讲它。

问题：`display.o: display.c` 这条规则里没有 `config.h`，而 display.c
确实 include 了它。

| 关系来源 | make 知道的依赖 |
|---|---|
| 手写规则 | `display.o → display.c` |
| 真实 include 关系 | `display.o → display.c → config.h` |

于是改了 `config.h` 里的宏，make 沿它知道的那条边看：display.c 没变、
display.o 最新、不重编。实测（mini_proj 第 4 步之前的状态就是如此，
3.5 节注错一复现）：

```text
$ touch config.h && make
gcc display.o main.o math_ops.o -o app        # 只重链接,不重编 display.o
$ ./app
hello, makefile                                # 改了宏输出也不变
```

**这是最难查的一类 bug**。原书式的具体场景：

| 文件 | 情况 | 对 `struct point` 的理解 |
|---|---|---|
| config.h | `{ int x, y; }` 改成 `{ int x, y, z; }` | 定义已变为 12 字节 |
| display.o | 没重编 | 仍按 8 字节算 `sizeof` |
| main.o | 重编过 | 按 12 字节解释 |

两边对同一块内存的理解不同。编译零警告，运行表现诡异。
手写全依赖不可能（内核几万个文件谁帮你列），解法是**让编译器自己吐**：

    gcc -M  c.c              打印完整依赖(含系统头),只打印不编译
    gcc -MM c.c              同上,跳过系统头
    gcc -MD -c -o c.o c.c    边编译边把依赖写进 c.d
    gcc -MMD -c -o c.o c.c   同上,跳过系统头
    gcc -MD -MP ...          再给每个头补一条空规则,防"删了头文件"报死

生成的 `c.d` 内容就是一行普通规则：`c.o: c.c config.h`。
Makefile 用 `-include` 把全部 `.d` 读回来，依赖表就齐了。

**原书勘误**（13 篇已记，这里复述一句）：PDF 136 写的
`gcc -M main.c abc.dep` 照敲报错，`-M` 的清单只打在 stdout；
落到文件用 `-MD`。

**两个坑**：

1. **`-include` 而不是 `include`**。首次 make 时 `.d` 还不存在，
   `include` 直接报错；`-include` 文件不存在就跳过。
   （教材另一写法是先 `$(wildcard ...)` 过滤再 `include`，等价，见 3.6 的引擎。）
2. **空命令规则**。视频 4_3-5 的 3:54 现场踩的：手工加
   `display.o: display.c config.h` 后面跟一个只有 TAB 的空行——
   TAB 后面什么都不写也是一条命令（空命令），它会**覆盖掉模式规则**，
   导致 display.o 永远不重编。删掉那个 TAB。

---

## 4 [做 L3] mini_proj：五步把 Makefile 长出来

工程在 `Knowledge/labs/03_makefile/mini_proj/`（最终形态已入库）。
五个 Makefile 形态，每步都能单独跑、单独验。**照着一步一步敲，别一步抄 final。**

**第 1 步 全部写死**——1.1 节那四条编译加一条链接，零变量零模式规则。

    [验] make 出可执行文件能跑。
    [感受] 加一个文件要改两处。这是后面四步要治的病。

**第 2 步 变量与模式规则**——CC/CFLAGS 提成变量，四条编译规则塌缩成一条：

```make
CC     := gcc
CFLAGS := -O2 -Wall -Wextra
OBJS   := main.o math_ops.o display.o

app: $(OBJS)
	$(CC) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<
```

    [验] make clean && make,产物照跑。

**第 3 步 自动收集源文件**：

```make
SRCS := $(wildcard *.c)
OBJS := $(SRCS:.c=.o)
```

    [验] 新建 extra.c 并在 main.c 里调它,不改 Makefile,make 必须成功。
    本机实测(2026-10-16):make 自动多出一条 gcc -c -o extra.o extra.c,
    程序打出 3*4=12。
    [代价] wildcard 只认"现在存在"的文件:把 extra.c 删掉再 make clean,
    rm 的清单里没有 extra.o/extra.d——它们成了孤儿,永久留在目录里。
    实测 clean 后 ls -A 仍见 extra.d extra.o。所以本仓 Project 的 clean
    用 find -name '*.o' 扫全目录,不用 $(OBJS)。

**第 4 步 头文件自动依赖**——编译加 `-MMD`，结尾 `-include $(DEPS)`：

```make
DEPS := $(OBJS:.o=.d)
%.o: %.c
	$(CC) $(CFLAGS) -MMD -c -o $@ $<

-include $(DEPS)
```

    [验] 改 config.h 的 BANNER_TEXT,display.o 必须重编,输出跟着变。
    本机实测:改宏后 make 恰好重编 1 个文件(display.c)再链接,输出变新值;
    改回来,又只重编 display.o。

**第 5 步 交叉编译**：

```make
CROSS ?=
CC := $(CROSS)gcc
```

    [验] make clean && make CROSS=arm-linux-gnueabihf-,file 显示 ARM。
    本机实测:app: ELF 32-bit LSB pie executable, ARM, EABI5 ...

**[判] 五条判据，逐条注错见红**（2026-10-16 全部实测通过）

    [ ] 1  make 后能跑,输出 1 + 2 = 3 / hello, makefile
    [ ] 2  改 config.h,恰好重编 display.o 再链接,输出跟着变
           注错:把 -include 那行注释掉,再改 config.h =>
                make: 'app' is up to date.,输出还是旧值
                (本机实测原样输出如上;见到它才算真懂第 3 层)
    [ ] 3  新建 extra.c 并调它,不改 Makefile,make 成功
           注错:把 wildcard 换成写死清单,新文件编不进去,
                链接报 undefined reference
    [ ] 4  make CROSS=arm-linux-gnueabihf- 后 file 显示 ARM
           注错:CC 写死成 gcc,产物变回 x86
    [ ] 5  make clean 后目录里没有 .o .d 和可执行文件(用 ls -A 查,
           孤儿产物除外——见第 3 步的[代价],顺手体会 clean 用 find 的理由)

---

## 5 [做 L3] 通用 Makefile：内核那套递归构建

视频 4_3-6 教使用，4_3-7 教实现。工程复现在
`Knowledge/labs/03_makefile/proj/`，与资料仓 `05_general_Makefile` 同思想。

**为什么必须学**：本仓 `Project/` 没用这套（理由见第 6 节），但 Linux 内核
和 U-Boot 的构建就是这套，第 2 阶段读内核 Makefile 躲不开。视频原话：
"以后我们来分析内核、分析 U-Boot 时，才需要对 Makefile 有更加深刻的理解。"

### 5.1 设计思想，三条

    1. 每个目录一份 Makefile,只声明一个变量 obj-y:
           obj-y += main.o
           obj-y += a/          结尾带斜杠的是子目录
       引擎靠结尾斜杠区分"这一项是文件还是目录"。

    2. 顶层一份 Makefile.build 是递归引擎,make -f 反复调它,一次处理一个目录。

    3. 每个目录的 .o 用 ld -r 合并成 built-in.o,子目录的再并进上层,
       最后顶层 built-in.o 链接成程序。

| 合并阶段 | 输入 | 输出 |
|---|---|---|
| 子目录 `a/` | sub2.o、sub3.o | `a/built-in.o` |
| 顶层 | main.o、sub.o、`a/built-in.o` | 顶层 `built-in.o` |
| 最终链接 | 顶层 `built-in.o` | app |

`ld -r` 是**可重定位合并**：不做最终链接，只把一堆 `.o` 打包成一个 `.o`。
这样顶层的链接命令永远只有 `gcc -o app built-in.o` 一行。它不需要知道
三层深的目录里有什么。

### 5.2 两个文件，全文

顶层 `proj/Makefile`：

```make
CROSS_COMPILE ?=
AS  := $(CROSS_COMPILE)as
CC  := $(CROSS_COMPILE)gcc
LD  := $(CROSS_COMPILE)ld

TOPDIR := $(shell pwd)
export AS CC LD TOPDIR

TARGET := app

obj-y += main.o
obj-y += sub.o
obj-y += a/          # 结尾带斜杠的项是子目录,引擎靠它区分文件与目录

all: start_recursive_build
	$(CC) -o $(TARGET) built-in.o

# 规则文件不在本文件里:-f 显式指定引擎;引擎每个目录被调一次
start_recursive_build:
	$(MAKE) -f Makefile.build

clean:
	rm -f $(shell find . -name '*.o') $(shell find . -name '.*.d') $(TARGET)

.PHONY: clean
```

引擎 `proj/Makefile.build`：

```make
# 注意 两个复现时真实踩到的坑,见 5.3
.DEFAULT_GOAL := __build
PHONY := __build

obj-y        :=
subdir-y     :=
EXTRA_CFLAGS :=

CFLAGS := -I$(TOPDIR)/include -MMD -MP

include Makefile

# obj-y 拆两半:带斜杠的是子目录,其余是本目录的 .o
subdir-y     := $(filter %/, $(obj-y))
subdir-y     := $(patsubst %/,%,$(subdir-y))
subdir_objs  := $(filter %/, $(obj-y))
subdir_objs  := $(patsubst %/,%/built-in.o, $(subdir_objs))
cur_objs     := $(filter-out %/, $(obj-y))

dep_files := $(foreach f, $(cur_objs), .$(f).d)
dep_files := $(wildcard $(dep_files))
ifneq ($(dep_files),)
  include $(dep_files)
endif

.PHONY: $(subdir-y)
$(subdir-y):
	$(MAKE) -C $@ -f $(TOPDIR)/Makefile.build

# built-in.o:本目录 .o + 子目录 built-in.o 用 ld -r 可重定位合并
built-in.o: $(cur_objs) $(subdir_objs)
	$(LD) -r -o $@ $^

# 编译规则:CFLAGS(全局) + EXTRA_CFLAGS(目录) + CFLAGS_<文件>(单文件)
%.o: %.c
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) $(CFLAGS_$@) -Wp,-MD,.$@.d -c -o $@ $<

__build: $(subdir-y) built-in.o
	@:

.PHONY: $(PHONY)
```

子目录 `a/Makefile`（演示按目录、按单文件设选项）：

```make
obj-y += sub2.o
obj-y += sub3.o

EXTRA_CFLAGS := -DDEBUG            # 本目录每个 .c 都带
CFLAGS_sub3.o := -DDEBUG_SUB3      # 只有 sub3.o 带
```

### 5.3 复现时真实踩到的两个坑（视频里没有，本仓实踩）

**坑一：默认目标被 include 抢走。** 引擎在 `include Makefile` 之前如果
没有一条**规则**（变量不算），make 的默认目标就是 include 进来的顶层
Makefile 的 `all`——于是引擎去跑 `all → start_recursive_build →
make -f Makefile.build → 引擎 → all → ...` 无限递归。本机实测炸到
七千多层才停（`Resource temporarily unavailable`）。修法：引擎第一行
`.DEFAULT_GOAL := __build` 把默认目标钉死。

**坑二：规则的依赖是读取时立即展开。** `__build: $(subdir-y) built-in.o`
如果写在过滤语句**之前**，`$(subdir-y)` 展开时还是空的，子目录永远不会
被递归——报错是顶层引擎里 `No rule to make target 'a/built-in.o'`
（顶层规则要它，却没人去造它）。修法：`__build` 规则写在过滤之后。

这两条合起来就是这套引擎的阅读钥匙：**变量在 include 之后才填，
规则在变量填完之后才写，默认目标一开始就钉死。**

### 5.4 [判] 六条判据（2026-10-16 全部实测通过）

首次 make 的完整输出（分层与合并一目了然）：

```text
$ make && ./app
make -f Makefile.build
make[1]: Entering directory '.../proj'
make -C a -f .../Makefile.build
make[2]: Entering directory '.../proj/a'
gcc ... -DDEBUG              -Wp,-MD,.sub2.o.d -c -o sub2.o sub2.c
gcc ... -DDEBUG -DDEBUG_SUB3 -Wp,-MD,.sub3.o.d -c -o sub3.o sub3.c
ld -r -o built-in.o sub2.o sub3.o
make[2]: Leaving directory '.../proj/a'
gcc ... -Wp,-MD,.main.o.d -c -o main.o main.c
gcc ... -Wp,-MD,.sub.o.d  -c -o sub.o sub.c
ld -r -o built-in.o main.o sub.o a/built-in.o
make[1]: Leaving directory '.../proj'
gcc -o app built-in.o
sub
sub2
sub2 debug
sub3 magic=3
sub3 debug
sub3 debug only
```

    [ ] 1  make 出 app 能跑;输出里 sub2/sub3 带 debug 行(EXTRA_CFLAGS 生效)
    [ ] 2  sub3 的编译命令有 -DDEBUG_SUB3,sub2 的没有(对账上面两行 gcc)
    [ ] 3  touch include/sub3.h && make:只有 sub3.o 重编,然后两层 ld -r 重新
           合并、重新链接(实测输出:仅一条 gcc -c sub3.c)
    [ ] 4  find . -name built-in.o 恰好两个:a/ 一个,顶层一个
    [ ] 5  make CROSS_COMPILE=arm-linux-gnueabihf- 后 file 显示 ARM
    [ ] 6  注错见红:删掉 a/Makefile 里 obj-y += sub2.o 一行,
           make clean && make 必须报 undefined reference to `sub2_print'
           (实测原样报错)。照样能链上说明你的 built-in.o 是别的方式收的,回去查

---

## 6 落进 Project：本章知识在真实工程里的样子

`Project/` 的构建系统就是本章的落地。**读 `Project/Makefile`，
确认每个记号在真实工程里长什么样**（行号以当前文件为准，用
`grep -n` 对一遍再引用）：

| 本章学的 | Project/Makefile 里的样子 |
|---|---|
| `?=`/`:=`（2.2） | `CROSS ?=` 与 `CC := $(CROSS)gcc` |
| wildcard + foreach（2.2/14 篇） | `SRCS := $(wildcard *.c) $(foreach d,$(SUBDIRS),$(wildcard $(d)/*.c))` |
| patsubst（14 篇） | `OBJS := $(patsubst %.c,$(BUILD)/%.o,$(SRCS))` |
| 自动依赖（3） | 编译命令里的 `-MMD -MP` + `-include $(deps)` |
| 函数 if/subst/firstword | `ARCH := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),x86)` |

看变量取值的现成入口：

```text
$ make show | head -2                     # 本机实测 2026-10-16
ARCH  = x86
CC    = gcc
$ make CROSS=arm-linux-gnueabihf- show | head -2
ARCH  = arm
CC    = arm-linux-gnueabihf-gcc
```

两条自动化注错已经在 `Project/check_core.sh` 里（`[3r]`、`[4r]`）：
SRCS 换写死清单、去掉 `-MMD -MP`。手工在 project 里做一遍这两个注错
（做完 `git checkout Project/Makefile` 还原），对应本章 4 的判据 3 与判据 2。

**为什么 project 没用第 5 节那套**：它的三项能力（任意深目录、按目录设
选项、按单文件设选项）当前一项用不上，代价却是构建过程分散在多个文件。
完整权衡在 Engineering/Todo/学习与项目路线.md 第十一节。
这不影响第 5 节实验的必要性，学它是为了读懂内核。

---

## 7 自检问题

答不上来就回到对应小节重读。这些问题都能用命令验证，不要凭印象答。

    1. make 判断要不要执行一条规则，依据是什么？看内容还是看时间戳？
       touch 一个没改的文件会发生什么？                              (0)

    2. 命令行前面必须是什么字符？用错报什么错？                       (1)

    3. $@ $< $^ 分别是什么？为什么编译规则用 $< 而链接用 $^？
       打开自动依赖之后用 $^ 会出什么问题？                           (2.1 3)

    4. := 和 = 有什么区别？A := $(C)、B = $(C)、C := abc 时
       A、B 各是什么？为什么 C 写在后面不影响 B？                     (2.2)

    5. Y = $(Y) foo 会发生什么？为什么 := 就没事？                    (2.2)

    6. 目录里有一个叫 clean 的文件，make clean 会怎样？怎么解决？      (2.3)

    7. 不做自动头文件依赖，什么情况下会编出一个能编过但行为错误的程序？
       描述 struct 字段增减的具体场景。                               (3)

    8. -MD 和 -MMD 差在哪？-MP 解决什么场景下的什么问题？
       为什么必须用 -include 而不是 include？                         (3 4)

    9. 通用 Makefile 靠什么区分 obj-y 里的一项是文件还是目录？
       built-in.o 怎么层层合并？顶层链接命令为什么永远只有一行？        (5.1)

   10. 复现那套引擎时踩到的两个坑（默认目标、依赖展开时机）各是什么？
       各怎么避免？                                                   (5.3)

   11. wildcard 收集源文件有什么收益和代价？
       （提示：加文件不改 Makefile 是收益；孤儿产物、废弃 .c、
       带 main 的测试文件是三类代价）                                 (4)

---

## 8 已知的坑

    坑 1  命令行必须 TAB 缩进。编辑器把 TAB 转成空格就报 missing separator。
          给 Makefile 单独设成 TAB。                                   (1)

    坑 2  一条规则后面跟一个只有 TAB 的空行,它是"空命令规则",
          会覆盖模式规则,目标永远不重新生成。视频 4_3-5 现场踩过。       (3)

    坑 3  延时变量不能自引用(X = $(X) foo),报 Recursive variable;
          改成即时变量 X := $(X) foo。                                 (2.2)

    坑 4  首次 make 时 .d 还不存在:用 include 会直接报错,
          用 -include 或先 wildcard 过滤。                             (3)

    坑 5  验证"自动依赖生效"必须先完整 make 一次再 touch 头文件;
          顺序错了量到的是"产物不存在所以全编",跟依赖无关。              (4)

    坑 6  wildcard 版 clean 扫不到已删源文件的孤儿 .o/.d;
          干净的 clean 用 find -name '*.o' 全目录扫(project 就是这么写的)。(4)

    坑 7  在 /mnt/e 下(Windows 盘)mtime 精度和 IO 都差,遇到"改了却不重编"
          把工程挪到 ~ 下试。Project/check.sh 把工程复制进 /tmp 再跑,
          原因之一就是这个。                                           (0)

    坑 8  wildcard 误收一个带 main() 的测试文件,链接报
          multiple definition of main,报错信息不直观。                 (4)

    坑 9  复现通用 Makefile 引擎:默认目标会被 include 进来的 Makefile 抢走
          (无限递归),规则写在变量过滤之前则子目录永远不被递归。
          钉 .DEFAULT_GOAL + 规则放过滤之后。                          (5.3)

---

## 9 这一章交出了什么

现在能独立做到：

- 写一条规则（目标、依赖、命令），并说得出 make 只比 mtime 不比内容
- 用模式规则、自动变量、变量把一千条规则收成几条
- 用 `-MMD -MP` 生成 `.d`，让头文件变化也触发正确重编
- 按五步把 mini_proj 的 Makefile 长出来，每一步的判据都注错见红
- 看懂 Project 的 Makefile，知道加一层、加一个文件要改哪里
- 复现通用 Makefile 引擎，说清 `.DEFAULT_GOAL` 与规则位置两个坑

还不能做：

- autotools / CMake 这类构建生成器（不在本阶段）
- 内核 Kbuild 的全貌（第 2 阶段）
- 第三方库的 `configure` 交叉构建（第 06 篇、fundamentals/12）

这一章在整机里的位置：它是 01、02 两篇的自动化。04～11 篇的实验都用它，
Project 的构建系统与 check.sh 也从这里来（选择与代价见 TechReports 01）。

下一章：[04 文件 IO](04_文件IO.md)。
