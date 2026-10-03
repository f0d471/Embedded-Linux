# input 层逐行精读

对应代码：`project/input/input_manager.h`（49 行）、`input_internal.h`（29 行）、
`input_manager.c`（294 行）、`evdev.c`（178 行）、`replay.c`（81 行）。

## 1. 文件定位

对上提供"等一个应用事件"的同步接口，对下挂 evdev（真实设备）与 replay（文本
回放）两个来源。内核的 `type/code/value` 记录流到应用事件之间的归并、坐标
换算、超时全部在 manager。上游消费者目前是 `unittest/input_test.c` 与
`main.c` 层表，未来的 ui/page 鼠标切页走同一组公开函数。
已知缺陷（同帧 pointer+key 丢键）登记在
[Bugs/01](../../Bugs/01-同帧指针与普通键丢事件.md)。

前置知识：[从零开始读写 project 代码](../00-从零开始读写项目代码.md)第 5/6 节
（函数指针链表、位运算）；第 05 章笔记（输入系统）；
开发经过见 [TechReports/project/05](../../TechReports/project/05-input层-把evdev原始帧变成应用事件.md)。

```
ui / page(未接入)   input_test   main.c 层表
        │ input_get_event(out, timeout_ms)
        ▼
┌──────────────── input_manager.c ────────────────┐
│ poll(deadline) → read_raw → parse_raw 状态机     │
│ 相对: clamp(x+dx)   绝对: scale_abs(int64)       │
│ 按钮: 位图跨帧保持   SYN_DROPPED: 丢弃到下个 REPORT │
└───────┬─────────────────────────────────────────┘
        │ get_fd / read_raw
 ┌──────┴───────┐
 │ evdev.c       │ replay.c
 │ event0..31    │ INPUT_REPLAY 文本
 │ 能力打分选节点 │ 每行 5 字段
 └──────────────┘
```

## 2. input_manager.h

### 第 1—15 行：事件种类与按钮位

```c
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
```

应用事件只有两种：指针与普通键。按钮用位图不用互斥枚举，`1u` 后缀保证
移位在无符号域进行——左中右三键可同时按住，位图是"哪些还按着"，
一个 `unsigned int` 装下。

### 第 17—40 行：应用事件与来源信息

```c
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
```

`input_event_data` 的字段按 kind 各取所需：POINTER 用 x/y/dx/dy/buttons，
KEY 用 code/value，时间戳两种都有。`sec/usec` 用 `int64_t` 固定宽度，
不依赖 `time_t` 在两个平台上的宽度差。`input_source_info` 是设备能力的
对外快照：manager 拿量程做绝对坐标换算，板上诊断读 name/path 定位设备。

### 第 42—49 行：公开函数

```c
int  input_init(void);
void input_exit(void);

/* timeout_ms: -1 永久等待，0 只检查现有数据，正数为最长等待毫秒数。 */
int input_get_event(struct input_event_data *out, int timeout_ms);
const struct input_source_info *input_get_source_info(void);

#endif /* __INPUT_MANAGER_H */
```

超时语义三档写在声明旁：`-1` 永等、`0` 不额外等待（已有半帧仍会消费到
完整帧）、正数是最长等待。返回值三态要分开读：`ERR_OK` 有事件、`ERR_BUSY`
到时无事件、`ERR_NOTFOUND` 在回放里是文件读完——后两者都不是错误，
`input_test` 对两者都正常退出。

## 3. input_internal.h

### 第 1—29 行：原始记录与 provider

```c
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
```

原始记录固定五字段、固定宽度：内核 `struct input_event` 在 32 位板与 64 位
开发机上布局不同（`time_t` 宽度），两个 provider 的职责就是把各自来源翻译成
这一份稳定结构。provider 四个动作里 `get_fd` 只为 manager 的 poll 服务；
回放用 `fileno()` 把 `FILE *` 的描述符交出来，所有权仍在 `FILE *`。

## 4. input_manager.c

### 第 1—33 行：全局状态分类

```c
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
```

两组全局变量的分界就是 05 章"持续状态 vs 本帧暂存"：`g_width/height/x/y/buttons`
跨帧保存（提交后保持，只有 init/exit 清），第二组每次 `reset_frame()` 清。
`g_key_code` 初值 -1 表示"本帧没有普通键"——0 是合法键码，不能用 0 当哨兵。
`g_dropping` 单列：它既非跨帧也非本帧，是丢帧恢复的标记。

### 第 35—71 行：注册、查找、帧复位、钳位

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
```

`reset_frame` 只清本帧暂存，`g_buttons` 不在其中：按住鼠标移动时，没有按钮
记录的帧必须维持按下状态，清了它上层会看到按钮逐帧弹起。`clamp_value` 的
上界是 `limit - 1`：宽 64 的合法下标到 63，64 已经越界。判据 [13r1] 注错把
负值检查改成 `< -9999` 后，`dx=-1000` 的帧输出 `x=-958`，见红。

### 第 73—100 行：绝对缩放与按钮映射

```c
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

`scale_abs` 先钳进量程再缩放：非法上报的大坐标不会变成屏幕外值。
中间乘积升到 `int64_t`——量程 4095 与屏宽 1280 的乘积在 32 位 `int` 里
不溢出，但触摸屏量程可以更大，这里一次到位。`max <= min` 的病态量程退化成
钳位，除零不可能发生。整数除法向零截断：2048×63/4095 = 31（31.5 截成 31）。

`BTN_TOUCH` 并入左键位是触摸屏的简化契约：触摸即"按住"，上层目前只用
"有没有按下"。返回 0 表示"不是按钮"，调用方把这类 `EV_KEY` 归入普通键。

### 第 102—185 行：parse_raw 状态机

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
```

状态机三个区：DROPPED 入口（清半帧、清按钮快照、置标记）、丢弃区
（一切记录忽略，REPORT 只解除标记）、正常收集。丢弃区间是
`[SYN_DROPPED, 下一个 SYN_REPORT)` 两端都算——判据 [13r3] 注错跳过丢弃区，
fixture 在 DROPPED 后故意放的 Y 位移与按钮翻转被拼成第 6 个事件，见红。

提交分支的优先级：本帧有 pointer 变化就交 pointer，否则有普通键交 key，
否则无事发生。已知缺陷在这里：同一帧两类动作并存时，`reset_frame()` 会把
暂存的 `g_key_code` 清掉（见 Bugs/01）。绝对与相对按轴独立判断
（`g_have_abs_x/y` 分开）：混合设备只报一轴绝对值时，另一轴仍走相对。

按钮更新用 `|=` / `&= ~mask`：按下置位、释放清位，互不覆盖。
`value` 为 2（长按重复）时按"仍按着"处理，进 `if (raw->value)` 置位分支。

### 第 187—251 行：时钟、init、exit

```c
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
```

`CLOCK_MONOTONIC` 只测经过时间，墙上时钟被手动调整不影响 deadline；
取不到时返回 0 是降级（正数超时会变成"立即到时"），`clock_gettime` 在
Linux 用户态实际不会失败。后端选择的缺省规则：显式 `INPUT_BACKEND` 优先，
否则设了 `INPUT_REPLAY` 就选 replay——判据脚本全走这条路。

几何来自 display 层且兜底成 1x1：`clamp_value(v, 1)` 恒 0、`scale_abs` 的
`limit-1=0` 分母不出现，除零与负上界都不会发生。指针初值是画布中心。
层序前提 display 在 input 之前由 `main.c` 的层表保证，这里的兜底防御
单测直接 `input_init` 的场景。

### 第 253—294 行：input_get_event

```c
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
```

总 deadline 先算一次，每轮只等剩余量：`poll` 被 `EINTR` 打断后 `continue`
重算，1000 ms 的等待被信号打断十次总长仍是 1000 ms。`remain > INT_MAX`
截断——`poll` 的超时参数是 `int`，64 位剩余值直接传会实现定义。
`timeout_ms=0` 时 deadline 就是现在，每轮 `wait_ms=0`：不睡眠但可以消费
已在缓冲里的数据直到完整帧或读空。

循环体的三种"继续"：poll 报就绪但 `read_raw` 得 `ERR_BUSY`（非阻塞 fd
暂时无数据，通常是被消费完的边沿），回去再 poll；`parse_raw` 返回 0
（本条记录不构成完整帧），继续读；`EINTR` 重算等待。三种"返回"：
`ERR_OK` 交付事件、`ERR_BUSY` 超时、`ERR_IO`/其他透传 provider 错误。

## 5. evdev.c

### 第 1—21 行：位图工具

```c
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "common.h"
#include "input/input_internal.h"

#define BITS_PER_LONG (sizeof(unsigned long) * 8)
#define NBITS(max) (((max) + BITS_PER_LONG) / BITS_PER_LONG)

static int g_fd = -1;

static int bit_is_set(const unsigned long *bits, int bit)
{
	return !!(bits[bit / BITS_PER_LONG] & (1ul << (bit % BITS_PER_LONG)));
}
```

内核能力位图按 `unsigned long` 数组返回，`NBITS(KEY_MAX)` 算要多大的缓冲。
`!!` 把非零值归一成 1，返回值进布尔语境。`1ul` 保证移位在 64 位宽度内
（`KEY_MAX` 超过 32）。

### 第 23—38 行：读绝对量程

```c
static int read_abs_range(int fd, int primary, int fallback, int *min, int *max)
{
	struct input_absinfo abs;

	if (ioctl(fd, EVIOCGABS(primary), &abs) == 0) {
		*min = abs.minimum;
		*max = abs.maximum;
		return 1;
	}
	if (fallback >= 0 && ioctl(fd, EVIOCGABS(fallback), &abs) == 0) {
		*min = abs.minimum;
		*max = abs.maximum;
		return 1;
	}
	return 0;
}
```

单点触摸量程取不到时退到多点触控轴（`ABS_X` → `ABS_MT_POSITION_X`），
两轴独立调用、独立失败，失败时量程保持 `g_info` 里的 0——配合
`scale_abs` 的 `max<=min` 分支退化为钳位，不会除零。

### 第 40—87 行：能力打分

```c
static int probe_fd(int fd, const char *path, struct input_source_info *out)
{
	unsigned long ev[NBITS(EV_MAX)];
	unsigned long rel[NBITS(REL_MAX)];
	unsigned long abs[NBITS(ABS_MAX)];
	unsigned long key[NBITS(KEY_MAX)];
	char name[sizeof(out->name)] = "unknown";
	int code, key_count = 0, score = 0;

	memset(ev, 0, sizeof(ev));
	memset(rel, 0, sizeof(rel));
	memset(abs, 0, sizeof(abs));
	memset(key, 0, sizeof(key));
	if (ioctl(fd, EVIOCGBIT(0, sizeof(ev)), ev) < 0)
		return -1;
	(void)ioctl(fd, EVIOCGNAME(sizeof(name)), name);

	memset(out, 0, sizeof(*out));
	snprintf(out->name, sizeof(out->name), "%s", name);
	snprintf(out->path, sizeof(out->path), "%s", path);
	if (bit_is_set(ev, EV_REL) &&
	    ioctl(fd, EVIOCGBIT(EV_REL, sizeof(rel)), rel) >= 0 &&
	    bit_is_set(rel, REL_X) && bit_is_set(rel, REL_Y)) {
		out->has_relative = 1;
		score += 400;
	}
	if (bit_is_set(ev, EV_ABS) &&
	    ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs)), abs) >= 0 &&
	    ((bit_is_set(abs, ABS_X) && bit_is_set(abs, ABS_Y)) ||
	     (bit_is_set(abs, ABS_MT_POSITION_X) && bit_is_set(abs, ABS_MT_POSITION_Y)))) {
		out->has_absolute = 1;
		read_abs_range(fd, ABS_X, ABS_MT_POSITION_X,
			       &out->abs_x_min, &out->abs_x_max);
		read_abs_range(fd, ABS_Y, ABS_MT_POSITION_Y,
			       &out->abs_y_min, &out->abs_y_max);
		score += 300;
	}
	if (bit_is_set(ev, EV_KEY) &&
	    ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(key)), key) >= 0) {
		for (code = 0; code <= KEY_MAX; code++)
			if (bit_is_set(key, code))
				key_count++;
		out->has_keys = key_count > 0;
		if (key_count > 0)
			score += strstr(name, "power") != NULL ? 10 : 100;
	}
	return score;
}
```

`EVIOCGBIT(0, ...)` 问的是事件类型位图，类型在位再问该类型的位图——两层
查询缺一不可。打分表把"能不能当鼠标"变成序：REL 双轴 400 压过 ABS 300
压过普通键 100，名含 power 的按键设备只有 10 分（板上 event0 是 powerkey、
event1 是 gpio-keys，实测定的分差）。名字查询失败用 "unknown" 兜底，
`strstr` 在其上照常工作。返回 -1（类型位图都问不出）与返回分数是两个
含义，调用方用 `< 0` 区分。

### 第 89—141 行：探测与打开

```c
static int evdev_open(struct input_source_info *out)
{
	struct input_source_info candidate, best;
	const char *forced = getenv("INPUT_DEV");
	char path[64], best_path[64] = "";
	int fd, i, score, best_score = -1;

	if (forced != NULL) {
		g_fd = open(forced, O_RDONLY | O_NONBLOCK);
		if (g_fd < 0)
			return ERR_IO;
		if (probe_fd(g_fd, forced, out) < 0) {
			close(g_fd);
			g_fd = -1;
			return ERR_NOTSUP;
		}
		return ERR_OK;
	}

	for (i = 0; i < 32; i++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		score = probe_fd(fd, path, &candidate);
		close(fd);
		if (score > best_score) {
			best_score = score;
			best = candidate;
			snprintf(best_path, sizeof(best_path), "%s", path);
		}
	}
	if (best_score < 0)
		return ERR_NOTFOUND;
	g_fd = open(best_path, O_RDONLY | O_NONBLOCK);
	if (g_fd < 0)
		return ERR_IO;
	*out = best;
	return ERR_OK;
}

static void evdev_close(void)
{
	if (g_fd >= 0) {
		close(g_fd);
		g_fd = -1;
	}
}

static int evdev_get_fd(void)
{
	return g_fd;
}
```

两段 fd 所有权：探测期间每个候选打开-查询-关闭（一次性），选中最高分后
重新打开作为长期 `g_fd`。探测失败（`probe_fd < 0`，如 `/dev/null` 不是
evdev）时临时 fd 当场归还，判据 [14] 的"普通文件不会冒充 evdev"退出码 1
就是这条路径。`best_score < 0`（一个节点都没打开过）与"打开了但都是 0 分"
（选中第一个 0 分节点）可区分：前者是系统没有输入设备。

### 第 143—178 行：read_raw 与注册

```c
static int evdev_read_raw(struct input_raw_event *out)
{
	struct input_event event;
	ssize_t got;

	if (out == NULL || g_fd < 0)
		return ERR_PARAM;
	do {
		got = read(g_fd, &event, sizeof(event));
	} while (got < 0 && errno == EINTR);
	if (got < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
		return ERR_BUSY;
	if (got == 0)
		return ERR_NOTFOUND;
	if (got != (ssize_t)sizeof(event))
		return ERR_IO;
	out->sec = event.input_event_sec;
	out->usec = event.input_event_usec;
	out->type = event.type;
	out->code = event.code;
	out->value = event.value;
	return ERR_OK;
}

static struct input_provider g_evdev = {
	.name = "evdev",
	.open = evdev_open,
	.close = evdev_close,
	.get_fd = evdev_get_fd,
	.read_raw = evdev_read_raw,
};

void evdev_register(void)
{
	input_register(&g_evdev);
}
```

`read` 的四个出口各自映射：`EINTR` 重试（`do-while`，信号打断不算失败）、
`EAGAIN` 返回 `ERR_BUSY` 交 manager 继续 poll、0 字节是设备 EOF、短读
（非整条记录）是 `ERR_IO`——evdev 不保证半条记录重读，硬凑会错位。
时间字段走 `input_event_sec/usec` 兼容宏：旧内核头是 `time` 联合体成员，
新内核是独立字段，宏在两者上都能编。

## 6. replay.c

### 第 1—43 行：open、close、get_fd

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "input/input_internal.h"

static FILE *g_file;

static int replay_open(struct input_source_info *out)
{
	const char *path = getenv("INPUT_REPLAY");

	if (path == NULL || path[0] == '\0')
		return ERR_PARAM;
	g_file = fopen(path, "r");
	if (g_file == NULL)
		return ERR_IO;
	memset(out, 0, sizeof(*out));
	snprintf(out->name, sizeof(out->name), "text replay");
	snprintf(out->path, sizeof(out->path), "%s", path);
	out->has_relative = 1;
	out->has_absolute = 1;
	out->has_keys = 1;
	out->abs_x_min = 0;
	out->abs_x_max = 4095;
	out->abs_y_min = 0;
	out->abs_y_max = 4095;
	return ERR_OK;
}

static void replay_close(void)
{
	if (g_file != NULL) {
		fclose(g_file);
		g_file = NULL;
	}
}

static int replay_get_fd(void)
{
	return g_file == NULL ? -1 : fileno(g_file);
}
```

能力与量程是声明的，不是探测的：这份回放同时要考相对、绝对、按键三条路径，
量程 0..4095 与 `input_replay.txt` 第 5 帧的 `4095` 配套（缩放到 64x32 假屏
得 63）。`get_fd` 把 `FILE *` 底下的描述符交给 poll；读操作全走 `FILE *`
缓冲，所有权与关闭只在 `fclose` 一处——对 `fileno` 的返回值调 close
是双重释放。

### 第 45—82 行：read_raw 与注册

```c
static int replay_read_raw(struct input_raw_event *out)
{
	char line[256], extra;
	long long sec, usec;
	unsigned int type, code;
	int value;

	if (g_file == NULL || out == NULL)
		return ERR_PARAM;
	while (fgets(line, sizeof(line), g_file) != NULL) {
		if (line[0] == '#' || line[0] == '\n')
			continue;
		if (sscanf(line, "%lld %lld %u %u %d %c",
			   &sec, &usec, &type, &code, &value, &extra) != 5)
			return ERR_IO;
		out->sec = sec;
		out->usec = usec;
		out->type = (uint16_t)type;
		out->code = (uint16_t)code;
		out->value = value;
		return ERR_OK;
	}
	return ferror(g_file) ? ERR_IO : ERR_NOTFOUND;
}

static struct input_provider g_replay = {
	.name = "replay",
	.open = replay_open,
	.close = replay_close,
	.get_fd = replay_get_fd,
	.read_raw = replay_read_raw,
};

void replay_register(void)
{
	input_register(&g_replay);
}
```

格式串末尾的 `%c` 是多余字段探测器：合法行恰好 5 项，第 6 个转换找不到输入，
返回 5；任何行尾垃圾（`input_replay_bad.txt` 的 `unexpected_field`）把返回值
顶成 6，判 `ERR_IO`。`%u` 收 type/code 后转 `uint16_t`——超出 16 位的行
静默截断，fixture 不构造这种行；严格校验写在 manager 之上没有收益。
EOF 与读错误用 `ferror` 区分：正常读完返回 `ERR_NOTFOUND`（应用层当作
"没有更多事件"），磁盘错误返回 `ERR_IO`。判据 [14] 对
`input_replay_bad.txt` 断言退出码 2（`input_test` 对 `ERR_IO` 的返回）。

## 7. 执行顺序

```
成功(回放): input_init → 注册两 provider → 选 replay → fopen
            → get_event 循环: poll(fd 就绪) → read_raw(逐行)
            → parse_raw(0: 继续读; 1: 交付) → EOF: ERR_NOTFOUND
            → input_exit → fclose
成功(真实): init → 扫描 event0..31 打分 → 重开选中节点
            → poll 等待 → read(EAGAIN: ERR_BUSY 继续) → 同上
失败1: 后端名不存在            → ERR_NOTFOUND
失败2: 全部节点打不开          → ERR_NOTFOUND(evdev_open best_score<0)
失败3: 真实设备无事件到时      → ERR_BUSY(干净超时, 板上 --once 5s 实测)
```

## 8. 容易读错的地方

- 跨帧状态（`g_x/g_y/g_buttons`）与本帧暂存（`g_frame_*/g_key_*`）清零时机
  不同；`reset_frame` 清后者不清前者。
- 第 2 帧没有按钮记录但 `buttons=1`：位图是持续状态，没有记录就保持。
- 丢弃区间是 `[SYN_DROPPED, 下一个 SYN_REPORT)`，两端都算；只清半帧漏掉后段
  会多出事件（判据 [13r3]）。
- `clamp_value` 的上界是 `limit-1`；`scale_abs` 先钳后缩，除数 `max-min`
  在 `max<=min` 时走不到。
- `timeout_ms=0` 不是"最多读一条"，是"不睡眠"；已有半帧仍会消费到完整帧。
- `fileno()` 的返回值不 close；`FILE *` 与 fd 是同一文件的两层包装。
- `ERR_BUSY`（超时）与 `ERR_NOTFOUND`（回放 EOF）都不是失败，
  `input_test` 对两者正常退出。

## 9. 消费者清单

- `main.c` 层表：`input_init/input_exit`。
- `unittest/input_test.c`：`input_get_event`（三种用法）、`input_get_source_info`。
- display 层：init 时读几何（`disp_get_buf`）。
- 判据：`check_font_input.sh` [13][14] 共 8 条；板上 2026-09-23 探测记录见
  TechReport 05 第五节。
- 未修缺陷：同帧 pointer+key 丢键（Bugs/01），修复后并入 TechReport 05。
