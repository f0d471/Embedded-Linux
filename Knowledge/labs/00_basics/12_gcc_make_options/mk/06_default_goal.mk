# .DEFAULT_GOAL 把默认目标钉死在 all 上
.DEFAULT_GOAL := all

include 06b_rules.mk

all:
	@echo "real default goal runs"
