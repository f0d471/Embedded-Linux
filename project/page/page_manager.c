#include "common.h"
#include "page/page_manager.h"

static int g_inited;

int page_init(void)
{
	if (g_inited)
		return ERR_OK;

	/* TODO 页面管理, 依赖 ui 画界面和 input 收事件 */

	g_inited = 1;
	LOG_INFO("page init OK");
	return ERR_OK;
}

void page_exit(void)
{
	if (!g_inited)
		return;

	/* TODO 释放 page_init 里申请的资源, 顺序与申请时相反 */

	g_inited = 0;
	LOG_INFO("page exit OK");
}
