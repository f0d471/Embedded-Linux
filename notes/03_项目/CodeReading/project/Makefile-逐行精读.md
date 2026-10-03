# Makefile 逐行精读

对应代码：`project/Makefile`（123 行）。

## 1. 文件定位

非递归单份 Makefile，管 x86/ARM 两条产物树、unittest 三个可执行、ARM 上
FreeType 2.10.2 的首次隔离构建。设计约束写在头部：新增一个 `.c` 到已列出的
子目录不需要改本文件（判据 [3] 用一个临时文件验证，[3r] 注错换成写死清单见红）。

前置知识：[从零开始读写 project 代码](../00-从零开始读写项目代码.md)第 9.1 节；
第 01 章笔记（构建系统）。

## 2. 正文

### 第 1—16 行：用法与架构推导

```makefile
# 网络视频终端项目顶层 Makefile
#
# 用法:
#   make                                本地 x86 版, 产物 build/x86/product_tool
#   make CROSS=arm-linux-gnueabihf-     ARM 版；首次自动隔离构建静态 FreeType
#   make V=1                            显示完整编译命令
#   make clean                          只删当前架构的产物
#   make distclean                      删掉整个 build/
#
# 设计约束: 新增一个 .c 到任何已列出的子目录, 不需要修改本文件。

CROSS   ?=
CC      := $(CROSS)gcc

# 从工具链前缀里取架构名: arm-linux-gnueabihf- 取到 arm, 前缀为空则是 x86
ARCH    := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),x86)

TARGET  := product_tool
BUILD   := build/$(ARCH)
BIN     := $(BUILD)/$(TARGET)
```

`ARCH` 一行做三件事：`subst` 把 `arm-linux-gnueabihf-` 按连字符拆成词表，
`firstword` 取第一个词，`$(if ...)` 在 `CROSS` 为空时落到 x86。架构名同时是
产物树名，两套工具链的 `.o` 永不相混（判据 [2] 验证两份产物并存与
`make clean` 只清当前架构）。`CROSS ?=` 允许命令行覆盖，
`:=` 让 `CC/ARCH/BUILD` 只展开一次。

### 第 22—35 行：源码收集与单测

```makefile
# 加一个新层时只改这一行
SUBDIRS := display input font ui page business

SRCS    := $(wildcard *.c) $(foreach d,$(SUBDIRS),$(wildcard $(d)/*.c))
OBJS    := $(patsubst %.c,$(BUILD)/%.o,$(SRCS))

# 单测: 每个 unittest/xxx.c 自己带 main, 单独链成 build/<arch>/unittest/xxx,
# 链接时带上除 main.o 外的全部 .o。unittest 不进 SUBDIRS, 否则它的 main
# 会被链进 product_tool 和 main.c 撞车。
TEST_SRCS := $(wildcard unittest/*.c)
TESTS     := $(patsubst %.c,$(BUILD)/%,$(TEST_SRCS))
LIB_OBJS  := $(filter-out $(BUILD)/main.o,$(OBJS))

DEPS    := $(OBJS:.o=.d) $(TESTS:=.d)
```

`wildcard` 在 make 读入时展开，新文件下一次 make 自动进来。`unittest` 的
三个 `main` 是核心冲突：`TEST_SRCS` 单列、链接时 `filter-out` 掉 `main.o`，
`product_tool` 与三个单测各得各的 main。注释里写了"不进 SUBDIRS"的后果，
这条约束由目录划分天然保证。

### 第 37—59 行：FreeType 双路

```makefile
# FreeType: x86 走系统 pkg-config；ARM 从资料包源码隔离构建到当前架构产物树。
ifeq ($(ARCH),arm)
  FT_VERSION  := 2.10.2
  FT_TARBALL  ?= ../../01_all_series_quickstart-master/04_嵌入式Linux应用开发基础知识/source/10_freetype/freetype-$(FT_VERSION).tar.xz
  FT_ROOT     := $(BUILD)/deps/freetype
  FT_SRC      := $(FT_ROOT)/freetype-$(FT_VERSION)
  FT_STAGE    := $(FT_ROOT)/stage
  FT_STAMP    := $(FT_STAGE)/.installed
  FREETYPE_CFLAGS ?= -I$(FT_STAGE)/usr/include/freetype2
  FREETYPE_LIBS   ?= $(FT_STAGE)/usr/lib/libfreetype.a -lm
else
  PKG_CONFIG ?= pkg-config
  FREETYPE_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags freetype2 2>/dev/null)
  FREETYPE_LIBS   ?= $(shell $(PKG_CONFIG) --libs freetype2 2>/dev/null)
endif

# -I. 让跨层引用写成 "display/disp_manager.h", 一眼看得出是跨层。
# FreeType 的头文件目录属于预处理选项，库放在对象文件之后的 LDLIBS。
CPPFLAGS := -I. -Iinclude $(FREETYPE_CFLAGS) $(CPPFLAGS_EXTRA)
CFLAGS   := -Wall -Wextra -Werror -O2 $(CFLAGS_EXTRA)
LDFLAGS  :=
LDLIBS   :=
override LDLIBS += $(FREETYPE_LIBS)
```

ARM 路径的四个目录变量都在 `build/$(ARCH)` 下，两架构互不污染；`?=` 允许
判据脚本从环境注入绝对路径（check.sh 里 `FT_TARBALL=...`，TechReport 04
4.3 节的教训：相对路径在 `/tmp` 副本里失效）。x86 的 `2>/dev/null` 让没装
FreeType 的机器给出干净的链接错误而不是 shell 报错。

`-I.` 与 `-Iinclude` 配合的是"跨层引用带目录前缀"的写法：
`#include "display/disp_manager.h"` 在引用处就暴露跨层关系。
`override LDLIBS +=`——命令行传的 `LDLIBS`（判据的 ASan 用法
`LDLIBS=-fsanitize=address`）会覆盖普通 `+=`，`override` 让 FreeType 库
无论如何都追加在后面，两不相失。

### 第 61—88 行：规则

```makefile
ifeq ($(V),1)
  Q :=
else
  Q := @
endif

.PHONY: all test clean distclean show

all: $(BIN)

$(BIN): $(OBJS)
	@mkdir -p $(dir $@)
	@echo "  LD    $@"
	$(Q)$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

test: $(TESTS)

$(BUILD)/unittest/%: $(BUILD)/unittest/%.o $(LIB_OBJS)
	@mkdir -p $(dir $@)
	@echo "  LD    $@"
	$(Q)$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

# -MMD 顺带生成 .d 文件, 内容是 "xxx.o: xxx.c a.h b.h ...", 实现头文件自动依赖
# -MP  为每个头文件补一条空规则, 这样删掉一个头文件时 make 不会报 No rule to make target
$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "  CC    $<"
	$(Q)$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c -o $@ $<
```

`Q` 是静默开关：`V=1` 时命令回显（`$(Q)` 为空），否则命令带 `@` 静默执行，
echo 的缩进格式照常打出。静态模式规则 `$(BUILD)/%.o: %.c` 一条管全部
`.c`，`$<` 是第一个前提（源文件）。`-MMD -MP` 的两条注释就是意图：
`.d` 文件由编译器生成（头文件依赖不会过期），`-MP` 补空规则防删头文件报错。
判据 [4]/[4r] 用"touch common.h 后重编文件数"钉住这条：去掉 `-MMD -MP`
后 touch 不再触发重编，见红。

### 第 90—109 行：ARM 的 FreeType 构建挂接

```makefile
ifeq ($(ARCH),arm)
$(FT_STAMP):
	@test -f "$(FT_TARBALL)" || { echo "missing $(FT_TARBALL)"; exit 1; }
	@mkdir -p "$(FT_ROOT)"
	@echo "  DEP   freetype-$(FT_VERSION) (ARM static)"
	$(Q)tar -xJf "$(FT_TARBALL)" -C "$(FT_ROOT)"
	$(Q)cd "$(FT_SRC)" && ./configure \
		--host=$(patsubst %-,%,$(CROSS)) --prefix=/usr \
		--enable-static --disable-shared --without-harfbuzz --without-brotli \
		--without-bzip2 --without-png --without-zlib >/dev/null
	$(Q)$(MAKE) -C "$(FT_SRC)" -j2 >/dev/null
	$(Q)$(MAKE) -C "$(FT_SRC)" DESTDIR="$(abspath $(FT_STAGE))" install >/dev/null
	$(Q)touch "$@"

$(BUILD)/font/font_freetype.o: $(FT_STAMP)
$(BIN) $(TESTS): | $(FT_STAMP)
endif

# -include 对不存在的文件不报错, 所以第一次编译时不需要再套一层 wildcard 过滤
-include $(DEPS)
```

stamp 规则只该跑一次：`.installed` 存在后目标已满足，不再重解压。
`--host=$(patsubst %-,%,$(CROSS))` 去掉尾缀连字符得到
`arm-linux-gnueabihf`，configure 的交叉三元组与工具链前缀同源。
`--without-*` 把可选依赖全关掉，产物只依赖 libc，板上少一批动态库要求。
依赖挂接分两条：`font_freetype.o` 是普通前置（stamp 变了就重编），
`$(BIN) $(TESTS)` 用 `|` order-only——链接不需要因为 stamp 时间戳变化而
重跑，只需要 stamp 先存在。`-include` 对缺失文件静默，首次构建时
`.d` 还不存在也不报错。

### 第 111—123 行：辅助目标

```makefile
# 排查 Makefile 变量展开用
show:
	@echo "ARCH  = $(ARCH)"
	@echo "CC    = $(CC)"
	@echo "SRCS  = $(SRCS)"
	@echo "OBJS  = $(OBJS)"
	@echo "FT    = $(FREETYPE_LIBS)"

clean:
	rm -rf $(BUILD)

distclean:
	rm -rf build
```

`clean` 只删当前架构（`BUILD`），`distclean` 删整棵 `build/`；判据 [2]
验证两者差一档。`show` 打印关键变量的最终展开值，排查 wildcard/FreeType
路径问题从它开始。

## 3. 执行顺序

```
make(首次, x86):   读入 → wildcard 收源 → 无 .d, -include 静默
                   → 逐个编 .o(-MMD 生成 .d) → 链 product_tool
make(ARM 首次):    同上 + FT_STAMP 不存在 → 解压/configure/make/install
                   → touch stamp → font_freetype.o → 链接
touch common.h:    .d 里 "disp_manager.o: include/common.h ..." 命中 → 相关 .o 全重编
make test:         TESTS 三个可执行, 链接时 LIB_OBJS(无 main.o) + FreeType 库
```

## 4. 容易读错的地方

- `ARCH` 由 `CROSS` 推导，`make CC=arm-linux-gnueabihf-gcc` 不会切架构，
  必须传 `CROSS=`。
- `unittest` 依赖 `filter-out main.o` 的 `LIB_OBJS`，把 `unittest` 加进
  `SUBDIRS` 会让 `main` 符号重复。
- `$(BIN) $(TESTS): | $(FT_STAMP)` 的 `|` 是 order-only：stamp 更新不触发
  重链接，只保证先后。
- `override LDLIBS +=` 是为了命令行 `LDLIBS=-fsanitize=address` 之类覆盖
  不丢 FreeType 库；没有 override，ASan 那次构建会漏链 freetype。
- `wildcard` 在读入时展开：构建中途生成的 `.c`（判据 [3] 的 disp_dummy.c）
  要下一次 make 才进 SRCS，判据正是先删 build 再 make 全程重跑。

## 5. 消费者清单

- 三个 check 脚本全部经由它构建（`make`/`make test`、`CFLAGS_EXTRA`、
  `LDLIBS`、`CROSS`）。
- 板上部署：`make CROSS=arm-linux-gnueabihf- LDFLAGS=-static`
  （命令行变量覆盖空值 `LDFLAGS :=`，glibc 2.41 vs 板上 2.30 的结论见
  TechReport 03/04）。
- 新层接入只改 `SUBDIRS` 一行（`main.c` 的 `g_layers` 同步加一行）。
