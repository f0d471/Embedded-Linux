# 自动变量在同一条规则里各是什么
# 先 touch a.txt b.txt c.txt 再 make -f 03_autovar.mk
all: a.txt b.txt c.txt
	@echo '$$@ = $@'
	@echo '$$< = $<'
	@echo '$$^ = $^'
	@echo '$$? = $?'
	@touch $@
