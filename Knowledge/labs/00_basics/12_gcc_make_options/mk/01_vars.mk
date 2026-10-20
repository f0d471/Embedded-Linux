# 五种赋值方式摆在一起：定义时定死还是使用时才算
# 注意 C 在第 8 行才定义，A/B/G/H 都在它之前
A = $(C)
B := $(C)

G = a
G += $(C)
H := a
H += $(C)

C = later

D = file_value
D ?= second

E ?= first_seen

define F
one_line_$(C)
endef

show:
	@echo "A(=)        = [$(A)]"
	@echo "B(:=)       = [$(B)]"
	@echo "G(= 后 +=)  = [$(G)]"
	@echo "H(:= 后 +=) = [$(H)]"
	@echo "D(?=)       = [$(D)]"
	@echo "E(?=)       = [$(E)]"
	@echo "F(define)   = [$(F)]"
