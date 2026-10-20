# 变量四件事:两种时机、两种修饰。
#   :=  定义那一刻就展开右边,值当场定死
#   =   用到那一刻才展开右边
#   ?=  只在这个变量从没被定义过时生效(延时)
#   +=  追加;是即时还是延时,跟着这个变量前面的定义走
#
# 用法: make            看 A/B/C 的差别
#       make D=cmdline  命令行变量覆盖文件里的赋值,?= 挡不住
#       make show       延时变量在命令里展开,能拿到 $@
#       make prereq     规则的依赖在读取那一刻展开

A := $(C)
B = $(C)
C := abc

D := first
D ?= second
E ?= first

X := abc
X += def

all:
	@echo A=[$(A)]
	@echo B=[$(B)]
	@echo C=[$(C)]
	@echo D=[$(D)]
	@echo E=[$(E)]
	@echo X=[$(X)]

VAL = $@
show:
	@echo VAL=[$(VAL)]

LIST = one
prereq: $(LIST)
	@echo prereq 展开成了 $^, 而 LIST 现在是 $(LIST)
LIST = two

.PHONY: all show prereq
