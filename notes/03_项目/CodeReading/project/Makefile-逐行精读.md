# Makefile 逐行精读

对应代码：`project/Makefile`，70 行。

前置：make 的规则模型、模式规则、自动变量、`$(wildcard)` 与 `$(patsubst)`、
`-MMD -MP` 的作用，见 [`notes/01_应用编程/01_工具链与构建系统.md`](../../../01_应用编程/01_工具链与构建系统.md)
第 4 节。本篇不重讲这些记号，只讲它们在这里展开成了什么。

---

## 1. 文件定位

顶层唯一的一份 `Makefile`，非递归。子目录里没有 `Makefile`。

它要同时满足三件事：本机 x86 编出来在 WSL 里调逻辑，交叉编出来拿去上板，
两份产物并存不互相覆盖；加一层的时候不用回来改它；
改一个头文件时该重编的都重编。

它写着一条设计约束（第 10 行）：

```
    # 设计约束: 新增一个 .c 到任何已列出的子目录, 不需要修改本文件。
```

这条约束是可验证的，`check.sh` 的第 3 组判据量的就是它。

---

## 2. 用法注释（第 1 到 10 行）

```makefile
# 量产工具项目顶层 Makefile
#
# 用法:
#   make                                本地 x86 版, 产物 build/x86/product_tool
#   make CROSS=arm-linux-gnueabihf-     ARM  版,    产物 build/arm/product_tool
#   make V=1                            显示完整编译命令
#   make clean                          只删当前架构的产物
#   make distclean                      删掉整个 build/
```

五种用法，对应下面五处实现。这段注释是这个文件的接口文档，
改了任何一个开关的行为都要回来改这里。

---

## 3. 工具链与架构名（第 12 到 16 行）

```makefile
CROSS   ?=
CC      := $(CROSS)gcc

# 从工具链前缀里取架构名: arm-linux-gnueabihf- 取到 arm, 前缀为空则是 x86
ARCH    := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),x86)
```

**`?=` 与 `:=` 的区别在这里是实质性的。**
`CROSS ?=` 的意思是"没有定义过才赋值"，命令行 `make CROSS=arm-...-` 传进来的值
优先级高于 Makefile 里的赋值，所以这一行不会覆盖它。
写成 `CROSS =` 或 `CROSS :=` 也不会——命令行变量的优先级本来就最高——
但 `?=` 把"这是个可以从外面给的开关"这层意思写在了语法里。

`CC := $(CROSS)gcc` 用 `:=` 立即展开。此刻 `CROSS` 的值已经定了，
所以 `CC` 当场变成 `gcc` 或 `arm-linux-gnueabihf-gcc`。
用 `=`（延时展开）效果相同但每次引用 `CC` 都要重新展开一遍，没有好处。

第 16 行是这个文件里最密的一行，从里往外拆：

```
    $(subst -, ,$(CROSS))
        把 CROSS 里所有的 '-' 换成空格
        "arm-linux-gnueabihf-"  ->  "arm linux gnueabihf "

    $(firstword ...)
        取第一个空白分隔的词
        "arm linux gnueabihf "  ->  "arm"

    $(if $(CROSS),<非空时的值>,x86)
        CROSS 非空取前者, 空取 "x86"
```

注意 `$(subst -, ,$(CROSS))` 里第二个参数是**一个空格**，
它夹在两个逗号之间，看起来像是空的。删掉那个空格就变成了"把 `-` 删掉"，
`firstword` 会拿到整个 `armlinuxgnueabihf`。这一处在编辑器里
如果开了"删除行尾空白"或者手动对齐时被吃掉，构建不会报错，
只会把产物放进一个叫 `armlinuxgnueabihf` 的目录里。

**为什么要算而不是手写 `ARCH`。** 手写的话会出现 `ARCH` 和 `CROSS` 对不上的构型
（`make ARCH=arm` 但没给 `CROSS`），编出来的是 x86 产物，放在 `build/arm/` 下，
`file` 之前看不出来。算出来就不存在这种构型。

代价是架构名跟着工具链前缀走：换成 `aarch64-linux-gnu-` 会得到 `aarch64`，
换成 `arm-buildroot-linux-gnueabihf-` 仍然得到 `arm`。
第 2 阶段换 BSP 工具链时，产物会落进同一个 `build/arm/`，
和 apt 工具链编的产物混在一起。那时要么先 `distclean`，要么把这一行改成
取更长的前缀。这是一处已知的账。

---

## 4. 路径与源文件收集（第 18 到 27 行）

```makefile
TARGET  := product_tool
BUILD   := build/$(ARCH)
BIN     := $(BUILD)/$(TARGET)

# 加一个新层时只改这一行
SUBDIRS := display input font ui page business

SRCS    := $(wildcard *.c) $(foreach d,$(SUBDIRS),$(wildcard $(d)/*.c))
OBJS    := $(patsubst %.c,$(BUILD)/%.o,$(SRCS))
DEPS    := $(OBJS:.o=.d)
```

`SRCS` 分两段：顶层的 `*.c`（`main.c` 和 `common.c`），
加上六个子目录各自的 `*.c`。

`$(foreach d,$(SUBDIRS),$(wildcard $(d)/*.c))` 的展开过程：
`d` 依次取 `display`、`input`……六个值，每次求一次 `$(wildcard display/*.c)`，
把六次的结果拼起来。

**为什么不用 `$(wildcard */*.c)` 一把收完。**
那样会把以后可能出现的任何目录都收进来，包括 `build/`（虽然 `build/` 下没有 `.c`）、
以后可能加的 `unittest/`（那里面会有自己的 `main()`，链接时报重复定义）、
以及资料仓拷进来做参考的目录。列出 `SUBDIRS` 是一道白名单，
代价是加一层要改这一行——这是第 3 节说的"加一层动两处"里没算进去的第三处，
因为加层这件事在整个项目里只会发生六次，而且已经发生完了。

`$(patsubst %.c,$(BUILD)/%.o,$(SRCS))` 把 `display/disp_manager.c` 变成
`build/x86/display/disp_manager.o`。**目录结构在产物树里被保留**，
所以两个不同目录下的同名 `.c` 不会撞车。

`$(OBJS:.o=.d)` 是 `$(patsubst %.o,%.d,$(OBJS))` 的简写。
`.d` 文件和 `.o` 放在一起，一个源文件对应一对。

---

## 5. 编译选项（第 29 到 32 行）

```makefile
# -I. 让跨层引用写成 "display/disp_manager.h", 一眼看得出是跨层
CFLAGS  := -Wall -Wextra -O2 -I. -Iinclude $(CFLAGS_EXTRA)
LDFLAGS :=
LDLIBS  :=
```

`-Wall -Wextra` 两个都开。`-Wextra` 里的 `-Wunused-parameter` 就是
`main.c` 里那两行 `(void)argc;` 的来历。

`-I.` 和 `-Iinclude` 是两条独立的搜索路径，各管一件事：
`-Iinclude` 让 `#include "common.h"` 找得到；
`-I.` 让 `#include "display/disp_manager.h"` 找得到。
去掉 `-I.` 之后，跨层引用就只能写成不带目录的形式，那条约定就没法执行了。

`$(CFLAGS_EXTRA)` 拼在末尾，是留给命令行的口子：

```
    make CFLAGS_EXTRA=-DLOG_LEVEL=0
```

拼在末尾而不是开头，是因为 gcc 的重复选项后者覆盖前者，
放末尾才能覆盖掉前面的默认值（比如 `CFLAGS_EXTRA=-O0` 要能盖掉 `-O2`）。

`LDFLAGS` 和 `LDLIBS` 现在都是空的。分成两个变量而不是一个，
是照链接命令的参数顺序：`LDFLAGS` 放 `-L` 这类"去哪找库"的选项，
出现在 `-o` 附近；`LDLIBS` 放 `-lfreetype` 这类"要哪个库"，
必须出现在所有 `.o` **之后**。顺序反了会报找不到符号。
接 freetype 的那一章会用到这个区别。

---

## 6. 静默开关（第 34 到 38 行）

```makefile
ifeq ($(V),1)
  Q :=
else
  Q := @
endif
```

`@` 前缀让 make 执行一条命令时不回显命令本身。把它做成变量，
是为了能一键切回完整命令：`make V=1` 时 `Q` 是空，命令原样打出来。

调试构建问题时必须能看到完整命令行。写死 `@` 的 Makefile 在
"为什么这个文件编出来不对"的时候要临时改文件才能看，很不方便。

注意 `ifeq` 和它的分支要顶格或者按 make 的缩进规则写，
分支里的两行前面是**空格**而不是 TAB。这里的缩进不是命令，
写成 TAB 会被当成一条 shell 命令交给 shell 执行。

---

## 7. 链接规则（第 40 到 47 行）

```makefile
.PHONY: all clean distclean show

all: $(BIN)

$(BIN): $(OBJS)
	@mkdir -p $(dir $@)
	@echo "  LD    $@"
	$(Q)$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)
```

`.PHONY` 声明四个假想目标。不声明的话，目录里如果真有一个叫 `clean` 的文件，
`make clean` 会认为目标已经是最新的而什么都不做。这个坑在
`notes/01` 第 4 节有实验。`all` 也要声明，理由相同。

`@mkdir -p $(dir $@)` 里的 `$(dir ...)` 取路径部分，
`build/x86/product_tool` 取到 `build/x86/`。`-p` 让父目录不存在时一并创建，
且目录已存在时不报错。这一行前面的 `@` 是写死的，
因为 `mkdir` 的回显没有调试价值。

`@echo "  LD    $@"` 是自己打的简化提示，形状仿 Linux 内核的构建输出。
它有一个副作用：`check.sh` 第 88 行用 `grep -c '^  CC '` 数重编了几个文件，
数的就是这类提示行。**改这里的格式会让那条判据失效**，
而且是静默失效——`grep -c` 会数到 0，判据变红，还算看得见；
如果改成前面多一个空格，判据会一直数到 0 并且红，容易被当成代码问题去查。

链接用 `$^`（全部依赖）而不是 `$<`（第一个依赖），因为要把所有 `.o` 一起喂给 gcc。

`$(LDLIBS)` 在 `$^` 之后，理由见第 5 节。

---

## 8. 编译规则与自动依赖（第 49 到 57 行）

```makefile
# -MMD 顺带生成 .d 文件, 内容是 "xxx.o: xxx.c a.h b.h ...", 实现头文件自动依赖
# -MP  为每个头文件补一条空规则, 这样删掉一个头文件时 make 不会报 No rule to make target
$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "  CC    $<"
	$(Q)$(CC) $(CFLAGS) -MMD -MP -c -o $@ $<

# -include 对不存在的文件不报错, 所以第一次编译时不需要再套一层 wildcard 过滤
-include $(DEPS)
```

模式规则的两边分别带前缀：目标是 `$(BUILD)/%.o`，依赖是 `%.c`。
`%` 匹配的部分是相同的，所以 `build/x86/display/disp_manager.o` 匹配到
`%` = `display/disp_manager`，依赖就是 `display/disp_manager.c`。
**产物树和源码树的目录结构靠这一条对应起来。**

`@mkdir -p $(dir $@)` 在这里比链接那条更重要：
第一次编译时 `build/x86/display/` 整条路径都不存在，gcc 不会替你建目录。

编译用 `$<`（第一个依赖）。这条规则只有一个依赖，用 `$^` 效果相同，
但 `.d` 文件被读进来之后依赖会变多（多出一串 `.h`），
那时 `$^` 会把头文件也当成输入文件喂给 gcc。所以这里必须是 `$<`。
**这是自动依赖打开之后才会暴露的区别**，在没有 `.d` 的第一次构建里看不出来。

`-MMD` 与 `-MD` 的区别是前者不把系统头写进依赖表。
`stdio.h` 不会变，把它写进去只会让 `.d` 文件变大、`make` 每次多 `stat` 几十个文件。

`-MP` 给每个头文件补一条没有依赖也没有命令的空规则。
它解决的是这个场景：`.d` 里写着 `xxx.o: xxx.c old.h`，
然后你删掉了 `old.h` 并且从 `xxx.c` 里去掉了那行 `#include`。
下次 `make` 时 `.d` 还是旧的，make 看到依赖 `old.h` 不存在又没有规则能生成它，
报 `No rule to make target 'old.h'` 并停下。有了 `-MP`，
`old.h` 自己有一条空规则，make 认为它"生成好了"，
于是判定 `xxx.o` 需要重编，重编时生成新的 `.d`，问题自愈。

`-include` 而不是 `include`：第一次构建时 `.d` 一个都不存在，
`include` 会报错停下。教材那套用 `$(wildcard)` 先过滤一遍再 `include`，
效果相同，多两行。

**`-include $(DEPS)` 的位置在文件中部而不是开头。**
make 里 `include` 进来的规则不影响"第一个目标是谁"，
但把它放在 `all:` 之前会有风险：如果某个 `.d` 文件损坏成了一条完整规则，
它会变成第一个目标。放在 `all:` 之后就没有这个问题。

---

## 9. 调试目标与清理（第 59 到 70 行）

```makefile
# 排查 Makefile 变量展开用
show:
	@echo "ARCH  = $(ARCH)"
	@echo "CC    = $(CC)"
	@echo "SRCS  = $(SRCS)"
	@echo "OBJS  = $(OBJS)"

clean:
	rm -rf $(BUILD)

distclean:
	rm -rf build
```

`make show` 打四个变量的展开结果。它存在的理由是第 3 节那一行 `ARCH` 的算法
不是一眼能看出来的，改动之后需要一个当场验证的手段。
`make CROSS=arm-linux-gnueabihf- show` 应该打出 `ARCH = arm`。

**`clean` 只删 `$(BUILD)`，也就是当前架构那一棵。** 删两棵叫 `distclean`。
这个区分是有代价的：习惯了 `make clean` 清干净的人会以为已经清了，
实际上另一棵还在。收益是交叉编译时不会误伤本机产物——
`make clean && make CROSS=...` 这个常见序列不会把 x86 产物删掉。

`check.sh` 第 59 到 62 行专门量这个区别：`clean` 之后剩 1 份产物，
`distclean` 之后 `build/` 目录都不在了。

`distclean` 里写的是字面量 `build` 而不是 `$(dir $(BUILD))`。
两者当前等价，写字面量是因为这一行的语义是"把整个产物根删掉"，
它不该跟着 `ARCH` 变。

---

## 10. 执行顺序

`make` 的执行分成两个完全分开的阶段，混起来读会读错。

**第一阶段，读取与展开。** make 把整个文件读一遍，此刻：

| 步 | 发生了什么 |
|---|---|
| 1 | `CROSS` 定值（命令行优先），`CC`、`ARCH`、`BUILD` 立即展开 |
| 2 | `$(wildcard)` **在这一刻**去磁盘上列文件，得到 `SRCS` |
| 3 | `OBJS`、`DEPS` 由 `SRCS` 算出 |
| 4 | `-include $(DEPS)` 把已存在的 `.d` 读进来，追加依赖关系 |
| 5 | 规则库建立完毕，此时还没有执行任何一条命令 |

第 2 步的时刻很关键：**`$(wildcard)` 是在读取阶段求值的，不是执行阶段。**
构建过程中新生成的 `.c` 文件不会被这次 `make` 看到，要再跑一次 `make`。
本仓不生成 `.c`，所以不受影响。

**第二阶段，执行。** 从默认目标 `all` 出发，按依赖图走：

| 步 | 发生了什么 |
|---|---|
| 6 | `all` 依赖 `$(BIN)`，`$(BIN)` 依赖八个 `.o` |
| 7 | 逐个 `.o` 比时间戳，需要重编的走模式规则 |
| 8 | 每次编译顺带写出一个 `.d`（这次不会被读，下次才读） |
| 9 | 八个 `.o` 都就绪后执行链接 |

第 8 步说明了为什么**第一次构建时头文件依赖是不生效的**：
`.d` 是这次才生成的，读的是上次的。第一次构建本来就要编全部文件，
所以没有影响；但如果你 `make clean` 之后立刻 `touch include/common.h` 再 `make`，
量到的"全量重编"是因为产物不存在，不是因为依赖生效。
`check.sh` 第 84 到 88 行的顺序（先完整 `make` 一次，再 `touch`，再 `make`）
就是为了避开这个陷阱。

---

## 11. 容易读错的地方

**`$(subst -, ,$(CROSS))` 第二个参数是一个空格，不是空。** 见第 3 节。

**编译规则必须用 `$<` 不能用 `$^`。** 自动依赖打开之后，`$^` 会把 `.h` 也喂给 gcc。

**`-include` 那一行在文件中部不是随手放的。** 见第 8 节末。

**`make clean` 不清另一个架构。** 要清干净用 `distclean`。

**`@echo "  CC    $<"` 的空格数是判据的一部分。** `check.sh` 用 `grep -c '^  CC '`
数它，改格式要同步改判据。

**`SUBDIRS` 是白名单，不是"这些目录下的文件会被编译"的描述。**
不在这个列表里的目录，哪怕有 `.c` 也不会被编。新建目录忘了加，
现象是链接时报 undefined reference，而不是"文件没编"。

---

## 12. 消费者

| 谁 | 用到的部分 |
|---|---|
| `check.sh` 第 36 行等 | 直接 `make`，量默认目标 |
| `check.sh` 第 55 行 | `make CROSS=$CROSS_PREFIX`，量交叉编译 |
| `check.sh` 第 59、61 行 | `make clean` 与 `make distclean` 的区别 |
| `check.sh` 第 77 行 | 用 `sed` 把 `SRCS` 那一行换成写死清单做注错 |
| `check.sh` 第 88、95 行 | `grep -c '^  CC '` 数重编文件数 |
| `check.sh` 第 91 行 | `sed 's/ -MMD -MP//'` 去掉自动依赖做注错 |
| `check.sh` 第 100 行 | `make CFLAGS_EXTRA=-DLOG_LEVEL=0` |

`check.sh` 第 77 行那个 `sed` 匹配的是行首的 `SRCS `（`^SRCS .*`）。
把变量改名或者改成 `SRCS:=`（等号前没有空格）都会让这条注错静默失效。
改这一行时要跑一次 `check.sh` 确认 `[3r]` 那一组仍然报红。
