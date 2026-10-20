# 06 make 的语法与函数

    实验    Knowledge/labs/00_basics/12_gcc_make_options/mk/
            另用 Knowledge/labs/03_makefile/ 下的 pat 式小工程
    电脑    WSL Ubuntu 26.04，GNU Make 4.4.1
            （本篇"本机实测"均为 2026-10-20 实跑）

Makefile 只有一种原子：**规则**（目标、依赖、TAB 开头的命令）。变量和函数
存在的意义是让规则写得短、写得全。这一篇是清单型篇目：教程 03 篇讲
"为什么这样写"的推导，这里把写法本身按问题分七组收全，每组先给问题，
再给能跑通的最小演示和真实输出，最后给本组清单。清单条目标注依据：
"实测 2026-10-20" 是本机 GNU Make 4.4.1 跑过的，"GNU make 手册"是查
官方文档登记的。

---

## 你会在哪里撞见它

- 敲 `make` 报 `Makefile:2: *** missing separator.  Stop.`（第 1.2 节：
  命令行前面那个字符必须是 TAB）。
- 目录里恰好有个文件叫 `clean`，`make clean` 回答 `up to date`，什么都没删
  （第 1.3 节）。
- 改了头文件，程序却没有重编（头文件依赖要靠 `-MMD` 加 `-include`，
  04 篇 7.2 节与本篇第 7 节合起来是它的完整机制）。
- 打开 [Project/Makefile](../../Project/Makefile)，前 40 行里就有
  `?=`、`:=`、`$(if ...)`、`$(firstword $(subst -, ,...))`、`$(wildcard)`、
  `$(foreach)`、`$(patsubst)`、`$(filter-out)`，全是本篇第 2、6 节的条目。

## 这篇要回答的问题

1. 一条规则由哪几部分组成，make 凭什么决定执不执行命令？
2. 五种变量赋值各在什么时刻展开，命令行、文件、环境变量谁覆盖谁？
3. 自动变量和函数怎么把依赖清单写短、写全？

## 0 先查三条

清单型篇目，不设起步实验。先按要解决的问题定位到某一节：

| 你要解决 | 去第几节 |
|---|---|
| 规则写法、执行条件、clean 不干活、默认目标 | 1 |
| 变量展开时机、覆盖优先级、传给子目录 | 2 |
| `$@` `$<` `$^` 各是什么 | 3 |
| `%.o: %.c` 怎么匹配、没有规则 make 也会编 | 4 |
| 按条件选分支 | 5 |
| 查某个函数的行为 | 6 |
| 命令行参数、递归子目录、本仓工程实例 | 7、8 |

---

## 1 规则与目标

### 1.1 规则的三部分与命令执行的两个条件

一条规则长这样：

```make
目标(target) ... : 依赖(prerequisites) ...
<TAB>命令(command)
```

- 目标通常是要生成的文件名，也可以是一个动作名（如 `clean`）。
- 依赖是产生目标要用的材料；一个目标可以有多个依赖，也可以没有。
- 命令是生成目标时交给 shell 执行的动作，可以有多行，**每行的第一个
  字符必须是 TAB**。

make 决定是否执行命令的条件只有两个：**目标文件还不存在**，或
**某个依赖文件比目标新**（比修改时间戳）。

用 labs 里的小工程看全过程。`mk/pat/` 下有三个 `.c` 和这样一份 Makefile：

```make
app: main.o a.o b.o
	gcc -o $@ $^

%.o: %.c
	gcc -c -o $@ $<

clean:
	rm -f *.o app

.PHONY: clean
```

连续四次操作，本机实测：

```text
$ make
gcc -c -o main.o main.c
gcc -c -o a.o a.c
gcc -c -o b.o b.c
gcc -o app main.o a.o b.o
$ make
make: 'app' is up to date.
$ touch a.c && make
gcc -c -o a.o a.c
gcc -o app main.o a.o b.o
$ make -n
（只打印将执行的命令，不执行）
```

对着条件读：

1. 第一次：`app`、`main.o` 等都不存在，四条命令全跑。make 先把
   `main.o a.o b.o` 当作"依赖目标"各自找到 `%.o: %.c` 规则生成，最后才
   执行链接。
2. 第二次：什么都不动，`app` 比所有 `.o` 新，每个 `.o` 又比各自的 `.c`
   新，没有一条命令满足执行条件。
3. `touch a.c` 只刷新了 `a.c` 的时间戳：只有 `a.o` 重编，然后 `app`
   因为 `a.o` 变新而重新链接。`main.o`、`b.o` 纹丝不动。**这就是
   Makefile 存在的意义：只重做受影响的部分。**
4. `-n` 预演：把将执行的命令打印出来但不执行，排查 Makefile 的第一工具。

### 1.2 第一个目标是默认目标；missing separator 是什么

`make` 不带参数时生成**第一个目标**；`make 目标名` 指定生成谁。上面的
Makefile 里 `app` 写在最前，所以裸 `make` 就是 `make app`。

把命令行的 TAB 换成四个空格：

```text
$ make
Makefile:2: *** missing separator.  Stop.
```

`missing separator` 几乎一定是"命令行开头不是 TAB"。make 用 TAB 区分
"这是规则的第几行"和"这是命令"，混进空格就解析不了。

### 1.3 假想目标 .PHONY：同名文件的坑

容易以为"clean 没有依赖，所以命令总会被执行"。实测不一定：

```text
$ printf 'clean:\n\trm -f *.o\n' > Makefile
$ touch clean          <-- 目录里出现一个名叫 clean 的文件
$ make clean
make: 'clean' is up to date.     <-- 什么都没删
```

目标 `clean` 没有依赖，但文件 `clean` 存在且没有比它新的依赖，"依赖比
目标新"这条不成立，"目标不存在"也不成立，于是命令不执行。对策是告诉
make 这个目标不代表文件：

```make
.PHONY: clean
```

加上之后，本机实测 `make clean` 无条件执行命令。本仓约定：所有动作型
目标（`clean`、`test`、`all`、`show`……）都进 `.PHONY`，
Project/Makefile 第 76 行就是这么写的。

### 1.4 默认目标会被 include 进来的文件抢走

`mk/06_default_goal.mk` 的内容：

```make
.DEFAULT_GOAL := all

include 06b_rules.mk          # 里面的第一个目标是 picked_first

all:
	@echo "real default goal runs"
```

本机实测两种写法：

```text
有 .DEFAULT_GOAL：real default goal runs
删掉那一行：      I would steal the default goal
```

make 的默认目标是"读到的第一条规则的目标"。`include` 是在原地展开的，
被包含文件的第一条规则会抢在 `all` 前面被读到。`.DEFAULT_GOAL` 是 GNU
make 的内置变量，显式赋值就把默认目标钉死。这个坑在本仓复现内核式
递归引擎时实踩过：[labs/03_makefile/proj/Makefile.build](../labs/03_makefile/proj/Makefile.build)
第 15 行的 `.DEFAULT_GOAL := __build` 就是防洪堤，文件头部注释记录了
当时的无限递归现象。

另一个等价的老办法：把 `First_target:` 先写在文件前面占位，依赖和命令
在后面再补全（规则可以分多次出现，依赖会累加）。新写的 Makefile 用
`.DEFAULT_GOAL` 更直白。

### 1.5 本组清单

| 写法 | 作用 | 依据 |
|---|---|---|
| `目标: 依赖` + TAB 命令 | 规则的唯一形式 | 实测 2026-10-20 |
| 执行条件 | 目标不存在，或依赖比目标新 | 实测 2026-10-20 |
| `make`（无参数） | 生成第一个目标 | 实测 2026-10-20 |
| `make 目标` | 指定生成谁 | 实测 2026-10-20 |
| `.PHONY: 目标` | 声明目标不是文件，无条件执行 | 实测 2026-10-20 |
| `.DEFAULT_GOAL := 目标` | 显式钉死默认目标 | 实测 2026-10-20 |
| `make -n` | 只打印不执行（预演） | 实测 2026-10-20 |
| `make -j N` | 并行执行（本仓 WSL 限定 -j2 以内） | GNU make 手册；Project/Makefile 第 114 行 |
| TAB 误用为空格 | 报 `missing separator`，退出码 2 | 实测 2026-10-20 |

**这一节搭好的积木**：规则是唯一原子，执行与否只看时间戳和两个条件；
`.PHONY` 和 `.DEFAULT_GOAL` 管住动作目标和默认目标。下一节：变量在
什么时刻被算出值。

---

## 2 变量：五种赋值与两个时刻

### 2.1 现象：同一个 $(C)，有人看见值，有人看见空

`mk/01_vars.mk`（完整文件在 labs，这里看关键行）：

```make
A = $(C)
B := $(C)

G = a
G += $(C)
H := a
H += $(C)

C = later

D = file_value
D ?= second
E ?= first_seen

show:
	@echo "A(=)        = [$(A)]"
	@echo "B(:=)       = [$(B)]"
	...（G H D E 同样打印）
```

本机实测：

```text
A(=)        = [later]
B(:=)       = []
G(= 后 +=)  = [a later]
H(:= 后 +=) = [a]
D(?=)       = [file_value]
E(?=)       = [first_seen]
```

六行各说一件事：

- **A（`=`，延时变量）**：定义时只记住原文 `$(C)`，用到它那一刻才展开。
  那时 `C = later` 已经读进来了，所以 A 是 `later`。定义写在 C 前面
  没关系。
- **B（`:=`，立即变量）**：定义那一刻就展开，此刻 C 还没定义，B 定死
  为空。
- **G、H（`+=` 追加）**：`+=` 沿袭变量原有的延时/立即属性。G 是延时的，
  追加的 `$(C)` 也留着以后算（`a later`）；H 是立即的，追加当场展开，
  C 此刻为空，等于什么也没加上。
- **D（`?=`）**：D 已经定义过，`?= second` 这一句被忽略。
- **E（`?=`）**：E 没定义过，`?=` 生效。

### 2.2 展开时机：读文件与执行命令是两个阶段

延时的底气来自 make 的工作方式：先把整个 Makefile 读完，再执行规则。
画成一条时间线：

```
 读文件阶段(自上而下)                 执行阶段(make show 时)
 -----------------------------       ----------------------
 第1行 A = $(C)     只记原文 "$(C)"
 第2行 B := $(C)    当场展开,C 未定义 -> B := ""
 第9行 C = later    C 定下来
                                    打印 $(A):此刻展开 "$(C)" -> later
                                    打印 $(B):已是死值 ""
```

规则里的命令、规则的依赖列表在读取阶段的处理不同：依赖列表是读取时
立即展开的，命令是执行时才展开的。Makefile.build 注释里记的第二个坑
就来自这条：`built-in.o: $(cur_objs) $(subdir_objs)` 这条规则如果写在
"拆分 obj-y" 的那几行 filter 之前，读到这里时两个变量还是空，子目录
永远不会被递归（[Makefile.build](../labs/03_makefile/proj/Makefile.build)
第 11-13 行的注释）。

延时变量不能引用自己：

```text
$ cat mk/02_selfref.mk
Y = $(Y) foo
...
$ make -f 02_selfref.mk show
mk/02_selfref.mk:2: *** Recursive variable 'Y' references itself (eventually).  Stop.
```

退出码 2。延时变量用到时才展开，展开 `$(Y)` 又得展开 `$(Y)`，make 直接
拒绝。需要"在自己基础上加长"时用 `:=`（右边立即展开，取的是旧值）。

### 2.3 谁覆盖谁：命令行 > 文件 > 环境

同一份 01_vars.mk，三种喂法，本机实测：

```text
文件里 D = file_value：        D = [file_value]
make ... D=from_cmd：          D = [from_cmd]      <-- 命令行压过文件
E=from_env make ...：          E = [from_env]      <-- 环境算已定义,?= 不动它
```

优先级从高到低：**命令行赋值 > 文件内赋值 > 环境变量**。`?=` 的准确语义
是"只在此前完全没定义过时才赋值"，环境变量也算定义过，所以上面 E 没被
`?= first_seen` 覆盖。

命令行变量连文件里的普通赋值都压得住；文件里想强制压过命令行，要用
`override 变量 ...`（GNU make 手册）。Project/Makefile 第 65、68 行的
`override LDLIBS += ...` 就是这个用途：命令行传 `LDFLAGS=-static` 时，
`-pthread` 也保得住。

执行 shell 命令取值用 `$(shell ...)`：`TOPDIR := $(shell pwd)`（配 `:=`，
不然每次用到都重新执行一遍命令）。换行会被折叠成空格。

### 2.4 export：变量传给子目录的 make

`make -C 子目录` 会启动一个新的 make 进程，文件里的变量默认传不过去，
只有 `export` 过的才跟着环境走。`mk/08_export.mk`：

```make
TOPDIR := $(shell pwd)
CC := gcc
export TOPDIR

recurse:
	@$(MAKE) -C sub show
```

本机实测（sub/Makefile 里打印两个变量）：

```text
sub sees TOPDIR=[/tmp/el-f0406-mk] CC=[cc]
```

TOPDIR 传过去了；CC 没 export，子 make 里的 `cc` 是 **make 自己的内置
默认值**，不是顶层那个 `gcc`。容易以为子 make 看到的 `cc` 是顶层传下来
的；实测没 export 就传不下去，看到的只是内置默认。把 `export TOPDIR`
改成 `export TOPDIR CC` 再跑，子 make 才看到 `CC=[gcc]`。

### 2.5 本组清单

| 写法 | 展开时机 / 语义 | 依据 |
|---|---|---|
| `A = xxx` | 延时：使用时展开 | 实测 2026-10-20 |
| `B := xxx` | 立即：定义时展开 | 实测 2026-10-20 |
| `C ?= xxx` | 延时；仅当此前未定义 | 实测 2026-10-20 |
| `D += xxx` | 追加；沿袭原有延时/立即属性 | 实测 2026-10-20 |
| `define X ... endef` | 延时；值可以跨多行 | 实测 2026-10-20 |
| `override X ...` | 压过命令行赋值 | GNU make 手册；Project/Makefile 第 65 行 |
| `make X=1` | 命令行赋值，优先级最高 | 实测 2026-10-20 |
| 环境变量 | 算"已定义"，优先级低于文件内赋值 | 实测 2026-10-20 |
| `export X` | 让子 make 进程可见 | 实测 2026-10-20 |
| `$(shell cmd)` | 执行 shell 命令取值，换行折叠成空格 | 实测 2026-10-20 |
| 延时变量自引用 | 报 `Recursive variable ... references itself`，退出码 2 | 实测 2026-10-20 |

**这一节搭好的积木**：`=`/`:=`/`?=`/`+=`/`define` 五种赋值，延时与立即
之分就是"读文件时"与"执行时"两个时刻之分；命令行优先级最高；跨目录
靠 `export`。下一节：规则里那些不用定义就有值的变量。

---

## 3 自动变量

规则执行时，make 自动填好几个以 `$` 开头的变量，它们的存在让同一条
规则能服务很多个文件。用 `mk/03_autovar.mk` 实测（目标是 `all`，依赖是
三个摸出来的空文件）：

```text
第一次 make（all 不存在）：
$@ = all
$< = a.txt
$^ = a.txt b.txt c.txt
$? = a.txt b.txt c.txt

touch b.txt 之后再 make：
$@ = all
$< = a.txt
$^ = a.txt b.txt c.txt
$? = b.txt                    <-- 只剩"比目标新"的那一个
```

| 记号 | 含义 | 实测 |
|---|---|---|
| `$@` | 本规则的目标 | 实测 2026-10-20 |
| `$<` | 第一个依赖 | 实测 2026-10-20 |
| `$^` | 全部依赖（去重） | 实测 2026-10-20 |
| `$?` | 比目标新的那些依赖 | 实测 2026-10-20 |
| `$*` | 模式规则里 `%` 匹配到的部分（茎） | GNU make 手册 |

本仓用法上有一条纪律：**编译用 `$<`，链接用 `$^`**。编译规则
`%.o: %.c` 一次只吃一个 `.c`，用 `$<`；链接要把全部 `.o` 都带上，用
`$^`。打开自动头文件依赖之后（04 篇 7.2 节），依赖列表里会混进 `.h`，
这时编译命令若误用 `$^`，`.h` 会被一起塞给 gcc，这就是必须用 `$<` 的
实际原因。labs/03_makefile 两个工程的所有规则都按这条写。

---

## 4 模式规则与隐含规则

### 4.1 %.o: %.c 是怎么匹配的

`%.o: %.c` 一条规则顶替了"每个 `.c` 一条规则"的重复劳动。`%` 是通配，
匹配任意长度的词干。匹配过程：

```
 要生成 a.o
   |
   v
 拿 a.o 去套模式 %.o         --> % 吃到词干 "a"
   |
   v
 依赖就是 %.c 代入词干       --> a.c
   |
   v
 命令里 $@ = a.o  $< = a.c   --> gcc -c -o a.o a.c
```

1.1 节的实测里，三个 `.c` 没有各自写过规则，全是这一条模式规则编的；
`touch a.c` 后只有 `a.o` 重编，也是因为只有它能通过"依赖比目标新"的
检查。

### 4.2 连 Makefile 都没有，make 也会编

`mk/imp/` 下只有一个 `hello.c`，没有任何 Makefile。本机实测：

```text
$ make hello
cc     hello.c   -o hello
$ ./hello
implicit rule built me
```

make 内置了一批规则（隐含规则），找不到 Makefile 也照样工作。把内置
规则的原貌问出来：

```bash
make -p -f /dev/null
```

输出里能翻到（本机实测，GNU Make 4.4.1）：

```make
%: %.c
	$(LINK.c) $^ $(LOADLIBES) $(LDLIBS) -o $@

%.o: %.c
	$(COMPILE.c) $(OUTPUT_OPTION) $<

COMPILE.c = $(CC) $(CFLAGS) $(CPPFLAGS) $(TARGET_ARCH) -c
LINK.c = $(CC) $(CFLAGS) $(CPPFLAGS) $(LDFLAGS) $(TARGET_ARCH)
```

两条内置规则本身就是普通模式规则的写法：这也是 `CC`、`CFLAGS` 这些变量
名成为约定的原因，内置规则就用它们，`make CFLAGS=-O2` 直接改内置规则的
行为。工程里一旦自己写了 `%.o: %.c`，同名模式规则就盖住内置的那条。

### 4.3 本组清单

| 写法 | 作用 | 依据 |
|---|---|---|
| `%.o: %.c` | 模式规则，`%` 匹配词干 | 实测 2026-10-20 |
| 词干代入 | 依赖里的 `%` 换成同一词干 | 实测 2026-10-20 |
| 内置规则 | 无 Makefile 也能 `make hello` | 实测 2026-10-20 |
| `make -p` | 倒出全部规则与变量（含内置） | 实测 2026-10-20 |
| 静态模式规则 `objs: %.o: %.c` | 只对列出的目标套模式 | GNU make 手册 |

---

## 5 条件：ifeq / ifneq / ifdef 与 $(if)

`mk/05_cond.mk` 演示三种条件语句和一个函数式条件（这段也是
Project/Makefile 第 16 行算架构名的写法的拆解）：

```make
ARCH := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),x86)

ifeq ($(ARCH),arm)
  MSG := cross build for arm
else ifeq ($(ARCH),x86)
  MSG := native build for x86
else
  MSG := unknown arch
endif

ifdef V
  Q :=
else
  Q := @
endif
```

本机实测：

```text
$ make -f 05_cond.mk show
ARCH=x86 MSG=native build for x86
$ make -f 05_cond.mk show CROSS=arm-linux-gnueabihf-
ARCH=arm MSG=cross build for arm
$ make -f 05_cond.mk show V=1
ARCH=x86 MSG=native build for x86
verbose mode
```

- `ifeq (a,b)` / `ifneq`：比两个字串。命令行传 `CROSS=...` 走了 arm 分支。
- `ifdef X`：X 有定义（哪怕值为空以外的任何内容）就为真；`V=1` 打开了
  verbose 分支。Project/Makefile 第 70-74 行的 `Q := @` 静音开关就是
  这个结构。
- `$(if 条件,则[,否则])`：函数版条件，在一行里选值。条件展开后非空
  为真；两个分支只算被选中的那个。这里用它配合 `$(subst -, ,...)` 和
  `$(firstword ...)`，从 `arm-linux-gnueabihf-` 里拆出 `arm`。

**这一节搭好的积木**：语句版条件管 Makefile 里整段的取舍，函数版管
一个值的取舍。下一节把所有函数收齐。

---

## 6 函数分族

调用形式统一是 `$(函数 参数1,参数2,...)`：函数名与第一个参数之间用空格，
参数之间用逗号，这些空格和逗号不算参数值的一部分。模式参数里的 `%`
是通配。下面每个函数都在 `mk/04_funcs.mk` 里跑过，输出是本机实测。

### 6.1 文本替换与分析

```text
subst     : fEEt on the strEEt       $(subst ee,EE,feet on the street)
patsubst  : x.c.o bar.o              $(patsubst %.c,%.o,x.c.c bar.c)
strip     : [a b c]                  $(strip   a   b   c  )
findstring: [a] []                   $(findstring a,a b c) 找到返回本身,否则空
filter    : foo.c bar.c baz.s        $(filter %.c %.s,foo.c bar.c baz.s ugh.h)
filter-out: ugh.h                    filter 的反函数
sort      : bar foo lose             排序并去重(输入里有两个 foo)
```

`patsubst` 注意两点：只有**整个词**匹配模式才替换（`x.c.c` 词干是
`x.c`，所以得到 `x.c.o`）；不匹配的词原样保留。

### 6.2 文件名

```text
dir       : src/ ./                  取到最后一个斜杠为止;没有目录给 ./
notdir    : foo.c hacks              只要文件名部分
suffix    : .c                       只要后缀
basename  : src/foo hacks            去掉后缀
addsuffix : foo.c bar.c              每个词后面接同一个后缀
addprefix : src/foo src/bar          每个词前面接同一个前缀
wildcard  : ../f_add.c ../main.c ... 真去磁盘找,只列存在的文件
foreach   : .main.c.d .sub.c.d .app.c.d
```

- `$(wildcard *.c)` 是真的访问文件系统：列出来的是那一刻**存在**的文件。
  工程变大后"新加一个 `.c` 不用改 Makefile"靠的就是它（mini_proj 第三步，
  [03 Makefile 的使用](../tutorials/01_应用编程/03_Makefile的使用.md)第 1 节）。
- `$(foreach f, 列表, 文本)`：把列表里每个词依次赋给 `f`，展开一次文本，
  结果用空格连起来。上面的输出是给每个 `.o` 算依赖文件名 `.xxx.d` 的
  经典写法（Makefile.build 第 35 行就是这么用的）。

### 6.3 取值、判断与出处

```text
firstword : arm-linux-gnueabihf-gcc
subst+fw  : arm                      $(firstword $(subst -, ,arm-linux-gnueabihf-))
shell     : 42                       $(shell echo $((6 * 7)))
if(true)  : non-empty
if(false) : [empty]
origin src: file                     文件里定义的
origin CC : default                  make 内置默认
origin ZZ : undefined                没定义过
命令行传入后 origin CC : command line
```

`$(origin 变量名)` 回答"这个变量是从哪来的"，参数是名字本身（不带
`$()`）。全部可能的返回值：`undefined`、`default`、`environment`、
`environment override`、`file`、`command line`、`override`、`automatic`
（GNU make 手册；本篇实测了其中四种）。

### 6.4 本组清单

| 族 | 函数 | 作用 | 依据 |
|---|---|---|---|
| 文本 | `subst` | 逐处替换子串 | 实测 2026-10-20 |
| 文本 | `patsubst` | 按模式替换整个词 | 实测 2026-10-20 |
| 文本 | `strip` | 去首尾空白、压连续空白 | 实测 2026-10-20 |
| 文本 | `findstring` | 找到返回本身，否则空 | 实测 2026-10-20 |
| 文本 | `filter` / `filter-out` | 按模式留 / 扔 | 实测 2026-10-20 |
| 文本 | `sort` | 排序并去重 | 实测 2026-10-20 |
| 文件名 | `dir` / `notdir` | 取目录部分 / 文件名部分 | 实测 2026-10-20 |
| 文件名 | `suffix` / `basename` | 取后缀 / 去后缀 | 实测 2026-10-20 |
| 文件名 | `addsuffix` / `addprefix` | 统一接后缀 / 前缀 | 实测 2026-10-20 |
| 文件名 | `wildcard` | 列出真实存在的匹配文件 | 实测 2026-10-20 |
| 文件名 | `realpath` / `abspath` | 绝对路径（realpath 要求存在） | GNU make 手册；Project/Makefile 第 115 行 |
| 循环 | `foreach` | 逐词展开模板 | 实测 2026-10-20 |
| 判断 | `if` | 二选一求值 | 实测 2026-10-20 |
| 出处 | `origin` | 变量的定义来源 | 实测 2026-10-20 |
| 外部 | `shell` | 执行 shell 命令 | 实测 2026-10-20 |
| 词表 | `firstword` / `word` / `words` | 取词 | firstword 实测 2026-10-20；余 GNU make 手册 |
| 词表 | `wordlist` / `lastword` | 取词区间 / 末词 | GNU make 手册 |
| 报信 | `$(info ...)` `$(warning ...)` `$(error ...)` | 打印 / 打印 / 打印并中止 | GNU make 手册 |
| 替代写法 | `$(SRCS:.c=.o)` | 等价 `$(patsubst %.c,%.o,$(SRCS))` | 实测（mini_proj Makefile 第 15 行） |

---

## 7 命令行与递归

### 7.1 make 自己的选项

```text
make -f Makefile.build         指定规则文件,不再找名为 Makefile 的文件
make -C a -f ../Makefile.build 先切到目录 a 再执行
make 目标                       指定目标,不默认第一个
make -n                         预演,只打印不执行
make -j2                        并行(本仓 WSL 用 -j2 以内)
make VAR=值                     命令行赋值,优先级最高(2.3 节)
```

全部实测过（`-C` 的输出会多两行 `Entering directory` / `Leaving
directory`，递归层次深时靠它们定位当前目录）。

### 7.2 递归调用要写 $(MAKE)

Makefile 里再启动 make（进子目录、或换一份规则文件），命令里写
`$(MAKE)` 而不是写死 `make`：这个变量的值是当前 make 的完整路径，而且
`-n`、`-j` 这类命令行状态会通过 `MAKEFLAGS` 自动传下去（GNU make 手册）。
本仓两个递归点都写 `$(MAKE)`：labs/03_makefile/proj 的引擎调用
（Makefile 第 29 行、Makefile.build 第 43 行），Project/Makefile 构建
FreeType 的第 114-115 行。

### 7.3 通用 Makefile 的三条核心规则（内核式递归引擎）

[labs/03_makefile/proj/](../labs/03_makefile/proj/) 复现了"每个目录只声明
`obj-y`，引擎递归合并"的通用结构。三条核心规则：

```make
# 子目录:进去用同一份引擎编(结尾带斜杠的 obj-y 项是目录)
$(subdir-y):
	$(MAKE) -C $@ -f $(TOPDIR)/Makefile.build

# 编译:全局 CFLAGS + 目录 EXTRA_CFLAGS + 单文件 CFLAGS_$@,顺手生成 .d
%.o: %.c
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) $(CFLAGS_$@) -Wp,-MD,$(dep_file) -c -o $@ $<

# 合并:本目录 .o + 子目录 built-in.o -> 本目录 built-in.o
built-in.o: $(cur_objs) $(subdir_objs)
	$(LD) -r -o $@ $^
```

配套的两个拆分用 `filter`：

```make
subdir-y := $(filter %/, $(obj-y))       # 带斜杠的是子目录
cur_objs := $(filter-out %/, $(obj-y))   # 其余是本目录的 .o
```

顶层链接永远一行：`$(CC) -o $(TARGET) built-in.o`。
这套结构的完整推导和两个实踩的坑（`.DEFAULT_GOAL` 被抢、规则写在过滤
之前）在 03 篇[03 Makefile 的使用](../tutorials/01_应用编程/03_Makefile的使用.md)第 7 节。

### 7.4 include 与 -include

```make
include $(DEPS)      # 文件不存在就报错
-include $(DEPS)     # 文件不存在当没看见
```

第一次编译时 `.d` 文件还不存在，所以工程里一律用 `-include`
（mini_proj Makefile 第 28 行、Project/Makefile 第 123 行）。实测：
`-include` 两个不存在的文件，make 照常执行。Makefile.build 第 35-39 行
用的是另一种老写法：先用 `wildcard` 把不存在的滤掉再 `include`，效果
相同。

---

## 8 本仓 Makefile 里的实物对照

| 实物 | 位置 | 用到了本篇哪些条目 |
|---|---|---|
| `CROSS ?=` 留空，命令行传工具链前缀 | Project/Makefile 第 12 行 | `?=`、命令行赋值 |
| 从工具链前缀拆架构名 | 第 16 行 | `$(if)`、`$(firstword)`、`$(subst)` |
| 自动收全部源文件 | 第 25 行 | `$(wildcard)`、`$(foreach)` |
| 源文件名单换算成目标名单 | 第 26、32、39 行 | `$(patsubst)` |
| 单测剔除 main.o | 第 33 行 | `$(filter-out)` |
| 交叉/本机选不同库参数 | 第 44-57 行 | `ifeq` |
| 命令行覆盖也保住 -pthread | 第 65、68 行 | `override` |
| `V=1` 显示完整命令 | 第 70-74 行 | `ifdef`、`@` 静音 |
| 链接用 `$^`、编译用 `$<` | 第 83、102 行 | 自动变量纪律（3 节） |
| 头文件自动依赖 | 第 99-102、123 行 | `-MMD -MP`（04 篇 7.2）、`-include` |
| FreeType 子构建 | 第 114-115 行 | `$(MAKE) -C`、`$(abspath)`、order-only 依赖 `|`（第 119 行） |
| 内核式递归引擎 | labs/03_makefile/proj/ | `.DEFAULT_GOAL`、`export`、`filter %/`、`$(MAKE)` |
| 五步演进的最小工程 | labs/03_makefile/mini_proj/ | 第 2 到 7 节几乎全部条目 |

`order-only` 依赖（`目标: 普通依赖 |  order依赖`）的语义：竖线右边的
只看存在与否，不比时间戳（GNU make 手册）。Project 用它表示"FreeType
装好一次就行，它的新旧不触发重链"。

---

## 9 [判] 本篇判据

`Knowledge/labs/00_basics/12_gcc_make_options/check.sh` 后半部分逐条核对
本篇清单里标"实测"的条目（与 04 篇共用一套脚本，2026-10-20 全量通过：
**128 PASS / 0 FAIL / 0 SKIP**，含 04 篇部分）：

    [ ] pat 工程:首 make 编三个 .c,二次 make up to date,
        touch a.c 只重编 a.o,make -n 只打印不执行
    [ ] 空格缩进报 missing separator(退出码 2)
    [ ] 目录里有同名文件时 make clean 被挡,.PHONY 后无条件执行
    [ ] A(=) 看见后定义的 C,B(:=) 定死为空;+= 沿袭延时/立即
    [ ] ?= 不覆盖文件内定义;环境变量算已定义;命令行压过一切
    [ ] 延时变量自引用报 Recursive variable,退出码 2
    [ ] export 的变量子 make 可见;没 export 的 CC 子 make 只见内置 cc
    [ ] $@ $< $^ $? 与手工推导一致(touch b.txt 后 $? 只剩 b.txt)
    [ ] 无 Makefile 也能 make hello(内置规则);make -p 能看到 %.o: %.c
    [ ] 条件三分支(默认/CROSS=/V=1)各走各路
    [ ] 04_funcs.mk 里 18 个函数的输出逐个与清单一致
    [ ] .DEFAULT_GOAL 钉住 all;删掉后被 include 方的第一个目标抢走

    注错见红:把 01_vars.mk 的 := 改成 =,"立即变量 B"判据必须 FAIL;
    把 check.sh 里 subst 的期望改一个字母,"subst"判据必须 FAIL
    (2026-10-20 已逐条验证)。

## 10 速查清单（索引）

清单本体就是第 1 到 7 节末尾的分组表。按症状反查：

| 你要做的事 | 条目 | 节 |
|---|---|---|
| 只重做受影响的文件 | 规则的两个执行条件 | 1.1 |
| clean/test 动作目标 | `.PHONY` | 1.3 |
| include 之后默认目标跑偏 | `.DEFAULT_GOAL` | 1.4 |
| 值什么时候算 | `=` 延时 / `:=` 立即 | 2.1、2.2 |
| 没定义过才赋值 | `?=` | 2.1 |
| 命令行临时改参数 | `make X=1` | 2.3 |
| 传给子目录 | `export` + `$(MAKE)` | 2.4、7.2 |
| 一个规则编所有 .c | `%.o: %.c` + `$@ $<` | 3、4.1 |
| 链接带全部 .o | `$^` | 3 |
| 按条件选参数 | `ifeq` / `$(if)` | 5 |
| 收集源文件 / 换后缀 / 拆目录 | `wildcard` / `patsubst` / `filter %/` | 6 |
| 头文件改了要触发重编 | `-MMD -MP`（04 篇）+ `-include` | 7.4 |

## 11 回看

| 问题 | 答案 | 证据在哪节 |
|---|---|---|
| 命令什么时候执行 | 目标不存在，或依赖比目标新 | 1.1 |
| 裸 make 编谁 | 第一个目标；可被 include 抢走，用 .DEFAULT_GOAL 钉死 | 1.2、1.4 |
| clean 为什么有时会"up to date" | 目录里有同名文件；`.PHONY` 解决 | 1.3 |
| 变量什么时候算出来 | 延时变量执行时，立即变量读取时 | 2.1、2.2 |
| 谁的赋值说了算 | 命令行 > 文件 > 环境 | 2.3 |
| 子目录怎么拿到变量 | `export`；递归用 `$(MAKE)` | 2.4、7.2 |
| `$@` `$<` `$^` `$?` | 目标 / 第一个依赖 / 全部依赖 / 更新的依赖 | 3 |
| 一条规则编所有 .c | `%.o: %.c`，词干代入 | 4.1 |
| 没有规则 make 也会编 | 内置隐含规则 | 4.2 |
| 清单怎么写短 | wildcard 收集、patsubst 换名、foreach 遍历 | 6 |

## 12 带走

开头三个问题的答案：

1. **规则**是 `目标: 依赖` 加 TAB 命令；make 只在"目标不存在"或"依赖
   更新"时执行命令；裸 `make` 生成第一个目标。
2. **变量**分延时（`=`、`?=`、`define`）和立即（`:=`）两个时刻，`+=`
   沿袭；命令行 > 文件 > 环境；跨目录靠 `export`。
3. **自动变量与函数**：`$@`/`$<`/`$^` 让规则通配所有文件（编译用 `$<`、
   链接用 `$^`）；`wildcard` 收集、`patsubst` 换名、`filter` 拆分、
   `foreach` 遍历、`origin` 查出处。

看到什么先想到什么：

| 看到 | 先想到 |
|---|---|
| `missing separator` | 命令行开头不是 TAB |
| `'xxx' is up to date`（不该出现时） | 有同名文件，查 `.PHONY` |
| 变量是空 | 它是立即变量，定义时右边还没值；或没 export 到子 make |
| `Recursive variable ... references itself` | 延时变量引用了自己，换 `:=` |
| include 之后裸 make 行为变了 | 默认目标被抢，加 `.DEFAULT_GOAL` |
| 改了 .h 没重编 | 缺 `-MMD -MP` 与 `-include`（04 篇 7.2） |
| 命令行 `make X=1` 没生效 | 文件里写了 `override X` |

## 13 接下来

- [03 Makefile 的使用](../tutorials/01_应用编程/03_Makefile的使用.md)：
  从四条写死的规则到通用引擎的完整推导（本篇是它的语法索引）
- [04 GCC 的选项](04_GCC的选项.md)：规则命令里的 `-MMD -MP`、`-c -o` 等
  开关在那里逐条讲
- [05 静态库、动态库与符号](05_静态库动态库与符号.md)：链接规则背后
  的机制

## 附：实验文件

本篇所有命令在 `Knowledge/labs/00_basics/12_gcc_make_options/mk/` 下执行：

```text
01_vars.mk          五种赋值与展开时机
02_selfref.mk       延时变量自引用报错
03_autovar.mk       $@ $< $^ $? 实测
04_funcs.mk         18 个函数的输出
05_cond.mk          ifeq / ifdef / $(if)
06_default_goal.mk  .DEFAULT_GOAL 对照实验（配 06b_rules.mk）
07_include.mk       -include 容忍缺失文件
08_export.mk        export 与递归（配 sub/Makefile）
pat/                模式规则小工程（%.o: %.c）
imp/                只有一个 hello.c，演示内置规则
```
