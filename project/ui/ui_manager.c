#include "common.h"
#include "ui/ui_manager.h"

static int g_inited;

int ui_init(void)
{
	if (g_inited)
		return ERR_OK;

	/* TODO 按钮等控件, 依赖 display 出图和 font 出字, 所以必须排在这两层后面 */

	g_inited = 1;
	LOG_INFO("ui init OK");
	return ERR_OK;
}

void ui_exit(void)
{
	if (!g_inited)
		return;

	/* TODO 释放 ui_init 里申请的资源, 顺序与申请时相反 */

	g_inited = 0;
	LOG_INFO("ui exit OK");
}
