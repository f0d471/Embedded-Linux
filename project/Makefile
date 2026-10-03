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
