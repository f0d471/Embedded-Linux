#include "common.h"
#include "input/input_manager.h"

static int g_inited;

int input_init(void)
{
	if (g_inited)
		return ERR_OK;

	/* TODO 第 05 章 输入系统: 打开 /dev/input/eventX, 起线程循环读 input_event */

	g_inited = 1;
	LOG_INFO("input init OK");
	return ERR_OK;
}

void input_exit(void)
{
	if (!g_inited)
		return;

	/* TODO 释放 input_init 里申请的资源, 顺序与申请时相反 */

	g_inited = 0;
	LOG_INFO("input exit OK");
}
