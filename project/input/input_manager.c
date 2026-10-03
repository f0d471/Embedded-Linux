#include <errno.h>
#include <limits.h>
#include <linux/input.h>
#include <poll.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "common.h"
#include "display/disp_manager.h"
#include "input/input_internal.h"
#include "input/input_manager.h"

/*
 * 读取线程 + 环形队列。
 *
 * provider 的 fd 由专职线程 poll 和解析, 产出应用事件后推进队列;
 * 消费者(input_get_event)只跟队列打交道。这样做的代价是多一把锁和一个
 * 线程生命周期要管理, 换来的是: 消费者慢的时候采集不丢采样时机,
 * 丢的是队列里最旧的事件, 而且丢了几个、送达了几个都有账可查。
 *
 * 队列满的策略是丢最旧: 输入事件的价值随时间衰减, 最新的指针位置
 * 比一秒前的按键更值得保留。丢弃量记在 g_dropped, 判据对账用。
 */

#define INPUT_QUEUE_DEPTH 32

/* 队列第 i 个槽位对应的物理下标 */
#define SLOT(i) ((i) % INPUT_QUEUE_DEPTH)

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

/* 队列与线程。g_lock 保护下面整块, 以及 cond 的谓词。 */
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_not_empty;          /* 时钟绑定见 input_init */
static pthread_t g_thread;
static struct input_event_data g_queue[INPUT_QUEUE_DEPTH];
static int g_head;                          /* 下一个写入槽 */
static int g_tail;                          /* 下一个读取槽 */
static int g_count;                         /* 队列里的可用事件数 */
static int g_quit;                          /* input_exit 请求线程退出 */
static int g_closed;                        /* provider 已到 EOF, 不会再有数据 */
static int g_error;                         /* provider 的致命错误, 消费时要穿透 */
static int g_received;
static int g_delivered;
static int g_dropped;

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

/* 推送一个应用事件。队列满时丢最旧的一个, 账记在 g_dropped。 */
static void queue_push(const struct input_event_data *ev)
{
	pthread_mutex_lock(&g_lock);
	if (g_count == INPUT_QUEUE_DEPTH) {
		g_tail = SLOT(g_tail + 1);
		g_count--;
		g_dropped++;
	}
	g_queue[SLOT(g_head)] = *ev;
	g_head = SLOT(g_head + 1);
	g_count++;
	g_received++;
	pthread_cond_signal(&g_not_empty);
	pthread_mutex_unlock(&g_lock);
}

/* 读取线程: poll provider 的 fd, 解析原始记录, 把应用事件推进队列。
 * provider 到 EOF 或出错时记下原因并通知消费者, 然后线程收场。 */
static void *input_reader(void *arg)
{
	struct input_raw_event raw;
	struct input_event_data ev;
	struct pollfd pfds[8];
	int fds[8];
	int nfds, ret;

	(void)arg;
	while (!g_quit) {
		nfds = g_cur->get_fds(fds, 8);
		if (nfds < 1) {
			g_error = ERR_IO;
			break;
		}
		for (ret = 0; ret < nfds; ret++) {
			pfds[ret].fd = fds[ret];
			pfds[ret].events = POLLIN;
			pfds[ret].revents = 0;
		}
		/* 200ms 醒一次看 g_quit: 退出请求最多等一个 poll 周期 */
		ret = poll(pfds, nfds, 200);
		if (g_quit)
			break;
		if (ret == 0)
			continue;
		if (ret < 0) {
			if (errno == EINTR)
				continue;
			g_error = ERR_IO;
			break;
		}

		ret = g_cur->read_raw(&raw);
		if (ret == ERR_BUSY)
			continue;
		if (ret == ERR_NOTFOUND)
			break;              /* replay 读到文件尾, 正常收场 */
		if (ret != ERR_OK) {
			g_error = ret;
			break;
		}
		if (parse_raw(&raw, &ev))
			queue_push(&ev);
	}

	pthread_mutex_lock(&g_lock);
	g_closed = 1;
	pthread_cond_broadcast(&g_not_empty);
	pthread_mutex_unlock(&g_lock);
	return NULL;
}

int input_init(void)
{
	pthread_condattr_t attr;
	const struct disp_buf *display;
	const char *name;
	int ret;

	if (g_inited)
		return ERR_OK;
	g_list = NULL;
	evdev_register();
	replay_register();
	netinput_register();

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

	g_head = 0;
	g_tail = 0;
	g_count = 0;
	g_quit = 0;
	g_closed = 0;
	g_error = 0;
	g_received = 0;
	g_delivered = 0;
	g_dropped = 0;

	/* 超时判据用 CLOCK_MONOTONIC 的毫秒数算期限, cond 也要绑到同一个
	 * 时钟上, pthread_cond_timedwait 的绝对期限才不会两套时间对不上。 */
	pthread_condattr_init(&attr);
	pthread_condattr_setclock(&attr, CLOCK_MONOTONIC);
	pthread_cond_init(&g_not_empty, &attr);
	pthread_condattr_destroy(&attr);

	ret = pthread_create(&g_thread, NULL, input_reader, NULL);
	if (ret != 0) {
		g_cur->close();
		g_cur = NULL;
		return ERR_NOMEM;
	}

	g_inited = 1;
	LOG_INFO("input init OK");
	return ERR_OK;
}

void input_exit(void)
{
	if (!g_inited)
		return;
	pthread_mutex_lock(&g_lock);
	g_quit = 1;
	pthread_cond_broadcast(&g_not_empty);
	pthread_mutex_unlock(&g_lock);
	pthread_join(g_thread, NULL);

	g_cur->close();
	g_cur = NULL;
	g_list = NULL;
	g_inited = 0;
	g_quit = 0;
	g_closed = 0;
	g_error = 0;
	g_count = 0;
	g_head = 0;
	g_tail = 0;
	g_received = 0;
	g_delivered = 0;
	g_dropped = 0;
	g_dropping = 0;
	reset_frame();
	LOG_INFO("input exit OK");
}

const struct input_source_info *input_get_source_info(void)
{
	return g_inited ? &g_info : NULL;
}

int input_get_stats(struct input_stats *out)
{
	if (out == NULL)
		return ERR_PARAM;
	pthread_mutex_lock(&g_lock);
	out->received = g_received;
	out->delivered = g_delivered;
	out->dropped = g_dropped;
	pthread_mutex_unlock(&g_lock);
	return ERR_OK;
}

int input_get_event(struct input_event_data *out, int timeout_ms)
{
	int64_t deadline = 0;
	int64_t remain;
	struct timespec until;
	int ret = ERR_OK;

	if (!g_inited || out == NULL || timeout_ms < -1)
		return ERR_PARAM;
	if (timeout_ms >= 0)
		deadline = monotonic_ms() + timeout_ms;

	pthread_mutex_lock(&g_lock);
	for (;;) {
		if (g_count > 0) {
			*out = g_queue[SLOT(g_tail)];
			g_tail = SLOT(g_tail + 1);
			g_count--;
			g_delivered++;
			break;
		}
		if (g_error != 0) {
			ret = g_error;
			break;
		}
		if (g_closed) {
			ret = ERR_NOTFOUND;
			break;
		}
		if (timeout_ms == 0) {
			ret = ERR_BUSY;
			break;
		}
		if (timeout_ms < 0) {
			pthread_cond_wait(&g_not_empty, &g_lock);
			continue;
		}
		remain = deadline - monotonic_ms();
		if (remain <= 0) {
			ret = ERR_BUSY;
			break;
		}
		until.tv_sec = (time_t)(deadline / 1000);
		until.tv_nsec = (long)(deadline % 1000) * 1000000L;
		pthread_cond_timedwait(&g_not_empty, &g_lock, &until);
	}
	pthread_mutex_unlock(&g_lock);
	return ret;
}
