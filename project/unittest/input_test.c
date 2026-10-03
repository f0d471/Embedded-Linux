/* input 层单测：同一程序既能读文本回放，也能在板上 probe/读取真实 evdev。 */

#include <stdio.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"
#include "input/input_manager.h"

int main(int argc, char **argv)
{
	const struct input_source_info *info;
	struct input_event_data event;
	int ret;
	int timeout = 0;

	if (display_init() != ERR_OK || input_init() != ERR_OK)
		return 1;
	info = input_get_source_info();
	printf("source name=%s path=%s rel=%d abs=%d keys=%d"
	       " xrange=%d..%d yrange=%d..%d\n",
	       info->name, info->path, info->has_relative, info->has_absolute,
	       info->has_keys, info->abs_x_min, info->abs_x_max,
	       info->abs_y_min, info->abs_y_max);

	if (argc > 1 && strcmp(argv[1], "--probe") == 0)
		goto out;
	if (argc > 1 && strcmp(argv[1], "--once") == 0)
		timeout = 5000;

	for (;;) {
		ret = input_get_event(&event, timeout);
		if (ret == ERR_NOTFOUND || ret == ERR_BUSY)
			break;
		if (ret != ERR_OK)
			return 2;
		if (event.kind == INPUT_KIND_POINTER) {
			printf("pointer x=%d y=%d dx=%d dy=%d buttons=%u\n",
			       event.x, event.y, event.dx, event.dy, event.buttons);
		} else {
			printf("key code=%u value=%d\n", event.code, event.value);
		}
		if (timeout > 0)
			break;
	}

out:
	input_exit();
	display_exit();
	return 0;
}
