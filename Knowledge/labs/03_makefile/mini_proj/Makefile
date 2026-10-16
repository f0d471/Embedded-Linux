# mini_proj 的 Makefile —— 五步演进的第 5 步（最终形态）
# 第 1 步 全部写死        四条编译规则 + 一条链接规则,一个变量都没有
# 第 2 步 变量与模式规则   CC/CFLAGS 提成变量,四条编译规则塌缩成 %.o: %.c
# 第 3 步 自动收集源文件   SRCS := $(wildcard *.c),加文件不改 Makefile
# 第 4 步 头文件自动依赖   编译加 -MMD,结尾 -include 读回 .d
# 第 5 步 交叉编译        CROSS ?= 空缺省,命令行传前缀
#
# 每一步的写法与验证见教程 03 篇 3.5 节,这里是五步全做完的样子。

CROSS   ?=
CC      := $(CROSS)gcc
CFLAGS  := -O2 -Wall -Wextra

SRCS := $(wildcard *.c)
OBJS := $(SRCS:.c=.o)
DEPS := $(OBJS:.o=.d)

app: $(OBJS)
	$(CC) $(OBJS) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -MMD -c -o $@ $<

clean:
	rm -f $(OBJS) $(DEPS) app

.PHONY: clean
-include $(DEPS)
