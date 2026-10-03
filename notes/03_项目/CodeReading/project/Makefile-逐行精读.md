# Makefile 逐行精读

对应代码：`project/Makefile`（137 行，`grep -n ''` 于 2026-10-04 核对）。

## 1. 文件定位

非递归单份 Makefile，管 x86/ARM 两条产物树、unittest 七个可执行、items
两个测试项程序、ARM 上 FreeType 2.10.2 的首次隔离构建。设计约束写在
头部：新增一个 `.c` 到已列出的子目录不需要改本文件（判据 [3] 用一个
临时文件验证，[3r] 注错换成写死清单见红）。

与旧版（TechReports 08 之前的 123 行）的差别集中在四处：`SUBDIRS`
加 config；新增 items 目标；`LDFLAGS` 的 pthread 用 `override` 追加；
unittest 计数从 3 到 7。

## 2. 变量区

### [12-23] 架构派生与层表

```make
CROSS   ?=
CC      := $(CROSS)gcc

# 从工具链前缀里取架构名: arm-linux-gnueabihf- 取到 arm, 前缀为空则是 x86
ARCH    := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),x86)

TARGET  := product_tool
BUILD   := build/$(ARCH)
BIN     := $(BUILD)/$(TARGET)

# 加一个新层时只改这一行
SUBDIRS := display input font ui page config business
```

`ARCH` 从工具链前缀拆出来，两条产物树 `build/x86` 与 `build/arm` 由此
并存（判据 [2] 验证并存与 `make clean` 只清当前架构）。config 加入
`SUBDIRS` 是第 08 章唯一的构建系统改动。

### [25-45] 三类源与三份清单

```make
SRCS    := $(wildcard *.c) $(foreach d,$(SUBDIRS),$(wildcard $(d)/*.c))
OBJS    := $(patsubst %.c,$(BUILD)/%.o,$(SRCS))

# 单测: 每个 unittest/xxx.c 自己带 main, 单独链成 build/<arch>/unittest/xxx,
# 链接时带上除 main.o 外的全部 .o。unittest 不进 SUBDIRS, 否则它的 main
# 会被链进 product_tool 和 main.c 撞车。
TEST_SRCS := $(wildcard unittest/*.c)
TESTS     := $(patsubst %.c,$(BUILD)/%,$(TEST_SRCS))
LIB_OBJS  := $(filter-out $(BUILD)/main.o,$(OBJS))

# 测试项程序(items/): 08/09 章的独立小工具(i2c 读光感、串口收发),
# 只链 common.o, 不带层和 FreeType -- 它们就是普通的应用编程练习,
# 上板单发。items 也不进 SUBDIRS。
ITEM_SRCS := $(wildcard items/*.c)
ITEMS     := $(patsubst %.c,$(BUILD)/%,$(ITEM_SRCS))

DEPS    := $(OBJS:.o=.d) $(TESTS:=.d) $(ITEMS:=.d)
```

三个 wildcard 各管一类 main：`SRCS` 里的 main.c 归 product_tool，
`TEST_SRCS` 每个文件自带 main，`ITEM_SRCS` 同理。判据 [4]"改
common.h 全量重编"的计数 = `NSRC`（core 判据里 find 出的、不含
unittest 与 items 的 .c 数），依赖 `.d` 文件把头文件依赖挂到每个
目标上——items 也依赖 common.h，所以它的 `.d` 必须进 `DEPS`，
否则 [4] 的重编数对不上。

### [47-71] FreeType 与编译选项

```make
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
LDFLAGS  := $(LDFLAGS_EXTRA)
LDLIBS   :=
override LDLIBS += $(FREETYPE_LIBS)
# 读取线程在 input 层内部; -pthread 放在 override 里, 命令行 LDFLAGS=-static
# 覆盖 LDFLAGS 本体时也保得住。
override LDFLAGS += -pthread
```

两个 `override` 是本章的关键新增。`override LDFLAGS += -pthread`：
命令行 `make LDFLAGS=-static`（板上产物必需，TechReports 03 记过
glibc 版本冲突）会替换 `LDFLAGS :=` 的赋值，`override` 的 `+=`
在命令行赋值之后追加，两种取值下链接命令都带 `-pthread`。判据 [17]
的 tsan 构建走 `LDFLAGS_EXTRA`/`CFLAGS_EXTRA`，与 sanitizer 的
既有用法（判据 [9] 的 ASan）一致。

### [73-135] 规则区

```make
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

test: $(TESTS) $(ITEMS)

$(BUILD)/unittest/%: $(BUILD)/unittest/%.o $(LIB_OBJS)
	@mkdir -p $(dir $@)
	@echo "  LD    $@"
	$(Q)$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

$(BUILD)/items/%: $(BUILD)/items/%.o $(BUILD)/common.o
	@mkdir -p $(dir $@)
	@echo "  LD    $@"
	$(Q)$(CC) $(LDFLAGS) -o $@ $^

# -MMD 顺带生成 .d 文件, 内容是 "xxx.o: xxx.c a.h b.h ...", 实现头文件自动依赖
# -MP  为每个头文件补一条空规则, 这样删掉一个头文件时 make 不会报 No rule to make target
$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "  CC    $<"
	$(Q)$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c -o $@ $<

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

三条链接规则三种料：product_tool 吃全部 OBJS 加 LDLIBS（FreeType 在内）；
unittest 吃 `LIB_OBJS`（除 main.o）加 LDLIBS——netinput_send 因此也
带着七层代码，3.2MB 的 ARM 产物里九成不是它的；items 只吃 common.o，
不带 FreeType，0.5MB，串口上传时间从三分钟降到四十秒。ARM 段的
FreeType 隔离构建与 stamp 依赖照旧；`$(BIN) $(TESTS): | $(FT_STAMP)`
的 order-only 前置保证 stamp 只触发 FreeType 目录存在性检查，不参与
时间戳比较。

## 3. 执行顺序

| 步 | `make`（x86 默认） | `make CROSS=arm-linux-gnueabihf- LDFLAGS=-static` |
|---|---|---|
| 变量 | ARCH=x86，FreeType 走 pkg-config | ARCH=arm，FreeType 指向隔离 stage |
| 编译 | build/x86/ 下全部 .o（含 config/） | build/arm/ 下全部 .o（静态，-pthread 由 override 保留） |
| 链接 | product_tool + LDLIBS | FT_STAMP 不在 → 先解包构建 FreeType → 再链 |
| test | make test 补 7 单测 + 2 items | 同规则静态版，判据 [2] 验 Machine=ARM |

## 4. 容易读错的地方

1. **命令行变量压过普通赋值**：`make LDFLAGS=-static` 不报错也不警告，
   `LDFLAGS :=` 静默失效——所有必须活过命令行覆盖的旗标都得走
   `override`，目前两个：FreeType 库（LDLIBS）与 pthread（LDFLAGS）。
2. **unittest 与 items 都不进 SUBDIRS**：两个目录里都有 main，进了
   就和 main.c 撞车；[4] 的重编计数也依赖这个排除（find 不算它们的
   .c）。
3. **`$(TESTS)` 依赖 `$(FT_STAMP)` 而 items 不依赖**：items 不碰
   FreeType，ARM 上第一次构建时它们不需要等解包编译，`make test`
   的关键路径因此短一截。

## 5. 消费者清单

| 消费者 | 用到的目标/变量 |
|---|---|
| 判据脚本（三个 check） | all/test/clean/distclean、CFLAGS_EXTRA、LDFLAGS_EXTRA、FT_TARBALL |
| TechReports 07 | `override LDFLAGS += -pthread` 的裁定记录 |
| TechReports 08 | SUBDIRS 加 config、items 链接规则 |
