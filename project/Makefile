# 量产工具项目顶层 Makefile
#
# 用法:
#   make                                本地 x86 版, 产物 build/x86/product_tool
#   make CROSS=arm-linux-gnueabihf-     ARM  版,    产物 build/arm/product_tool
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
DEPS    := $(OBJS:.o=.d)

# -I. 让跨层引用写成 "display/disp_manager.h", 一眼看得出是跨层
CFLAGS  := -Wall -Wextra -O2 -I. -Iinclude $(CFLAGS_EXTRA)
LDFLAGS :=
LDLIBS  :=

ifeq ($(V),1)
  Q :=
else
  Q := @
endif

.PHONY: all clean distclean show

all: $(BIN)

$(BIN): $(OBJS)
	@mkdir -p $(dir $@)
	@echo "  LD    $@"
	$(Q)$(CC) $(LDFLAGS) -o $@ $^ $(LDLIBS)

# -MMD 顺带生成 .d 文件, 内容是 "xxx.o: xxx.c a.h b.h ...", 实现头文件自动依赖
# -MP  为每个头文件补一条空规则, 这样删掉一个头文件时 make 不会报 No rule to make target
$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	@echo "  CC    $<"
	$(Q)$(CC) $(CFLAGS) -MMD -MP -c -o $@ $<

# -include 对不存在的文件不报错, 所以第一次编译时不需要再套一层 wildcard 过滤
-include $(DEPS)

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
