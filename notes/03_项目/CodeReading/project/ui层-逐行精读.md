# ui 层逐行精读

代码路径与总行数（`grep -n ''` 于 2026-10-04 核对）：
`ui/ui_manager.c`（214 行）+ `ui/ui_manager.h`（40 行）。

前置知识：display 层的 `disp_region` 左闭右开约定、font 层的墨迹外框
（`struct font_text_metrics`）。文件定位：层表第四层，依赖 display 与
font。消费者：page 层不直接用，business 层两个具体页面用全套按钮接口，
`unittest/ui_test` 用除回调注册外的全部接口。

## ui_manager.h：对外接口

```c
// ui/ui_manager.h  [13-38] 正文
struct ui_button;

/* 点击回调: 按下并在同一颗按钮内抬起才触发 */
typedef void (*ui_on_click)(struct ui_button *btn, void *ctx);

int  ui_init(void);
void ui_exit(void);

/* 坐标是按钮外框, 与显示像素同单位; 失败返回 NULL */
struct ui_button *ui_button_create(const char *label, int x, int y,
				   int w, int h,
				   ui_on_click on_click, void *ctx);
void ui_button_destroy(struct ui_button *btn);
int  ui_button_count(void);

/* 把当前所有按钮重画一遍并 flush */
void ui_button_draw_all(void);

/* 指针按下/抬起事件喂给按钮层; 命中返回 1 */
int  ui_button_press(int x, int y);
int  ui_button_release(int x, int y);

/* 单测用: 指定按钮的按下态与命中测试, 不走回调 */
int  ui_button_is_pressed(const struct ui_button *btn);
int  ui_button_hit(const struct ui_button *btn, int x, int y);
```

按钮句柄是不透明指针，内部结构对外不可见。`press/release` 不吃
`input_event_data` 整个结构体、只吃两个 int——ui 层不 include input 层，
事件怎么从设备走到这两个 int 是 page/business 的事。

## ui_manager.c

### [14-34] 常量与内部结构

```c
#define UI_LABEL_MAX 64
#define UI_BORDER    1            /* 边框宽度, 像素 */

#define UI_BG_NORMAL   0x303030u   /* 静止底色 */
#define UI_BG_PRESSED  0x707070u   /* 按下底色, 判据数的就是这两色的差 */
#define UI_BORDER_RGB  0x909090u
#define UI_TEXT_RGB    0xffffffu

struct ui_button {
	char label[UI_LABEL_MAX];
	struct disp_region rect;
	int pressed;
	ui_on_click on_click;
	void *ctx;
	struct ui_button *next;
};

static struct ui_button *g_list;
static int g_count;
static int g_inited;
```

颜色常量的注释指明它们同时是判据对象：`count.sh` 在显存转储里数的
就是 0x303030 与 0x707070 的个数差（判据 [19]）。改颜色 = 改判据，
一个动作必须两处同步。

### [36-61] init/exit

```c
int ui_init(void)
{
	if (g_inited)
		return ERR_OK;
	g_list = NULL;
	g_count = 0;
	g_inited = 1;
	LOG_INFO("ui init OK");
	return ERR_OK;
}

void ui_exit(void)
{
	struct ui_button *b, *next;

	if (!g_inited)
		return;
	for (b = g_list; b != NULL; b = next) {
		next = b->next;
		free(b);
	}
	g_list = NULL;
	g_count = 0;
	g_inited = 0;
	LOG_INFO("ui exit OK");
}
```

exit 的总清理循环逐个 save-next 再 free——页面上谁忘了 destroy，
这里兜底。TechReports 08 的 4.5 节解释过它的含义：留在链表上的按钮
不构成 ASan 泄漏，只有这条循环失效（free 被注错掉）才会红。

### [63-109] 画一条按钮

```c
static void fill_border(const struct disp_region *r, unsigned int rgb)
{
	struct disp_region edge;

	edge = (struct disp_region){ r->x, r->y, r->w, UI_BORDER };
	disp_fill_rect(&edge, rgb);
	edge = (struct disp_region){ r->x, r->y + r->h - UI_BORDER, r->w, UI_BORDER };
	disp_fill_rect(&edge, rgb);
	edge = (struct disp_region){ r->x, r->y, UI_BORDER, r->h };
	disp_fill_rect(&edge, rgb);
	edge = (struct disp_region){ r->x + r->w - UI_BORDER, r->y, UI_BORDER, r->h };
	disp_fill_rect(&edge, rgb);
}

/* 标签按墨迹外框居中: baseline 抬到 (盒高-墨高)/2 再抵掉墨迹顶。
 * 没有墨迹(空串/全缺字)就不画字, 只留一块底色。 */
static void draw_label(const struct ui_button *b)
{
	struct font_text_metrics m;
	size_t bad;
	int x, baseline;

	if (font_measure_utf8(b->label, strlen(b->label), &m, &bad) != ERR_OK)
		return;
	if (m.ink_w == 0 || m.ink_h == 0)
		return;
	x = b->rect.x + (b->rect.w - m.ink_w) / 2 - m.ink_x;
	baseline = b->rect.y + (b->rect.h - m.ink_h) / 2 - m.ink_y;
	font_draw_utf8(b->label, strlen(b->label), x, baseline,
		       UI_TEXT_RGB, &m, &bad);
}

static void draw_one(const struct ui_button *b)
{
	unsigned int bg = b->pressed ? UI_BG_PRESSED : UI_BG_NORMAL;
	struct disp_region inner;

	inner = (struct disp_region){ b->rect.x + UI_BORDER,
				      b->rect.y + UI_BORDER,
				      b->rect.w - 2 * UI_BORDER,
				      b->rect.h - 2 * UI_BORDER };
	disp_fill_rect(&inner, bg);
	draw_label(b);
	fill_border(&b->rect, UI_BORDER_RGB);
	disp_flush(&b->rect);
}
```

居中的几何：font 层的墨迹外框以 baseline 为原点、ink_y 可为负
（"g" 的尾巴在 baseline 之下），所以 x 与 baseline 各自要减一遍
`ink_x`/`ink_y` 把外框挪回"以按钮盒左上角为参照"的坐标系。画序
底色 → 文字 → 边框，最后一次 `disp_flush` 整块提交——flush 的粒度
是一颗按钮而不是一次 fill。

### [110-159] 生命周期与重画

```c
struct ui_button *ui_button_create(const char *label, int x, int y,
				   int w, int h,
				   ui_on_click on_click, void *ctx)
{
	struct ui_button *b;

	if (label == NULL || w <= 0 || h <= 0)
		return NULL;
	b = calloc(1, sizeof(*b));
	if (b == NULL)
		return NULL;
	snprintf(b->label, sizeof(b->label), "%s", label);
	b->rect.x = x;
	b->rect.y = y;
	b->rect.w = w;
	b->rect.h = h;
	b->on_click = on_click;
	b->ctx = ctx;
	b->next = g_list;
	g_list = b;
	g_count++;
	return b;
}

void ui_button_destroy(struct ui_button *btn)
{
	struct ui_button **pp;

	for (pp = &g_list; *pp != NULL; pp = &(*pp)->next) {
		if (*pp == btn) {
			*pp = btn->next;
			free(btn);
			g_count--;
			return;
		}
	}
}

int ui_button_count(void)
{
	return g_count;
}

void ui_button_draw_all(void)
{
	const struct ui_button *b;

	for (b = g_list; b != NULL; b = b->next)
		draw_one(b);
}
```

destroy 用二级指针摘链——循环变量是"指向 next 字段的指针"，命中时
`*pp = btn->next` 同时覆盖头指针与中间 next 两种情况，不用特判链表头。
create 不画（画是显式的 `draw_all` 或页面的职责），只入链表。

### [161-214] 命中与按下态

```c
static struct ui_button *find_at(int x, int y)
{
	struct ui_button *b;

	for (b = g_list; b != NULL; b = b->next) {
		if (x >= b->rect.x && x < b->rect.x + b->rect.w &&
		    y >= b->rect.y && y < b->rect.y + b->rect.h)
			return b;
	}
	return NULL;
}

int ui_button_hit(const struct ui_button *btn, int x, int y)
{
	if (btn == NULL)
		return 0;
	return x >= btn->rect.x && x < btn->rect.x + btn->rect.w &&
	       y >= btn->rect.y && y < btn->rect.y + btn->rect.h;
}

int ui_button_is_pressed(const struct ui_button *btn)
{
	return btn != NULL ? btn->pressed : 0;
}

int ui_button_press(int x, int y)
{
	struct ui_button *b = find_at(x, y);

	if (b == NULL)
		return 0;
	b->pressed = 1;
	draw_one(b);
	return 1;
}

int ui_button_release(int x, int y)
{
	struct ui_button *b;
	int clicked = 0;

	/* 按下的按钮只有一颗(单指针); 挪出区域再抬起算放弃, 不触发回调 */
	for (b = g_list; b != NULL; b = b->next) {
		if (!b->pressed)
			continue;
		if (ui_button_hit(b, x, y) && b->on_click != NULL) {
			b->on_click(b, b->ctx);
			clicked = 1;
		}
		b->pressed = 0;
		draw_one(b);
	}
	return clicked;
}
```

release 扫全链表而不是只找按下点：按下与抬起之间指针可以走出按钮，
抬起位置只决定"这算不算点击"，回弹（清 pressed 并重画）无条件发生。
回调在清态之前触发——回调里如果重开页面，看到的按钮状态已经是干净的。

## 执行顺序

| 步 | 成功路径（一次点击） | 失败/放弃路径 |
|---|---|---|
| press(x,y) | find_at 命中 → pressed=1 → 重画 → 返回 1 | 未命中返回 0，屏幕不变 |
| release(x,y) | 命中同一颗 → 回调 → 清态重画 → 返回 1 | 抬在框外：只回弹，不回调 |
| destroy | 摘链 + free | 句柄不在链表上：静默返回 |

## 容易读错的地方

1. **press/release 的返回值含义不同**：press 返回"命中了吗"，release
   返回"触发回调了吗"。判据 [19] 分别用它们验证命中路径与放弃路径。
2. **颜色是判据的一部分**：`UI_BG_PRESSED` 改值必须同步 [19r] 注错判据
   的期望分布（TechReports 08 的 4.5 节是教训的反面）。
3. **draw_all 的顺序**：链表头插法意味着后创建的先画，重叠时后建的
   在上层；当前布局按钮不重叠，这条只在未来加浮层时生效。

## 消费者清单

| 消费者 | 用到的接口 |
|---|---|
| business/business_main_page.c | create/destroy/press/release/draw_all/count |
| business/business_settings_page.c | 同上（一颗按钮） |
| unittest/ui_test.c | 全部接口（含 `is_pressed`/`hit`） |
| check_gui.sh [19] | 显存转储里数两种底色像素 |
