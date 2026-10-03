#ifndef __INPUT_MANAGER_H
#define __INPUT_MANAGER_H

#include <stdint.h>

enum input_kind {
	INPUT_KIND_POINTER = 1,
	INPUT_KIND_KEY = 2,
};

enum input_button {
	INPUT_BUTTON_LEFT   = 1u << 0,
	INPUT_BUTTON_RIGHT  = 1u << 1,
	INPUT_BUTTON_MIDDLE = 1u << 2,
};

struct input_event_data {
	int64_t sec;
	int64_t usec;
	enum input_kind kind;
	int x;
	int y;
	int dx;
	int dy;
	unsigned int buttons;
	unsigned int code;
	int value;
};

struct input_source_info {
	char name[64];
	char path[128];
	int has_relative;
	int has_absolute;
	int has_keys;
	int abs_x_min;
	int abs_x_max;
	int abs_y_min;
	int abs_y_max;
};

int  input_init(void);
void input_exit(void);

/* timeout_ms: -1 永久等待，0 只检查现有数据，正数为最长等待毫秒数。 */
int input_get_event(struct input_event_data *out, int timeout_ms);
const struct input_source_info *input_get_source_info(void);

#endif /* __INPUT_MANAGER_H */
