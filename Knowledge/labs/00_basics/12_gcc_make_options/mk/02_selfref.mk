# 延时变量引用自己：报错现场
Y = $(Y) foo

show:
	@echo $(Y)
