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

// 表的顺序就是依赖顺序
static const struct layer g_layers[] = {
	{ "display",  display_init,  display_exit  },
	{ "input",    input_init,    input_exit    },
	{ "font",     font_init,     font_exit     },
	{ "ui",       ui_init,       ui_exit       },
	{ "page",     page_init,     page_exit     },
	{ "business", business_init, business_exit },
};

// 反序退出前 n 层
static void layers_exit(int n)
{
	int i;

	for (i = n - 1; i >= 0; i--)
		g_layers[i].exit();
}

// 顺序初始化所有层
static int layers_init(void)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(g_layers); i++) {
		ret = g_layers[i].init();
		if (ret != ERR_OK) {
			LOG_ERR("%s_init failed: %s", g_layers[i].name, err_str(ret));
			// 只回滚已经成功的那几层, 没 init 过的不能 exit
			layers_exit(i);
			return ret;
		}
	}

	return ERR_OK;
}

// 主循环
static int main_loop(void)
{
	LOG_INFO("framework is up, no page to run yet");
	return ERR_OK;
}

int main(int argc, char **argv)
{
	int ret;
	const char *log_path;

	(void)argc;
	(void)argv;

	// 日志重定向
	log_path = getenv("LOG_FILE");
	if (log_path != NULL) {
		ret = log_redirect(log_path);
		if (ret != ERR_OK) {
			LOG_ERR("cannot redirect log to %s: %s", log_path, err_str(ret));
			return 1;
		}
	}

	// 初始化所有层
	ret = layers_init();
	if (ret != ERR_OK)
		return 1;

	ret = main_loop();

	// 退出所有层
	layers_exit(ARRAY_SIZE(g_layers));

	return (ret == ERR_OK) ? 0 : 1;
}
