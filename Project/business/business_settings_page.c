#include <string.h>

#include "common.h"
#include "config/config.h"
#include "display/disp_manager.h"
#include "font/font_manager.h"
#include "ui/ui_manager.h"

#include "business/business_internal.h"

/*
 * 设置页: 把当前配置的要点写在屏幕上, 外加一颗"返回"。
 * 它存在的意义是让"切页释放旧页资源"有一个可以判据化的对象。
 */

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

static void settings_destroy(void)
{
	if (g_back_btn != NULL) {
		ui_button_destroy(g_back_btn);
		g_back_btn = NULL;
	}
	LOG_INFO("page settings destroyed");
}

static void settings_on_event(const struct input_event_data *ev)
{
	if (ev->kind != INPUT_KIND_POINTER)
		return;
	if (ev->buttons & INPUT_BUTTON_LEFT)
		ui_button_press(ev->x, ev->y);
	else
		ui_button_release(ev->x, ev->y);
}

static struct page_ops g_settings_page = {
	.name = "settings",
	.create = settings_create,
	.destroy = settings_destroy,
	.on_event = settings_on_event,
};

void business_settings_page_register(void)
{
	page_register(&g_settings_page);
}
