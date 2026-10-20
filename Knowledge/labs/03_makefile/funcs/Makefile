# 本篇主线用到的函数,每个一行。目录里真实存在 a.c b.c c.h,没有 ghost.c。
# 用法: make            看每个函数的输出
#       make CROSS=arm-linux-gnueabihf-   看 arch 的变化

files := $(wildcard *.c)
ask   := $(wildcard a.c b.c ghost.c)

objs  := $(files:.c=.o)
objs2 := $(patsubst %.c,%.o,$(files) read.me)

mixed := src/ include/ main.o
dirs  := $(filter %/,$(mixed))
plain := $(filter-out %/,$(mixed))

deps  := $(foreach f,$(objs),.$(f).d)

arch  := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),x86)

top   := $(shell pwd)

all:
	@echo files  = $(files)
	@echo ask    = $(ask)
	@echo objs   = $(objs)
	@echo objs2  = $(objs2)
	@echo dirs   = $(dirs)
	@echo plain  = $(plain)
	@echo deps   = $(deps)
	@echo arch   = $(arch)
	@echo top    = $(top)

.PHONY: all
