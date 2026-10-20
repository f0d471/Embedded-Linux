# mini_proj 的 Makefile,五步走完的样子:
#   第 3 步 自动收集源文件   SRCS := $(wildcard *.c),加文件不改本文件
#   第 4 步 头文件自动依赖   编译加 -MMD,结尾 -include 读回 .d
#   第 5 步 交叉编译         CROSS ?= 空缺省,命令行传前缀
# 第 0～2 步与中间形态在 steps/ 下,各自可用 make -f steps/stepN/Makefile 单独跑。
# 每一步的来历见教程 03 篇第 1、3、4、5、6 节。

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
