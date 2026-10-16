#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"
#include "font/font_manager.h"
#include "ui/ui_manager.h"

/*
 * 按钮 = 一块矩形 + 一个居中标签 + 两个状态色。
 * 出图依赖 display 层(填矩形、flush), 出字依赖 font 层(测外框、画文本),
 * 所以本层在层表里必须排在它俩后面; main.c 的层表顺序就是依赖顺序。
 */

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
