#ifndef __INPUT_INTERNAL_H
#define __INPUT_INTERNAL_H

#include <stdint.h>

#include "input/input_manager.h"

struct input_raw_event {
	int64_t sec;
	int64_t usec;
	uint16_t type;
	uint16_t code;
	int32_t value;
};

struct input_provider {
	const char *name;
	int  (*open)(struct input_source_info *out);
	void (*close)(void);
	/* 把本轮 poll 要监听的 fd 填进 fds, 返回个数。netinput 这类
	 * "监听 + 客户端" 的后端, 个数会随连接的建立与断开变化。 */
	int  (*get_fds)(int *fds, int max);
	int  (*read_raw)(struct input_raw_event *out);
	struct input_provider *next;
};

void input_register(struct input_provider *provider);
void evdev_register(void);
void replay_register(void);
void netinput_register(void);

#endif /* __INPUT_INTERNAL_H */
