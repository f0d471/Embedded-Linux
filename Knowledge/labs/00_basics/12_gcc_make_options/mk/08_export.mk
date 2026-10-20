# export 的变量，递归调用的 make 才看得到
TOPDIR := $(shell pwd)
CC := gcc
export TOPDIR

recurse:
	@$(MAKE) -C sub show
