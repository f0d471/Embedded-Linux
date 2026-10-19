# 14 make 的语法与函数

Makefile 只有规则一种原子（目标:依赖 + TAB 命令），变量和函数都是为了让
依赖表写得短、写得全。这一篇把原书第 3 章的语法罗列（PDF 145-156、161-165）
完整收进来；教程 03 篇讲原理与实验，这里查写法。所有例子出自原书原文
（标页码）或本机 GNU Make 4.4.1 实测（标"实测"）。

## 一、规则

```make
目标(target) ... : 依赖(prerequisites) ...
<TAB>命令(command)
```

- 目标通常是要生成的文件名，也可以是动作名称（如 `clean`）。
- 命令被执行的两个条件：**依赖比目标新**，或**目标还没生成**（PDF 145）。
- `make` 不带参数生成**第一个目标**；`make 目标名` 指定生成谁（PDF 147）。
- 没有依赖的目标（如 clean）其命令被强制执行（PDF 150-151）。

make 命令行（PDF 147）：

    make -f Makefile.build        指定规则文件,不再找名为 Makefile 的文件
    make -C a -f ...build         先切到目录 a 再执行
    make 目标 / make -C a 目标    指定目标,不再默认第一个

## 二、变量：五种定义

PDF 151 的原始形式（immediate = 读取时展开，deferred = 使用时展开）：

```text
immediate = deferred          延时变量
immediate ?= deferred         延时,仅当变量此前未定义时生效
immediate := immediate        立即(即时)变量
immediate += deferred or immediate   追加;沿袭左边变量的即时/延时属性
define immediate              define...endef 定义的变量是延时的
deferred
endef
```

- 延时变量在整个 Makefile 读完后再求值，所以**定义位置在后不影响结果**；
  即时变量定义那一刻定死（实测对照见教程 03 篇 2.2）。
- 延时变量自引用 `Y = $(Y) foo` 报
  `Recursive variable 'Y' references itself (eventually)`；用 `:=` 解决。
- 命令行变量 > Makefile 内赋值（`make X=1` 覆盖一切文件内定义）。
- 子目录递归时想让变量可见，`export CC`（PDF 148）。
- 执行 shell 命令取值：`TOPDIR := $(shell pwd)`（PDF 148）。

## 三、自动变量

| 记号 | 含义 | 典型用法 |
|---|---|---|
| `$@` | 本规则的目标 | 链接 `gcc -o $@ $^`、编译 `-o $@` |
| `$<` | 第一个依赖 | 编译 `gcc -c -o $@ $<`（一次只喂一个 `.c`） |
| `$^` | 全部依赖（去重、空格分隔） | 链接、`ld -r -o $@ $^` |

**编译用 `$<`、链接用 `$^`**；打开自动头文件依赖后 `$^` 会混入 `.h`，
所以编译规则永远用 `$<`（教程 03 篇 2.1）。

## 四、特殊目标与默认目标

| 写法 | 作用 |
|---|---|
| `.PHONY: clean` | 声明 clean 不是文件：不比时间戳，无条件执行。`all` 同理 |
| 第一个目标 | `make` 的默认目标。放前面不便时，可先写 `First_target: ...` 占位、后面再补全依赖与命令（PDF 148） |
| `.DEFAULT_GOAL := xxx` | 显式钉死默认目标（GNU make 内置变量）。**include 别的 Makefile 之前没有自己的规则时必须设**，否则默认目标被 include 方抢走——本仓复现通用 Makefile 引擎时的实踩坑，教程 03 篇 5.3 |

## 五、函数

调用形式 `$(function arguments)`，函数名与参数间用空格，参数间用逗号
（PDF 151）。`pattern` 里的 `%` 是通配。

### 5.1 文本替换与分析（PDF 151-152）

| 函数 | 形式 | 原书例子 → 结果 |
|---|---|---|
| subst | `$(subst from,to,text)` | `$(subst ee,EE,feet on the street)` → `fEEt on the strEEt` |
| patsubst | `$(patsubst pattern,replacement,text)` | `$(patsubst %.c,%.o,x.c.c bar.c)` → `x.c.o bar.o`；不匹配的项原样保留 |
| strip | `$(strip string)` | `$(strip a  b c)` → `a b c`（去首尾空格、压连续空格） |
| findstring | `$(findstring find,in)` | `$(findstring a,a b c)` → `a`；`$(findstring a,b c)` → 空 |
| filter | `$(filter pattern...,text)` | `$(filter %.c %.s,foo.c bar.c baz.s ugh.h)` → `foo.c bar.c baz.s` |
| filter-out | `$(filter-out pattern...,text)` | 同上例子 → `ugh.h`（filter 的反函数） |
| sort | `$(sort list)` | `$(sort foo bar lose)` → `bar foo lose`（排序并去重） |

### 5.2 文件名（PDF 152-153）

| 函数 | 形式 | 原书例子 → 结果 |
|---|---|---|
| dir | `$(dir names...)` | `$(dir src/foo.c hacks)` → `src/ ./` |
| notdir | `$(notdir names...)` | 同上 → `foo.c hacks` |
| suffix | `$(suffix names...)` | `$(suffix src/foo.c hacks)` → `.c` |
| basename | `$(basename names...)` | `$(basename src/foo.c hacks)` → `src/foo hacks` |
| addsuffix | `$(addsuffix suffix,names...)` | `$(addsuffix .c,foo bar)` → `foo.c bar.c` |
| addprefix | `$(addprefix prefix,names...)` | `$(addprefix src/,foo bar)` → `src/foo src/bar` |
| wildcard | `$(wildcard pattern)` | `$(wildcard *.c)` → 当前目录真实存在的 .c 列表（**真的去磁盘找**） |

### 5.3 其他（PDF 153-155）

| 函数 | 形式 | 说明 |
|---|---|---|
| foreach | `$(foreach var,list,text)` | list 每个词赋给 var 展开 text，结果空格相连。原书：`files := $(foreach dir,$(dirs),$(wildcard $(dir)/*))` |
| if | `$(if condition,then[,else])` | condition 非空为真；只计算被选中的那个分支 |
| origin | `$(origin variable)` | 查变量出处：`undefined`/`default`/`environment`/`file`/`command line`/`automatic`/`override`（PDF 154 表） |
| shell | `$(shell command)` | 执行 shell 命令，换行折叠成空格。原书：`src := $(shell ls *.c)` |

本仓 Project/Makefile 的组合实例（教程 03 篇 6 节）：
`ARCH := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),x86)`——
if/subst/firstword 三层嵌套，从工具链前缀算架构名。

## 六、通用 Makefile 速查（内核同款）

三条核心规则（PDF 149；完整复现与两坑见教程 03 篇 5 节）：

```make
# 子目录:进进去用顶层引擎编
$(subdir-y):
	$(MAKE) -C $@ -f $(TOPDIR)/Makefile.build

# 编译:全局 CFLAGS + 目录 EXTRA_CFLAGS + 单文件 CFLAGS_$@,顺手生成 .d
%.o: %.c
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) $(CFLAGS_$@) -Wp,-MD,$(dep_file) -c -o $@ $<

# 合并:本目录 .o + 子目录 built-in.o -> 本目录 built-in.o
built-in.o: $(cur_objs) $(subdir_objs)
	$(LD) -r -o $@ $^
```

顶层链接永远一行：`$(CC) $(LDFLAGS) -o $(TARGET) built-in.o`。
`obj-y` 里"带斜杠 = 子目录"的区分靠 `$(filter %/)` / `$(filter-out %/)`。

## 七、原书勘误与本仓补充

- `gcc -M main.c abc.dep`（PDF 136）：照敲报错，`-M` 只打 stdout；
  落文件用 `-MD`。见 13 篇第七节。
- `.DEFAULT_GOAL`：原书未提，本仓实踩后补入（第四节）。
- 原书 PDF 145 的最小 Makefile 用 `rm -f hello` 做清理，工程变大后应改为
  `find` 全目录扫（教程 03 篇第 4 步的孤儿产物实验）。
