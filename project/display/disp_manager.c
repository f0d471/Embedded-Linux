#include "common.h"
#include "display/disp_manager.h"

static int g_inited;

int display_init(void)
{
	if (g_inited)
		return ERR_OK;

	/* TODO 第 03 章 Framebuffer: 打开 /dev/fb0, 取 fb_var_screeninfo, mmap 出显存 */

	g_inited = 1;
	LOG_INFO("display init OK");
	return ERR_OK;
}

void display_exit(void)
{
	if (!g_inited)
		return;

	/* TODO 释放 display_init 里申请的资源, 顺序与申请时相反 */

	g_inited = 0;
	LOG_INFO("display exit OK");
}
