# main 逐行精读

代码路径与总行数（`grep -n ''` 于 2026-10-04 核对）：`main.c`（101 行）。

前置知识：`notes/00_基础/00_从源码到运行.md`（程序怎么被跑起来）。
文件定位：进程入口。它只做三件事——日志重定向、按层表顺序启停、
把主循环让给 business 层。main 不知道任何一层的内部，层表是它与
全部代码的交界。消费者：TechReports 01（骨架）、check_core.sh [1]
（启停顺序判据的提取规则 `awk '{print $(NF-2)}'` 依赖每层日志的
行尾三词是"层名 init OK"）。

```c
// main.c  [1-27]
#include <stdlib.h>
#include <string.h>

#include "common.h"

#include "display/disp_manager.h"
#include "input/input_manager.h"
#include "font/font_manager.h"
#include "ui/ui_manager.h"
#include "page/page_manager.h"
#include "config/config.h"
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
	{ "config",   config_init,   config_exit   },
	{ "business", business_init, business_exit },
};
```

层表是本章全部的架构。第 08 章加 config 时的动作只有两处：这里一行、
Makefile 的 `SUBDIRS` 一个词——第 01 章把加层的成本压到这个数，八层
以后依然成立。顺序即依赖：config 在 page 之后 business 之前，因为
page 要按配置建按钮、business 要按配置执行命令（路线图 3.4 节的
裁定原样落地）。

```c
// main.c  [29-61]
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

// 主循环: 事件从 input 层进来, 页面分发在 business 层, 这里只负责调它
static int main_loop(void)
{
	return business_run();
}
```

`layers_exit(i)` 的参数语义是"退出前 i 层"：第 i 层（下标从 0 计）
失败时，成功的是 0..i-1 共 i 层。main_loop 从第 01 章的"打印一行"
变成第 08 章的一行转发——事件循环住在 business 层，main 保持只管
启停的职责边界。

```c
// main.c  [63-101]
int main(int argc, char **argv)
{
	int ret;
	int os_errno = 0;
	const char *log_path;

	(void)argc;
	(void)argv;

	// 日志重定向
	log_path = getenv("LOG_FILE");

	if (log_path != NULL) {
		ret = log_redirect(log_path, &os_errno);
		if (ret != ERR_OK) {
			if (os_errno != 0) {
				LOG_ERR("cannot redirect log to %s: %s (%s)",
					log_path, err_str(ret), strerror(os_errno));
			} else {
				LOG_ERR("cannot redirect log to %s: %s",
					log_path, err_str(ret));
			}
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
```

日志重定向在任何层 init 之前——`log_redirect` 把 stderr 整条 dup2
到文件，此后的全部 LOG（含各层 init）天然落文件。失败报错区分
"系统调用失败（带 errno 文本）"与"参数非法（不带）"两种形态，
判据 [6] 逐字锁定这两个报错。退出码两个来源：init 失败 1、主循环
失败 1、成功 0——板上判据用退出码判定运行结果，这条约定从第 01 章
用到本章的端到端。

## 执行顺序

| 步 | 成功路径 | 失败路径 |
|---|---|---|
| LOG_FILE 设置 | dup2 后 20 条日志进文件 | 打不开 → 报错退出 1 |
| layers_init | 7 层依次 init OK | 某层失败 → 回滚已成功的层 → 退出 1 |
| main_loop | business_run 事件循环 | business 未 init → ERR_NOTSUP → 退出 1 |
| layers_exit(7) | 7 层反序 exit OK | — |

## 容易读错的地方

1. **层表顺序即依赖顺序**：调层不是按名字找，是按数组下标；把 config
   挪到 business 后面，business_init 里 `config_get()` 返回 NULL，
   起不来。判据 [1] 的顺序对账就是这条约束的守门人。
2. **`layers_exit(i)` 与 `layers_exit(ARRAY_SIZE(...))` 的 n 语义不同**：
   前者是"回滚前 i 层"，后者是"退出全部层"，两处共用一个函数。
3. **20 条日志**：7 init OK + 7 exit OK + config 详情 1 + business
   几何 1 + page created/destroyed 2 + loop end 1，共 20——判据 [6]
   的数字与层表长度联动，加层要改判据。

## 消费者清单

| 消费者 | 用到的接口 |
|---|---|
| build（Makefile） | main.o 链进 product_tool，unittest 以 `filter-out main.o` 排除 |
| check_core.sh [1]/[6] | 启停顺序与日志行数 |
| 全部七层 | init/exit 被层表引用，其余接口互不可见 |
