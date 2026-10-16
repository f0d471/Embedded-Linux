/* input 层单测：同一程序既能读文本回放，也能在板上 probe/读取真实 evdev。 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "common.h"
#include "display/disp_manager.h"
#include "input/input_manager.h"

int main(int argc, char **argv)
{
	const struct input_source_info *info;
	struct input_event_data event;
	int ret;
	int wait_ms = 0;   /* 每次取事件的最长等待; 0 = 只看现有数据 */
	int limit = 0;     /* 取满多少个事件后退出; 0 = 不限 */
	int slow_us = 0;   /* 每取一个事件睡多久, 模拟慢消费者 */
	int done = 0;
	int i;

	if (display_init() != ERR_OK || input_init() != ERR_OK)
		return 1;
	info = input_get_source_info();
	printf("source name=%s path=%s rel=%d abs=%d keys=%d"
	       " xrange=%d..%d yrange=%d..%d\n",
	       info->name, info->path, info->has_relative, info->has_absolute,
	       info->has_keys, info->abs_x_min, info->abs_x_max,
	       info->abs_y_min, info->abs_y_max);

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--probe") == 0) {
			goto out;
		} else if (strcmp(argv[i], "--once") == 0) {
			wait_ms = 5000;
			limit = 1;
		} else if (strcmp(argv[i], "--wait") == 0 && i + 1 < argc) {
			wait_ms = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--count") == 0 && i + 1 < argc) {
			limit = atoi(argv[++i]);
		} else if (strcmp(argv[i], "--slow") == 0 && i + 1 < argc) {
			slow_us = atoi(argv[++i]);
		}
	}

	for (;;) {
		ret = input_get_event(&event, wait_ms);
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
		done++;
		if (slow_us > 0)
			usleep((useconds_t)slow_us);
		if (limit > 0 && done >= limit)
			break;
	}

	{
		struct input_stats stats;

		if (input_get_stats(&stats) == ERR_OK)
			printf("stats received=%d delivered=%d dropped=%d\n",
			       stats.received, stats.delivered, stats.dropped);
	}

out:
	input_exit();
	display_exit();
	return 0;
}
