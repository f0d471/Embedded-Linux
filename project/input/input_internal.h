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
	int  (*get_fd)(void);
	int  (*read_raw)(struct input_raw_event *out);
	struct input_provider *next;
};

void input_register(struct input_provider *provider);
void evdev_register(void);
void replay_register(void);

#endif /* __INPUT_INTERNAL_H */
