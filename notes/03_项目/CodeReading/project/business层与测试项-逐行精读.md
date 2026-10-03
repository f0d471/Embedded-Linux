# business 层与测试项逐行精读

代码路径与总行数（`grep -n ''` 于 2026-10-04 核对）：

```
business/business_manager.c          137 行   init/主循环/命令执行/布局公式
business/business_main_page.c        118 行   主页: 测试项网格 + 设置按钮
business/business_settings_page.c     99 行   设置页: 配置摘要 + 返回按钮
business/business_internal.h          33 行   层内约定(布局常量、页面注册)
business/business_manager.h           19 行   对外接口
items/ap3216_read.c                  139 行   08 章 I2C 测试项
items/serial_loop.c                  150 行   09 章串口测试项
```

前置知识：config 层（条目数据）、page 层（ops 三件事）、ui 层（按钮）、
`notes/01_应用编程/08_I2C` 与 `09_串口`（两个 items 的 API 来源）。
文件定位：层表第七层，是"整个程序真正干活的地方"。具体页面住在
business 而不在 page——page 管切换协议，页面是业务数据，这个分法照搬
参考项目的目录结构。消费者：main.c（`business_run`）、check_gui.sh
[21]（端到端回放的输出行）、配置文件（`command` 字段点名 items 程序）。

## business_manager.h / business_internal.h

```c
// business/business_manager.h  [11-17]
int  business_init(void);
void business_exit(void);

/* main_loop 调它; 返回时整个程序就准备退出了 */
int  business_run(void);
```

```c
// business/business_internal.h  [13-31] 正文
#define UI_MARGIN   8
#define UI_BTN_H    40
#define UI_GAP      8
#define UI_COLS     2

/* item i 在网格里的外框 */
void business_item_rect(int index, int item_count, struct disp_region *out);

/* "设置"/"返回" 按钮共用的位置: 最后一行最后一格 */
void business_prefs_rect(int item_count, struct disp_region *out);

/* 两个具体页面, 在各自的 .c 里调 page_register */
void business_main_page_register(void);
void business_settings_page_register(void);

/* 点了测试项按钮: fork+exec 跑配置里给的命令, 退出码进日志 */
void business_run_command(const char *name, const char *command);
```

布局常量是层内契约也是判据契约：check_gui.sh [21] 的点击坐标按这套
公式手算（320x240 单测试项 → 测试项 (8,8,148,40)、设置 (164,56,148,40)）。
改任何常量必须同一次改动里重算判据坐标，`business_internal.h` 的
头注释写明了这条耦合。

## business_manager.c

### [18-44] 两个布局公式

```c
void business_item_rect(int index, int item_count, struct disp_region *out)
{
	const struct disp_buf *fb = disp_get_buf();
	int bw, col, row;

	bw = (fb->xres - UI_MARGIN * (UI_COLS + 1)) / UI_COLS;
	col = index % UI_COLS;
	row = index / UI_COLS;
	out->x = UI_MARGIN + col * (bw + UI_GAP);
	out->y = UI_MARGIN + row * (UI_BTN_H + UI_GAP);
	out->w = bw;
	out->h = UI_BTN_H;
	(void)item_count;
}

void business_prefs_rect(int item_count, struct disp_region *out)
{
	const struct disp_buf *fb = disp_get_buf();
	int bw, rows;

	bw = (fb->xres - UI_MARGIN * (UI_COLS + 1)) / UI_COLS;
	rows = (item_count + UI_COLS - 1) / UI_COLS;
	out->x = UI_MARGIN + (UI_COLS - 1) * (bw + UI_GAP);
	out->y = UI_MARGIN + rows * (UI_BTN_H + UI_GAP);
	out->w = bw;
	out->h = UI_BTN_H;
}
```

按钮宽度从屏幕宽度反推而不是写死——1024x600 的板子和 320x240 的
假屏用同一套公式，端到端判据与板上演示才有同一份代码。"设置"按钮
的行号 = 测试项占用的行数（向上取整），永远在最后一行最后一格，
两个页面共用同一位置，点击坐标因此可以复用。

### [46-67] 命令执行

```c
void business_run_command(const char *name, const char *command)
{
	pid_t pid;
	int status = -1;

	/* name 只出现在日志里; LOG_LEVEL=0 时日志整体消失, 得压住告警 */
	(void)name;
	pid = fork();
	if (pid < 0) {
		LOG_ERR("item %s fork failed", name);
		return;
	}
	if (pid == 0) {
		execl("/bin/sh", "sh", "-c", command, (char *)NULL);
		_exit(127);            /* 只有 execl 失败才走到这 */
	}
	waitpid(pid, &status, 0);
	if (WIFEXITED(status))
		LOG_INFO("item %s rc=%d", name, WEXITSTATUS(status));
	else
		LOG_INFO("item %s killed by signal %d", name, WTERMSIG(status));
}
```

同步执行：主循环在 `waitpid` 上阻塞到命令退出。测试项是短命令
（meminfo、读一次传感器），长命令会卡住整个界面——这是当前场景
的接受项，异步执行与结果页属于后续。`(char *)NULL` 是 execl 变参
列表的终止哨兵，裸 `NULL` 在 64 位上 sizeof 不匹配指针是未定义行为。
子进程退出码 127 保留给"shell 都没起来"，与 shell 自身的 127
（命令没找到）撞号，日志层面无法区分——已知简化。

### [69-108] init 与 exit

```c
int business_init(void)
{
	const struct config *cfg;
	const struct disp_buf *fb;

	if (g_inited)
		return ERR_OK;

	cfg = config_get();
	if (cfg == NULL)
		return ERR_NOTFOUND;

	if (cfg->font_file[0] != '\0') {
		/* 真字体选不上就退回内置点阵, 界面照常出, 字丑一点 */
		if (font_select("freetype", cfg->font_file, 0) != ERR_OK ||
		    font_set_pixel_size(cfg->font_size) != ERR_OK)
			LOG_INFO("font %s unavailable, builtin fallback",
				 cfg->font_file);
	}

	fb = disp_get_buf();
	(void)fb;    /* 几何只进日志, LOG_LEVEL=0 时压住 unused 告警 */
	business_main_page_register();
	business_settings_page_register();
	page_switch("main");
	LOG_INFO("business %dx%d %d item(s)",
		 fb != NULL ? fb->xres : 0, fb != NULL ? fb->yres : 0,
		 cfg->item_count);
	LOG_INFO("business init OK");
	g_inited = 1;
	return ERR_OK;
}

void business_exit(void)
{
	if (!g_inited)
		return;
	g_inited = 0;
	LOG_INFO("business exit OK");
}
```

字体降级链写在 init：配置给了字体文件但选不上（文件缺失、FreeType
后端没编），界面退回内置点阵继续跑——配置项失效的代价是难看，
不是起不来。页面注册在切换之前，`page_switch("main")` 是起手式。

### [110-137] 主循环

```c
int business_run(void)
{
	const struct config *cfg;
	struct input_event_data ev;
	int timeout;
	int events = 0;
	int ret;

	if (!g_inited) {
		LOG_INFO("business not inited, no loop");
		return ERR_NOTSUP;
	}
	cfg = config_get();
	timeout = cfg->page_timeout_ms > 0 ? cfg->page_timeout_ms : -1;

	for (;;) {
		ret = input_get_event(&ev, timeout);
		if (ret != ERR_OK)
			break;            /* 超时/输入源收场都走出循环 */
		events++;
		if (ev.kind == INPUT_KIND_KEY && ev.code == 16 /* KEY_Q */ &&
		    ev.value == 1)
			break;            /* q 键 = 退出, 板上没有别的出口 */
		page_dispatch(&ev);
	}
	LOG_INFO("business loop end events=%d", events);
	return ERR_OK;
}
```

循环三条腿：取事件（配置的超时决定空等多久，0 换成 -1 无限期）、
q 键退出（KEY_Q = 16，按下沿 value==1 才算，松开不算）、其余全部
分发给当前页。`ERR_BUSY`（超时）与 `ERR_NOTFOUND`（回放 EOF、
输入源收场）都走出循环——对测试与判据这意味着回放放完程序自然结束。
判据 [21] 的 `events=9` 与 [1] 的退出码 0 都锚在这段循环上。

## business_main_page.c

### [16-40] 状态与回调

```c
static struct ui_button *g_item_btns[CONFIG_ITEMS_MAX];
static struct ui_button *g_prefs_btn;

static void on_item_click(struct ui_button *btn, void *ctx);
static void on_prefs_click(struct ui_button *btn, void *ctx);
static void main_destroy(void);

static void on_item_click(struct ui_button *btn, void *ctx)
{
	const struct config *cfg = config_get();
	int index = (int)(intptr_t)ctx;

	(void)btn;
	if (cfg == NULL || index < 0 || index >= cfg->item_count)
		return;
	business_run_command(cfg->items[index].name,
			     cfg->items[index].command);
}

static void on_prefs_click(struct ui_button *btn, void *ctx)
{
	(void)btn;
	(void)ctx;
	page_switch("settings");
}
```

按钮的 `ctx` 携带测试项下标（`create` 时以 `(void *)(intptr_t)i` 存入），
回调里先验下标仍有效（配置在两次切换之间不会变，防御留给未来）。
判据 [21r] 注错的正是 `on_prefs_click` 里的 `page_switch`——切页行为
由页面自己的回调驱动，按钮层不知道"settings"这个名字。

### [42-77] create

```c
static int main_create(void)
{
	const struct config *cfg = config_get();
	const struct disp_buf *fb = disp_get_buf();
	struct disp_region r;
	int i;

	/* 切页先清屏: 上一页的像素不归本页管, 但也不能留在屏上 */
	disp_fill_rect(&(struct disp_region){ 0, 0, fb->xres, fb->yres },
		       0x000000u);

	if (cfg != NULL) {
		for (i = 0; i < cfg->item_count; i++) {
			business_item_rect(i, cfg->item_count, &r);
			g_item_btns[i] = ui_button_create(cfg->items[i].name,
							  r.x, r.y, r.w, r.h,
							  on_item_click,
							  (void *)(intptr_t)i);
			if (g_item_btns[i] == NULL)
				goto fail;
		}
	}
	business_prefs_rect(cfg != NULL ? cfg->item_count : 0, &r);
	g_prefs_btn = ui_button_create("settings", r.x, r.y, r.w, r.h,
				       on_prefs_click, NULL);
	if (g_prefs_btn == NULL)
		goto fail;
	ui_button_draw_all();
	LOG_INFO("page main buttons=%d", ui_button_count());
	return ERR_OK;

fail:
	/* 一颗建不出来就把已建的全拆掉, 让 create 保持"要么全成要么没动过" */
	main_destroy();
	return ERR_NOMEM;
}
```

清屏是 create 的第一步（TechReports 08 的 4.2 节记录了没有它的
残影现场）。fail 标签把"建到一半失败"收敛成"等于没建过"——
create 的原子性在页面这一侧保证，page 层的切换协议依赖它。

### [79-118] destroy、事件、注册

```c
static void main_destroy(void)
{
	const struct config *cfg = config_get();
	int i, n = cfg != NULL ? cfg->item_count : 0;

	for (i = 0; i < CONFIG_ITEMS_MAX; i++) {
		if (g_item_btns[i] != NULL) {
			ui_button_destroy(g_item_btns[i]);
			g_item_btns[i] = NULL;
		}
	}
	if (g_prefs_btn != NULL) {
		ui_button_destroy(g_prefs_btn);
		g_prefs_btn = NULL;
	}
	(void)n;
	LOG_INFO("page main destroyed");
}

static void main_on_event(const struct input_event_data *ev)
{
	if (ev->kind != INPUT_KIND_POINTER)
		return;
	if (ev->buttons & INPUT_BUTTON_LEFT)
		ui_button_press(ev->x, ev->y);
	else
		ui_button_release(ev->x, ev->y);
}

static struct page_ops g_main_page = {
	.name = "main",
	.create = main_create,
	.destroy = main_destroy,
	.on_event = main_on_event,
};

void business_main_page_register(void)
{
	page_register(&g_main_page);
}
```

事件到按钮的翻译在页面的 `on_event` 里：左键按着 = press，否则 =
release。按键事件直接忽略——主页没有键盘导航。destroy 按"槽位非空
才销毁"循环，与 create 的 fail 路径共用。

## business_settings_page.c

```c
// business/business_settings_page.c  [16-39] 状态、回调、摘要文本
static struct ui_button *g_back_btn;
static char g_info_line[CONFIG_PATH_MAX + 64];

static void on_back_click(struct ui_button *btn, void *ctx)
{
	(void)btn;
	(void)ctx;
	page_switch("main");
}

static void draw_info_text(void)
{
	const struct disp_buf *fb = disp_get_buf();
	struct font_text_metrics m;
	size_t bad;
	int baseline = UI_MARGIN * 2 + UI_BTN_H;

	if (font_measure_utf8(g_info_line, strlen(g_info_line), &m, &bad)
	    != ERR_OK)
		return;
	font_draw_utf8(g_info_line, strlen(g_info_line), UI_MARGIN, baseline,
		       0xffffffu, &m, &bad);
	disp_flush(&(struct disp_region){ 0, 0, fb->xres, fb->yres });
}
```

```c
// business/business_settings_page.c  [41-88] create/destroy/on_event(节选 create)
static int settings_create(void)
{
	const struct config *cfg = config_get();
	const struct disp_buf *fb = disp_get_buf();
	struct disp_region r;

	disp_fill_rect(&(struct disp_region){ 0, 0, fb->xres, fb->yres },
		       0x000000u);

	if (cfg != NULL)
		snprintf(g_info_line, sizeof(g_info_line),
			 "font=%s size=%d items=%d",
			 cfg->font_file[0] != '\0' ? cfg->font_file
						   : "(builtin)",
			 cfg->font_size, cfg->item_count);
	else
		snprintf(g_info_line, sizeof(g_info_line), "no config");

	business_prefs_rect(cfg != NULL ? cfg->item_count : 0, &r);
	g_back_btn = ui_button_create("back", r.x, r.y, r.w, r.h,
				      on_back_click, NULL);
	if (g_back_btn == NULL)
		return ERR_NOMEM;
	ui_button_draw_all();
	draw_info_text();
	LOG_INFO("page settings buttons=%d", ui_button_count());
	return ERR_OK;
}
```

摘要文本的缓冲取 `CONFIG_PATH_MAX + 64`：最长的 font_file 路径加上
格式串的固定字符装得下，gcc 的 `-Wformat-truncation` 在 256 字节
缓冲上拦过第一版（TechReports 08 没记这处，编译期拦截）。画序
清屏 → 建按钮 → draw_all → 摘要文本，文本最后画所以不会被子画面
覆盖。destroy/on_event 与主页同构，`settings_destroy` 只销毁
`g_back_btn` 一颗。

## items/ap3216_read.c

```c
// items/ap3216_read.c  [18-35] 寄存器与访问原语(节选)
#define AP3216_ADDR        0x1e
#define AP3216_REG_SYS_CFG 0x00
#define AP3216_REG_ALS_L   0x0a
#define AP3216_REG_ALS_H   0x0b
#define AP3216_REG_IR_L    0x0c
#define AP3216_REG_IR_H    0x0d
#define AP3216_REG_PS_L    0x0e
#define AP3216_REG_PS_H    0x0f

/* 数据手册给出的换算: 每个计数控 0.35 lux(环境光 16 位模式) */
#define ALS_LUX_PER_COUNT 0.35

static int g_fd = -1;

/* 一次"写寄存器地址 + 读 1 字节"。i2c-dev 的 write/read 就是这么用的:
 * write 把要访问的寄存器号发过去, 紧跟的 read 从那个寄存器搬数据。 */
static int read_reg(unsigned char reg, unsigned char *out)
{
	ssize_t got;

	if (write(g_fd, &reg, 1) != 1)
		return -1;
	do {
		got = read(g_fd, out, 1);
	} while (got < 0 && errno == EINTR);
	return got == 1 ? 0 : -1;
}
```

```c
// items/ap3216_read.c  [44-77] 自动探测与单次读(节选两段)
static int open_sensor(int forced_bus, int *real_bus)
{
	char path[32];
	unsigned char cfg;
	int bus, fd;

	for (bus = (forced_bus >= 0 ? forced_bus : 0);
	     bus <= (forced_bus >= 0 ? forced_bus : 8); bus++) {
		snprintf(path, sizeof(path), "/dev/i2c-%d", bus);
		fd = open(path, O_RDWR);
		if (fd < 0)
			continue;
		g_fd = fd;
		if (ioctl(fd, I2C_SLAVE, AP3216_ADDR) < 0 ||
		    read_reg(AP3216_REG_SYS_CFG, &cfg) < 0) {
			g_fd = -1;
			close(fd);
			continue;
		}
		*real_bus = bus;
		return 0;
	}
	return -1;
}

static int read_once(int bus)
{
	unsigned char als_l, als_h, ir_l, ir_h, ps_l, ps_h;
	unsigned als, ir, ps;

	if (write_reg(AP3216_REG_SYS_CFG, 0x03) < 0) {
		fprintf(stderr, "ap3216: write cfg: %s\n", strerror(errno));
		return 1;
	}
	/* 三路转换最长大约 100ms, 写完立刻读会把上一轮的旧值读出来 */
	usleep(200 * 1000);
	...
	als = (als_h << 8) | als_l;
	ir = (ir_h << 8) | ir_l;
	ps = ((ps_h & 0x3f) << 4) | (ps_l & 0x0f);
	printf("ap3216 bus=%d addr=0x%02x als=%u ir=%u ps=%u lux=%.1f\n",
	       bus, AP3216_ADDR, als, ir, ps, als * ALS_LUX_PER_COUNT);
	return 0;
}
```

`g_fd = fd` 必须在探测期间就挂上——read_reg 只认 g_fd，探测失败先
置回 -1 再 close（TechReports 09 的 4.1 节：这个次序错一次，板上
strace 抓到 `write(-1)` EBADF）。PS 数据寄存器只取低 10 位（高 6 位
是标志位），掩码写在合成表达式里。ALS 撕裂读嫌疑（两字节分两次事务）
记在 TechReports 09 的 4.2 节，未修。

## items/serial_loop.c

```c
// items/serial_loop.c  [24-58] termios 与帧(节选)
static int configure(int fd)
{
	struct termios tio;

	if (tcgetattr(fd, &tio) != 0)
		return -1;
	cfmakeraw(&tio);
	cfsetispeed(&tio, B115200);
	cfsetospeed(&tio, B115200);
	tio.c_cflag |= CLOCAL | CREAD;   /* 忽略调制解调器线, 打开接收 */
	tio.c_cc[VMIN] = 0;              /* read 不等满缓冲 */
	tio.c_cc[VTIME] = 10;            /* 1 秒内没数据就返回 */
	return tcsetattr(fd, TCSANOW, &tio);
}

/* 填一帧, 返回总长(恒为 FRAME_LEN)。校验和覆盖前面 10 个字节。 */
static int frame_build(int seq, char *out)
{
	unsigned char sum = 0;
	int n, i;

	n = sprintf(out, "PING %04x ", seq & 0xffff);
	for (i = 0; i < n; i++)
		sum ^= (unsigned char)out[i];
	n += sprintf(out + n, "%02x\n", sum);
	return n;
}
```

```c
// items/serial_loop.c  [96-104] 打开与超时语义(节选)
	fd = open(device, O_RDWR | O_NOCTTY | O_NONBLOCK);
	...
	/* 非阻塞打开是为了 open 永不卡住(有的驱动要等载波);
	 * 配置完再把 O_NONBLOCK 摘掉, read 的 VTIME 超时只在阻塞模式下生效 */
	fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
```

`O_NOCTTY` 防止串口成为控制台（这台设备是控制台本身时尤其要紧）。
"非阻塞打开 + 阻塞读写"的两段式是 termios 的标准姿势：VTIME 超时
只对阻塞 read 生效，而 open 永远非阻塞才不会被等载波的驱动挂住。
回显核对判据（check_gui.sh [22]）用伪终端当对端；`--probe` 模式
不发数据，板上调试串口就这样验证。注错判据 [22r] 把校验和的起点
错开一个字节，回显核对当场变红。

## 执行顺序

| 步 | 端到端成功路径（一次点击"mem"） | 分叉 |
|---|---|---|
| init | config→字体降级链→注册两页→切主页 | 字体选不上 → builtin 继续 |
| 主循环 | input_get_event 阻塞到事件 | 超时/EOF/q → 出循环 |
| press | on_event → ui_button_press → 重画按下态 | 空地按下无事发生 |
| release | 命中 → on_item_click → fork+exec → waitpid | 抬在框外 → 只回弹 |
| 命令 | `/bin/sh -c "head -3 /proc/meminfo"` rc=0 | execl 失败 → 子进程 127 |

## 容易读错的地方

1. **命令执行是同步的**：主循环卡在 waitpid，界面对长命令无响应。
   测试项都是秒级以下命令，这是当前场景的接受项。
2. **`(void)item_count` 不是笔误**：item_rect 只需要 index 与屏幕宽，
   item_count 是为对称签名保留的参数，VOID 压制 unused。
3. **两个 items 不链层与 FreeType**：Makefile 的 items 链接规则只带
   `common.o`——它们是独立的应用编程练习，上板体积因此从 3.2MB
   降到 0.5MB，串口上传少 40 块。
4. **布局常量是三层契约**：business_internal.h 定义、两个页面消费、
   判据脚本按它算点击坐标，改一处必须三处同步。

## 消费者清单

| 消费者 | 用到的接口 |
|---|---|
| main.c | `business_run()`（main_loop 一行） |
| 配置文件 gui.conf | `command` 字段点名 items 程序 |
| check_gui.sh [21]/[22] | 主循环日志行、items 的退出码 |
| TechReports 08/09 | 布局公式、端到端事件数 |
