#include <stdint.h>
#include <string.h>

#include "common.h"
#include "config/config.h"
#include "display/disp_manager.h"
#include "ui/ui_manager.h"

#include "business/business_internal.h"

/*
 * 主页: 配置里每个测试项一颗按钮, 外加右下角一颗"设置"。
 * 按下只画按下态, 抬起(仍在按钮内)才执行命令。
 */

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
