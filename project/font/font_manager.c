#include "common.h"
#include "font/font_manager.h"

static int g_inited;

int font_init(void)
{
	if (g_inited)
		return ERR_OK;

	/* TODO 第 04 章 文字显示: 装载 ASCII 点阵 / HZK16 中文 / freetype 矢量字体 */

	g_inited = 1;
	LOG_INFO("font init OK");
	return ERR_OK;
}

void font_exit(void)
{
	if (!g_inited)
		return;

	/* TODO 释放 font_init 里申请的资源, 顺序与申请时相反 */

	g_inited = 0;
	LOG_INFO("font exit OK");
}
