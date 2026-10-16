# 顶层 Makefile —— 通用 Makefile（内核那套递归构建）的教学复现
# 设计思想（3.6 节）:
#   1. 每个目录一份 Makefile,里面只用 obj-y 声明"编哪些文件、进哪些目录"
#   2. 顶层一份 Makefile.build 当递归引擎,make -f 反复调它,一次处理一个目录
#   3. 每个目录的 .o 用 ld -r 合并成 built-in.o,层层向上,最后链接成程序
#
# 用法:  make            编出 app
#        make clean      清全部产物(含各层 built-in.o 与隐藏 .d)

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
