#include <errno.h>
#include <limits.h>
#include <linux/input.h>
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "common.h"
#include "display/disp_manager.h"
#include "input/input_internal.h"
#include "input/input_manager.h"

static struct input_provider *g_list;
static struct input_provider *g_cur;
static struct input_source_info g_info;
static int g_inited;
static int g_width;
static int g_height;
static int g_x;
static int g_y;
static unsigned int g_buttons;

static int g_frame_dx;
static int g_frame_dy;
static int g_abs_x;
static int g_abs_y;
static int g_have_abs_x;
static int g_have_abs_y;
static int g_pointer_changed;
static int g_key_code = -1;
static int g_key_value;
static int g_dropping;

void input_register(struct input_provider *provider)
{
	if (provider == NULL || provider->name == NULL)
		return;
	provider->next = g_list;
	g_list = provider;
}

static struct input_provider *input_find(const char *name)
{
	struct input_provider *p;

	for (p = g_list; p != NULL; p = p->next)
		if (strcmp(p->name, name) == 0)
			return p;
	return NULL;
}

static void reset_frame(void)
{
	g_frame_dx = 0;
	g_frame_dy = 0;
	g_have_abs_x = 0;
	g_have_abs_y = 0;
	g_pointer_changed = 0;
	g_key_code = -1;
	g_key_value = 0;
}

static int clamp_value(int value, int limit)
{
	if (value < 0)
		return 0;
	if (value >= limit)
		return limit - 1;
	return value;
}

static int scale_abs(int value, int min, int max, int limit)
{
	int64_t numerator;

	if (max <= min)
		return clamp_value(value, limit);
	if (value < min)
		value = min;
	if (value > max)
		value = max;
	numerator = (int64_t)(value - min) * (limit - 1);
	return (int)(numerator / (max - min));
}

static unsigned int button_mask(unsigned int code)
{
	switch (code) {
	case BTN_LEFT:
	case BTN_TOUCH:
		return INPUT_BUTTON_LEFT;
	case BTN_RIGHT:
		return INPUT_BUTTON_RIGHT;
	case BTN_MIDDLE:
		return INPUT_BUTTON_MIDDLE;
	default:
		return 0;
	}
}

/* 返回 1 表示一个以 SYN_REPORT 封口的应用事件已经产出。 */
static int parse_raw(const struct input_raw_event *raw, struct input_event_data *out)
{
	unsigned int mask;

	if (raw->type == EV_SYN && raw->code == SYN_DROPPED) {
		/* 内核已丢记录：此前半帧和下一次 REPORT 前的记录都不再可信。 */
		reset_frame();
		g_buttons = 0;
		g_dropping = 1;
		return 0;
	}
	if (g_dropping) {
		if (raw->type == EV_SYN && raw->code == SYN_REPORT)
			g_dropping = 0;
		return 0;
	}

	if (raw->type == EV_REL) {
		if (raw->code == REL_X) {
			g_frame_dx += raw->value;
			g_pointer_changed = 1;
		} else if (raw->code == REL_Y) {
			g_frame_dy += raw->value;
			g_pointer_changed = 1;
		}
	} else if (raw->type == EV_ABS) {
		if (raw->code == ABS_X || raw->code == ABS_MT_POSITION_X) {
			g_abs_x = raw->value;
			g_have_abs_x = 1;
			g_pointer_changed = 1;
		} else if (raw->code == ABS_Y || raw->code == ABS_MT_POSITION_Y) {
			g_abs_y = raw->value;
			g_have_abs_y = 1;
			g_pointer_changed = 1;
		}
	} else if (raw->type == EV_KEY) {
		mask = button_mask(raw->code);
		if (mask != 0) {
			if (raw->value)
				g_buttons |= mask;
			else
				g_buttons &= ~mask;
			g_pointer_changed = 1;
		} else {
			g_key_code = raw->code;
			g_key_value = raw->value;
		}
	}

	if (raw->type != EV_SYN || raw->code != SYN_REPORT)
		return 0;

	memset(out, 0, sizeof(*out));
	out->sec = raw->sec;
	out->usec = raw->usec;
	if (g_pointer_changed) {
		if (g_have_abs_x)
			g_x = scale_abs(g_abs_x, g_info.abs_x_min, g_info.abs_x_max, g_width);
		else
			g_x = clamp_value(g_x + g_frame_dx, g_width);
		if (g_have_abs_y)
			g_y = scale_abs(g_abs_y, g_info.abs_y_min, g_info.abs_y_max, g_height);
		else
			g_y = clamp_value(g_y + g_frame_dy, g_height);
		out->kind = INPUT_KIND_POINTER;
		out->x = g_x;
		out->y = g_y;
		out->dx = g_frame_dx;
		out->dy = g_frame_dy;
		out->buttons = g_buttons;
		reset_frame();
		return 1;
	}
	if (g_key_code >= 0) {
		out->kind = INPUT_KIND_KEY;
		out->code = (unsigned int)g_key_code;
		out->value = g_key_value;
		reset_frame();
		return 1;
	}
	reset_frame();
	return 0;
}

static int64_t monotonic_ms(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
		return 0;
	return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int input_init(void)
{
	const struct disp_buf *display;
	const char *name;
	int ret;

	if (g_inited)
		return ERR_OK;
	g_list = NULL;
	evdev_register();
	replay_register();

	name = getenv("INPUT_BACKEND");
	if (name == NULL)
		name = getenv("INPUT_REPLAY") != NULL ? "replay" : "evdev";
	g_cur = input_find(name);
	if (g_cur == NULL)
		return ERR_NOTFOUND;

	memset(&g_info, 0, sizeof(g_info));
	ret = g_cur->open(&g_info);
	if (ret != ERR_OK) {
		g_cur = NULL;
		return ret;
	}

	display = disp_get_buf();
	g_width = display != NULL && display->xres > 0 ? display->xres : 1;
	g_height = display != NULL && display->yres > 0 ? display->yres : 1;
	g_x = g_width / 2;
	g_y = g_height / 2;
	g_buttons = 0;
	g_dropping = 0;
	reset_frame();
	g_inited = 1;
	LOG_INFO("input init OK");
	return ERR_OK;
}

void input_exit(void)
{
	if (!g_inited)
		return;
	g_cur->close();
	g_cur = NULL;
	g_list = NULL;
	g_inited = 0;
	g_dropping = 0;
	reset_frame();
	LOG_INFO("input exit OK");
}

const struct input_source_info *input_get_source_info(void)
{
	return g_inited ? &g_info : NULL;
}

int input_get_event(struct input_event_data *out, int timeout_ms)
{
	struct input_raw_event raw;
	struct pollfd pfd;
	int64_t deadline = 0;
	int wait_ms, ret;

	if (!g_inited || out == NULL || timeout_ms < -1)
		return ERR_PARAM;
	if (timeout_ms >= 0)
		deadline = monotonic_ms() + timeout_ms;

	for (;;) {
		if (timeout_ms < 0) {
			wait_ms = -1;
		} else {
			int64_t remain = deadline - monotonic_ms();
			if (remain < 0)
				remain = 0;
			wait_ms = remain > INT_MAX ? INT_MAX : (int)remain;
		}
		pfd.fd = g_cur->get_fd();
		pfd.events = POLLIN;
		pfd.revents = 0;
		ret = poll(&pfd, 1, wait_ms);
		if (ret == 0)
			return ERR_BUSY;
		if (ret < 0) {
			if (errno == EINTR)
				continue;
			return ERR_IO;
		}

		ret = g_cur->read_raw(&raw);
		if (ret == ERR_BUSY)
			continue;
		if (ret != ERR_OK)
			return ret;
		if (parse_raw(&raw, out))
			return ERR_OK;
	}
}
