#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "common.h"
#include "config/config.h"
#include "display/disp_manager.h"
#include "font/font_manager.h"
#include "page/page_manager.h"
#include "ui/ui_manager.h"

#include "business/business_internal.h"
#include "business/business_manager.h"

static int g_inited;

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
