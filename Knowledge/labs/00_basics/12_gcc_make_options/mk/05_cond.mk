# ifeq / ifneq / ifdef 三种条件
ARCH := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),x86)

ifeq ($(ARCH),arm)
  MSG := cross build for arm
else ifeq ($(ARCH),x86)
  MSG := native build for x86
else
  MSG := unknown arch
endif

ifdef V
  Q :=
else
  Q := @
endif

show:
	@echo "ARCH=$(ARCH) MSG=$(MSG)"
ifneq ($(V),)
	@echo "verbose mode"
endif
