#include "common.h"
#include "business/business_manager.h"

static int g_inited;

int business_init(void)
{
	if (g_inited)
		return ERR_OK;

	/* TODO 业务逻辑, 项目整合阶段填, 这里是整个程序真正干活的地方 */

	g_inited = 1;
	LOG_INFO("business init OK");
	return ERR_OK;
}

void business_exit(void)
{
	if (!g_inited)
		return;

	/* TODO 释放 business_init 里申请的资源, 顺序与申请时相反 */

	g_inited = 0;
	LOG_INFO("business exit OK");
}
