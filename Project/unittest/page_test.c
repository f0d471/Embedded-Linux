/* page 层单测: 两颗最简页面互相切换 2*rounds+1 次, 日志给切换与建毁顺序,
 * ASan 判据看建毁是否平衡(泄漏即红)。 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"
#include "font/font_manager.h"
#include "page/page_manager.h"
#include "ui/ui_manager.h"

#define BTN_W 30
#define BTN_H 20

static struct ui_button *g_btn_a;
static struct ui_button *g_btn_b1;
static struct ui_button *g_btn_b2;
static int g_a_creates, g_a_destroys, g_b_creates, g_b_destroys;
static int g_switches;

/* 模拟一次点击: 按下 + 抬起两条指针事件 */
static void click(int x, int y)
{
	struct input_event_data ev;

	memset(&ev, 0, sizeof(ev));
	ev.kind = INPUT_KIND_POINTER;
	ev.x = x;
	ev.y = y;
	ev.buttons = INPUT_BUTTON_LEFT;
	page_dispatch(&ev);
	ev.buttons = 0;
	page_dispatch(&ev);
}

static int a_create(void)
{
	g_a_creates++;
	g_btn_a = ui_button_create("A", 10, 10, BTN_W, BTN_H, NULL, NULL);
	if (g_btn_a == NULL)
		return ERR_NOMEM;
	printf("page A create count=%d\n", ui_button_count());
	return ERR_OK;
}

static void a_destroy(void)
{
	if (g_btn_a != NULL) {
		ui_button_destroy(g_btn_a);
		g_btn_a = NULL;
	}
	g_a_destroys++;
}

static int b_create(void)
{
	g_b_creates++;
	g_btn_b1 = ui_button_create("B1", 10, 40, BTN_W, BTN_H, NULL, NULL);
	g_btn_b2 = ui_button_create("B2", 50, 40, BTN_W, BTN_H, NULL, NULL);
	if (g_btn_b1 == NULL || g_btn_b2 == NULL)
		return ERR_NOMEM;
	printf("page B create count=%d\n", ui_button_count());
	return ERR_OK;
}

static void b_destroy(void)
{
	if (g_btn_b1 != NULL) {
		ui_button_destroy(g_btn_b1);
		g_btn_b1 = NULL;
	}
	if (g_btn_b2 != NULL) {
		ui_button_destroy(g_btn_b2);
		g_btn_b2 = NULL;
	}
	g_b_destroys++;
}

static void a_on_event(const struct input_event_data *ev)
{
	if (ev->kind == INPUT_KIND_POINTER &&
	    (ev->buttons & INPUT_BUTTON_LEFT) &&
	    ev->x >= 10 && ev->x < 10 + BTN_W &&
	    ev->y >= 10 && ev->y < 10 + BTN_H) {
		g_switches++;
		page_switch("B");
	}
}

static void b_on_event(const struct input_event_data *ev)
{
	if (ev->kind == INPUT_KIND_POINTER &&
	    (ev->buttons & INPUT_BUTTON_LEFT) &&
	    ev->x >= 10 && ev->x < 10 + BTN_W &&
	    ev->y >= 40 && ev->y < 40 + BTN_H) {
		g_switches++;
		page_switch("A");
	}
}

static struct page_ops g_page_a = {
	.name = "A", .create = a_create, .destroy = a_destroy,
	.on_event = a_on_event,
};
static struct page_ops g_page_b = {
	.name = "B", .create = b_create, .destroy = b_destroy,
	.on_event = b_on_event,
};

int main(int argc, char **argv)
{
	int rounds = argc > 1 ? atoi(argv[1]) : 50;
	int i;

	if (display_init() != ERR_OK || font_init() != ERR_OK ||
	    ui_init() != ERR_OK || page_init() != ERR_OK)
		return 1;
	page_register(&g_page_a);
	page_register(&g_page_b);
	if (page_switch("A") != ERR_OK)
		return 1;

	for (i = 0; i < rounds; i++) {
		click(15, 15);    /* A 的按钮: A -> B */
		click(15, 45);    /* B1 的按钮: B -> A */
	}

	printf("page_test creates=%d/%d destroys=%d/%d switches=%d"
	       " final=%s count=%d\n",
	       g_a_creates, g_b_creates, g_a_destroys, g_b_destroys,
	       g_switches, page_current_name(), ui_button_count());

	page_exit();
	ui_exit();
	font_exit();
	display_exit();
	return 0;
}
