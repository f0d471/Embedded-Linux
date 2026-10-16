# a/ 目录的 Makefile:只声明编哪些文件,外加本目录/单文件编译选项

obj-y += sub2.o
obj-y += sub3.o

EXTRA_CFLAGS := -DDEBUG            # 本目录每个 .c 都带
CFLAGS_sub3.o := -DDEBUG_SUB3      # 只有 sub3.o 带
