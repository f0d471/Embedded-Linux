# input 层逐行精读

代码路径与总行数（`grep -n ''` 于 2026-10-04 核对）：

```
input/input_manager.c    460 行   manager: 帧聚合 + 读取线程 + 环形队列
input/input_manager.h     57 行   对外接口
input/input_internal.h    32 行   provider 契约
input/netinput.c         221 行   网络输入源(第 06 章)
input/evdev.c            181 行   真实输入设备(第 05 章)
input/replay.c            84 行   文本回放(第 05 章)
```

前置知识见 [00-从零开始读写项目代码](00-从零开始读写项目代码.md) 与
`notes/01_应用编程/` 第 05/06/07 章；正文就地解释 `poll`、`pthread`、
`socket` 等语法，不把外部链接当理解门槛。

文件定位：input 层在 display 层之上、ui/page/business 之下。上游有三个
数据源——内核 evdev 子系统（`/dev/input/eventX`）、文本回放文件、TCP
对端——它们被统一翻译成应用事件交给上层。消费者：page 层（事件分发）、
business 层（主循环）、`unittest/input_test`、`unittest/netinput_send`
（协议另一端）。已知缺陷（同帧 pointer+key 丢键）登记在
[Bugs/01](../../Bugs/01-同帧指针与普通键丢事件.md)。

## input_manager.h：对外接口

```c
// input/input_manager.h  [1-57]
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

/* 队列对账: received = delivered + dropped 恒成立(同一次 init/exit 内)。 */
struct input_stats {
	int received;
	int delivered;
	int dropped;
};

int  input_init(void);
void input_exit(void);

/* timeout_ms: -1 永久等待，0 只检查现有数据，正数为最长等待毫秒数。 */
int input_get_event(struct input_event_data *out, int timeout_ms);
const struct input_source_info *input_get_source_info(void);
int  input_get_stats(struct input_stats *out);

#endif /* __INPUT_MANAGER_H */
```

`input_event_data` 是应用事件的全部字段：kind 选定 x/y/dx/dy/buttons
（指针）或 code/value（按键）哪一组有意义。第 07 章新增 `input_stats`：
三个计数的恒等式 `received = delivered + dropped` 是压力判据的根基，
恒等式成立的范围写在注释里——跨一次 `input_init`/`input_exit` 循环
它会被重置，比较账目必须在同一次生命周期内。

## input_internal.h：provider 契约

```c
// input/input_internal.h  [1-32]
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
```

`input_raw_event` 与内核 `struct input_event` 同构（五个数）。provider
五个动作在 `get_fds` 这一处与第 05 章不同：原 `get_fd()` 返回单个描述符，
netinput 任意时刻要监听"监听 socket + 零或一个客户端 socket"，个数是
动态的，契约改成"填数组、返回个数"。manager 每轮 poll 前重新调用一次，
连接的建立与断开自然反映为个数变化，poll 循环里没有 netinput 这个词。

## input_manager.c

### [15-30] 头注与 include

```c
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
```

头注释（15-30 行的块注释）交代本章模型：provider 的 fd 由专职线程 poll
和解析，产出的事件推进队列，消费者只跟队列打交道；代价是一把锁加一个
线程生命周期，换来采集不被慢消费者卡住、丢的是最旧事件且有账可查。

### [32-66] 两块状态

```c
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
```

```c
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
```

状态分三组、三个生命周期。跨帧状态（g_x/g_y/g_buttons）提交后保持，只有
init/exit 清；本帧暂存（g_frame_*、g_abs_*、g_key_*）每次提交事件后由
`reset_frame()` 清；队列状态（g_lock 起、g_dropped 止）全部受 g_lock
保护，其中 g_closed/g_error 是线程写给消费者看的收场标记——`g_error`
单独存在的原因在 TechReports 07 的 4.2 节：provider 的致命错误必须
穿透队列到达消费者，否则"读坏了"与"读完了"合并成一个返回码。

`parse_raw` 与这些帧状态只被读取线程触碰（第 07 章之后），消费者只动
队列——状态所有权的边界就是这把锁。

### [68-84] 注册与查找

```c
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
```

头插法注册链表，与 display 层同型。查找按名字线性扫，链表长度为 3。

### [86-134] 帧工具

```c
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
```

`scale_abs` 的 `int64_t` 中间值防 `量程 × 屏宽` 溢出（4095×1024 还在
32 位内，1920 宽屏加大量程就出界）。`button_mask` 把 `BTN_TOUCH`
并进左键位，是当前对触摸屏的简化契约。

### [136-218] parse_raw：SYN 帧聚合

```c
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
```

```c
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
```

```c
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
```

三段读法：第一段是丢弃状态机——`SYN_DROPPED` 表示内核丢过记录，此前
半帧与到下一个 REPORT 之间的记录全部不可信，`g_dropping` 置位后的
记录只用来识别解除标志；第二段按 type 分路累计本帧状态；第三段只在
`SYN_REPORT` 封口时产出事件，指针优先于按键（判据 [13] 的五行输出
钉死了这个次序），两者都没有则只清帧。提交时 `memset` 清 `out` 保证
未填字段（按键事件的 dx/dy 等）是零而不是栈垃圾。

### [220-246] monotonic_ms 与 queue_push

```c
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
```

队满挤旧：`g_tail` 前移一格等于扔掉最旧事件，然后新事件照常入队——
推送端永不阻塞、永不失败，代价是 `dropped` 加一。`SLOT(i)` 宏做环形
取模。`pthread_cond_signal` 在持锁期间发出是允许的（等待方醒来后
反正要重新拿锁），放锁前调用省一次上下文切换。

### [248-299] input_reader：读取线程

```c
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
```

与第 05 章同步循环的差别只有三处：轮询超时从"消费者给的期限"换成固定
200ms（让退出请求最多等一个周期，省掉一条自唤醒管道）；`ERR_NOTFOUND`
与错误分开记录（EOF 是正常收场，`g_error` 才是事故）；收场时加锁广播，
让所有等在 `cond` 上的消费者醒来重新查条件。`g_quit` 的读不在锁内——
它由 exit 置位、这里只读，`poll` 的 200ms 周期保证最迟 200ms 后能看见，
布尔标志在所有真实平台上不必为此加锁。

### [301-365] input_init

```c
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
```

顺序即依赖：注册三个 provider → 按 `INPUT_BACKEND`（缺省回落到
`INPUT_REPLAY` 是否设置）选一个 → open → 几何与状态清零 → cond 绑定
单调时钟 → 起线程。失败路径各回各的：找不到 provider 直接返回；open
失败关都关不了（open 自己没拿到资源）；线程建失败要把 provider 关掉再
返回——那一刻资源在 provider 手里。`g_inited` 最后置位，线程已经可能
在推事件，但队列状态先清好了，不依赖 g_inited。

### [367-398] input_exit

```c
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
```

停止协议三步：置位 → 唤醒（线程可能睡在 poll 或 cond 上）→ join。
join 在 close 之前，线程不会碰已关闭的 fd；broadcast 让可能等在
`input_get_event` 的消费者醒来。清理块的顺序与 init 相反，账目一并
归零——`received = delivered + dropped` 的恒等式只在 init 到 exit
之间有效。

### [400-460] 查询与取事件

```c
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
```

取事件循环的次序是契约：有数据先给数据；队列空时错误优先于 EOF
（`g_error` 是事故，`ERR_NOTFOUND` 是正常收场）；`timeout_ms == 0`
不等、`< 0` 无限期等、`> 0` 算到绝对期限。`cond_timedwait` 的期限
由 init 阶段绑定的单调时钟解释（3.2 节），虚假唤醒回到循环顶重查
条件，不产出任何东西。整个循环持锁——条件与队列状态同锁，等待期间
锁被 `cond_wait` 临时释放，这是 pthread 的约定而非代码写出来的。

## netinput.c：网络输入源

```c
// input/netinput.c  [15-47] 头注释与常量(节选断言)
#define NETINPUT_MAGIC      0x6e49
#define NETINPUT_DEFAULT_PORT 23232

struct netinput_record {
	uint16_t magic;
	uint16_t type;
	uint16_t code;
	uint16_t pad;
	int32_t  value;
	int32_t  sec;
	int32_t  usec;
} __attribute__((packed));

_Static_assert(sizeof(struct netinput_record) == 20,
	       "netinput wire record must stay 20 bytes");
```

20 字节定长小端记录，字段与 `input_raw_event` 同构加一个 magic。
`__attribute__((packed))` 消除填充之后仍显式留 pad 字段——它是格式
的一部分（线上第 6-7 字节），留名字比留洞清楚。静态断言把"字段一动
格式就变"钉在编译期，TechReports 06 的 4.1 节是它第一次生效的现场。

```c
// input/netinput.c  [55-113] open
static int set_nonblock(int fd)
{
	int flags = fcntl(fd, F_GETFL, 0);

	if (flags < 0)
		return -1;
	return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static int netinput_open(struct input_source_info *out)
{
	struct sockaddr_in addr;
	const char *port_str;
	long port;
	int fd;

	port_str = getenv("NETINPUT_PORT");
	port = port_str != NULL ? strtol(port_str, NULL, 10)
				: NETINPUT_DEFAULT_PORT;
	if (port <= 0 || port > 65535)
		return ERR_PARAM;

	fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0)
		return ERR_IO;
	if (set_nonblock(fd) < 0) {
		close(fd);
		return ERR_IO;
	}

	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_ANY);
	addr.sin_port = htons((uint16_t)port);
	/* SO_REUSEADDR: TIME_WAIT 里也能立刻重绑, 判据要连跑好几轮 */
	int one = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    listen(fd, 4) < 0) {
		close(fd);
		return ERR_IO;
	}

	g_listen = fd;
	g_client = -1;
	g_have = 0;

	memset(out, 0, sizeof(*out));
	snprintf(out->name, sizeof(out->name), "netinput");
	snprintf(out->path, sizeof(out->path), "tcp:0.0.0.0:%ld", port);
	out->has_relative = 1;
	out->has_absolute = 1;
	out->has_keys = 1;
	out->abs_x_min = 0;
	out->abs_x_max = 4095;
	out->abs_y_min = 0;
	out->abs_y_max = 4095;
	return ERR_OK;
}
```

服务端后端：`socket → set_nonblock → bind(SO_REUSEADDR) → listen`。
`SO_REUSEADDR` 让上一轮判据留在 `TIME_WAIT` 的端口能立刻重绑，没有它
连跑几轮判据会在 `bind` 上轮转着失败。能力位声明三种全有——来的是
鼠标还是按键取决于对端发什么。绝对量程声明 0..4095，与 replay 相同，
同一份 fixture 才能在两种后端上产出同样的缩放坐标。

```c
// input/netinput.c  [115-155] 连接管理与校验
static void netinput_drop_client(void)
{
	if (g_client >= 0) {
		close(g_client);
		g_client = -1;
	}
	g_have = 0;
}

static void netinput_close(void)
{
	netinput_drop_client();
	if (g_listen >= 0) {
		close(g_listen);
		g_listen = -1;
	}
}

static int netinput_get_fds(int *fds, int max)
{
	int n = 0;

	if (max < 1)
		return ERR_PARAM;
	fds[n++] = g_listen;
	if (g_client >= 0 && n < max)
		fds[n++] = g_client;
	return n;
}

/* 校验不过的记录说明对端不是本协议的客户端, 整条连接丢弃。 */
static int record_valid(const struct netinput_record *rec)
{
	if (rec->magic != NETINPUT_MAGIC)
		return 0;
	if (rec->type > EV_MAX || rec->code > KEY_MAX)
		return 0;
	if (rec->usec < 0 || rec->usec >= 1000000)
		return 0;
	return 1;
}
```

`get_fds` 每轮被 manager 重新调用：没有客户端时只监听 listen fd，
accept 成功后下一轮起客户端 fd 也进 poll 集。校验三项各挡一类字节流：
magic 挡"不是本协议"、type/code 范围挡"协议对但记录乱"、usec 范围挡
"半条旧记录拼半条新记录"。任何一项不过都断开整条连接——流式协议一旦
错位，没有重新对齐的办法，只能等下一个连接。

```c
// input/netinput.c  [157-208] read_raw
static int netinput_read_raw(struct input_raw_event *out)
{
	ssize_t got;

	if (out == NULL || g_listen < 0)
		return ERR_PARAM;

	/* 还没有客户端: 监听 fd 可读才走到这里, accept 一个进来。
	 * 本轮不产事件, 让下一轮 poll 把客户端 fd 也挂进监听集。 */
	if (g_client < 0) {
		g_client = accept(g_listen, NULL, NULL);
		if (g_client < 0)
			return ERR_BUSY;
		if (set_nonblock(g_client) < 0) {
			netinput_drop_client();
			return ERR_BUSY;
		}
		g_have = 0;
		return ERR_BUSY;
	}

	/* 攒够一整条记录为止; 半条留在 g_rec 里等下一轮。 */
	while (g_have < sizeof(g_rec)) {
		got = read(g_client, (char *)&g_rec + g_have,
			   sizeof(g_rec) - g_have);
		if (got > 0) {
			g_have += (size_t)got;
			continue;
		}
		if (got < 0 && errno == EINTR)
			continue;
		if (got < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
			return ERR_BUSY;
		/* EAGAIN = 这批数据读完了, 半条记录等下一轮接着攒;
		 * EOF/复位/错误 = 对端没了。 */
		netinput_drop_client();
		/* 客户端没了只影响这一条连接, 服务继续等下一个客户端 */
		return ERR_BUSY;
	}

	g_have = 0;
	if (!record_valid(&g_rec)) {
		netinput_drop_client();
		return ERR_BUSY;
	}
	out->sec = g_rec.sec;
	out->usec = g_rec.usec;
	out->type = g_rec.type;
	out->code = g_rec.code;
	out->value = g_rec.value;
	return ERR_OK;
}
```

三态读法是本文件的核心（TechReports 06 的 4.2 节是它的反例现场）：
`EAGAIN` 表示这批可读字节耗尽，连接与半条缓冲原样保留，等下一轮 poll；
EOF 与错误才断开。四种返回全部映射到 `ERR_BUSY`/`ERR_OK`——客户端断开
对服务而言不是错误，manager 的 `ERR_NOTFOUND`（收场）语义永远不会被
网络事件触发。manager 调 `read_raw` 前刚 poll 过，accept 走非阻塞路径
不会卡：监听 fd 可读时 accept 几乎必然成功，失败（对端在握手完成前
撤了）按"没有数据"处理。

```c
// input/netinput.c  [210-221] 注册
static struct input_provider g_netinput = {
	.name = "netinput",
	.open = netinput_open,
	.close = netinput_close,
	.get_fds = netinput_get_fds,
	.read_raw = netinput_read_raw,
};

void netinput_register(void)
{
	input_register(&g_netinput);
}
```

## evdev.c 与 replay.c 的契约适配

两文件主体（探测打分、能力位图、`sscanf` 探测写法）见第 05 章精读，
本章只改了一处契约：

```c
// input/evdev.c  [138-144]
static int evdev_get_fds(int *fds, int max)
{
	if (max < 1)
		return ERR_PARAM;
	fds[0] = g_fd;
	return 1;
}

// input/replay.c  [40-46]
static int replay_get_fds(int *fds, int max)
{
	if (max < 1)
		return ERR_PARAM;
	fds[0] = g_file == NULL ? -1 : fileno(g_file);
	return 1;
}
```

单 fd 后端把原 `get_fd` 的返回值填进数组第一个槽。replay 的 -1 分支
实际到不了（`open` 失败时 manager 不会选择它），留着是防御：`fileno`
对 NULL 的 `FILE *` 是未定义行为。

## 执行顺序

成功路径（replay 后端，五帧回放）：

| 步 | 发生了什么 | 此刻资源 |
|---|---|---|
| init | 三 provider 注册，选中 replay，open 文件，cond 绑单调时钟 | 文件 fd 已开 |
| init 末 | 线程起，开始 poll + 读文件 + 推队列 | 队列开始积累 |
| get_event ×5 | 每次锁内取一条，期限未到就 timedwait | 计数 delivered 递增 |
| 线程 EOF | read_raw 返回 NOTFOUND → g_closed 置位 → 广播 | 队列可能还有存货 |
| get_event 第 6 次 | 排空后见 g_closed → ERR_NOTFOUND | 消费者收场 |
| exit | 置 g_quit → broadcast → join → close 文件 → 清账 | 全部归还 |

失败路径（畸形回放）：

| 步 | 发生了什么 | 与成功路径的分叉 |
|---|---|---|
| init | 同上 | 无 |
| 线程 | 读到畸形行，read_raw 返回 ERR_IO | g_error = ERR_IO，线程收场 |
| get_event | 队列空，先查 g_error | 返回 ERR_IO 而非 NOTFOUND |
| 消费者 | input_test 以退出码 2 结束 | 判据 [14] 由此成立 |

netinput 失败路径再添一支：客户端发坏记录 → `read_raw` 断开连接返回
ERR_BUSY → manager 继续 poll（此时只有 listen fd）→ 下一个客户端照常
accept。服务不因任何单个客户端的任何行为收场。

## 容易读错的地方

1. **`ERR_BUSY` 在 netinput 里不是"忙"**。在 replay 里它是"这批数据读完了
   请再 poll"；在 netinput 里它还涵盖"accept 到了新客户端""半条记录等着"
   "客户端断开了"。manager 对 `ERR_BUSY` 只做一件事——继续循环——所以
   这些含义不会串。
2. **`g_dropping` 清的是两样东西**。半帧暂存（reset_frame）和按钮快照
   （g_buttons = 0）都在 DROPPED 时清，但后者清掉后不向设备重查：物理上
   仍按着的键，设备下一次翻转前软件无从得知。判据只覆盖"失真区间不冒充
   事件"。
3. **账目恒等式的有效期**。`received = delivered + dropped` 跨 init/exit
   失效（exit 清零），跨 provider 切换也失效——manager 一次只服务一个
   provider，运行中不切换。
4. **`netinput_send`（unittest/）与本文件的 record 结构体是两份声明**。
   这是协议两端，谁也不 include 谁；对齐靠两处 `_Static_assert` 加
   TechReports 06 的格式表。改格式要三处同改。

## 消费者清单

| 消费者 | 用到的接口 |
|---|---|
| page/page_manager.h | `struct input_event_data`（事件分发签名） |
| business/business_manager.c | `input_get_event`（主循环取事件）、`INPUT_KIND_KEY` |
| unittest/input_test.c | `input_init/exit/get_event/get_source_info/get_stats` |
| unittest/netinput_send.c | 线上格式（20 字节记录，协议对端） |
| TechReports 06/07 | 格式表、三本账恒等式 |
