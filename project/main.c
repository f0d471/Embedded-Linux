/*
 * 量产工具主程序。
 *
 * 这个文件里不允许出现任何具体硬件操作 -- 不 open 设备节点, 不碰 mmap,
 * 不认识 /dev 下的任何路径。它只做三件事:
 *   1. 按依赖顺序把各层拉起来
 *   2. 跑主循环
 *   3. 反序把各层关掉
 *
 * 这一条守住了, 项目才长得大。破了之后就回不来了。
 */

#include <stdlib.h>

#include "common.h"

#include "display/disp_manager.h"
#include "input/input_manager.h"
#include "font/font_manager.h"
#include "ui/ui_manager.h"
#include "page/page_manager.h"
#include "business/business_manager.h"

struct layer {
	const char *name;
	int  (*init)(void);
	void (*exit)(void);
};

/*
 * 表的顺序就是依赖顺序: 靠后的层可以用靠前的层, 反过来不行。
 * 退出时严格反序, 保证一个层被关掉时, 依赖它的层已经先关了。
 */
static const struct layer g_layers[] = {
	{ "display",  display_init,  display_exit  },
	{ "input",    input_init,    input_exit    },
	{ "font",     font_init,     font_exit     },
	{ "ui",       ui_init,       ui_exit       },
	{ "page",     page_init,     page_exit     },
	{ "business", business_init, business_exit },
};

/* 反序退出前 n 层。n 等于层数就是全部退出 */
static void layers_exit(int n)
{
	int i;

	for (i = n - 1; i >= 0; i--)
		g_layers[i].exit();
}

static int layers_init(void)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(g_layers); i++) {
		ret = g_layers[i].init();
		if (ret != ERR_OK) {
			LOG_ERR("%s_init failed: %s", g_layers[i].name, err_str(ret));
			/* 只回滚已经成功的那几层, 没 init 过的不能 exit */
			layers_exit(i);
			return ret;
		}
	}

	return ERR_OK;
}

static int main_loop(void)
{
	/* TODO 项目整合阶段: 交给 page 层跑页面事件循环 */
	LOG_INFO("framework is up, no page to run yet");
	return ERR_OK;
}

int main(int argc, char **argv)
{
	int ret;
	const char *log_path;

	(void)argc;
	(void)argv;

	/*
	 * 板子上只有一根串口, 输出刷过去就没了, 也没法回头翻。设了 LOG_FILE 就把
	 * 日志整条接到那个文件, 事后能查; 没设就照旧打到串口。
	 * 这一步必须排在 layers_init 前面: 接晚了, 已经打出去的那几行就落不进文件。
	 */
	log_path = getenv("LOG_FILE");
	if (log_path != NULL) {
		ret = log_redirect(log_path);
		if (ret != ERR_OK) {
			LOG_ERR("cannot redirect log to %s: %s", log_path, err_str(ret));
			return 1;
		}
	}

	ret = layers_init();
	if (ret != ERR_OK)
		return 1;

	ret = main_loop();

	layers_exit(ARRAY_SIZE(g_layers));

	return (ret == ERR_OK) ? 0 : 1;
}
