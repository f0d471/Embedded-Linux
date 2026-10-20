# -include：文件不存在不报错
DEPS := not_exist_1.d not_exist_2.d
-include $(DEPS)

show:
	@echo "included nothing, still fine"
