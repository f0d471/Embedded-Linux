# 空壳三层与 main 逐行精读

对应代码：`project/main.c`（100 行）、`ui/ui_manager.h`（13 行）与
`ui/ui_manager.c`（27 行）、`page/page_manager.h`（13 行）与
`page/page_manager.c`（27 行）、`business/business_manager.h`（13 行）与
`business/business_manager.c`（27 行）。

## 1. 文件定位

`main.c` 用一张层表管六个层的顺序启停与失败回滚；ui/page/business 三个空壳
只有幂等的 init/exit，TODO 注释标明各自将来依赖谁。空壳存在的理由：层表
今天就要以六层形态运转（判据 [1] 数 init/exit 各 6 行、顺序正反各验一次），
等到刀 9/刀 10 填实现时，构建、层序、回滚都已经验过。

前置知识：[从零开始读写 project 代码](../00-从零开始读写项目代码.md)第 5 节
（函数指针表）。

```
main.c
  g_layers[] = display → input → font → ui → page → business
  layers_init:  顺序 init, 失败则 layers_exit(i) 回滚已成功的前 i 层
  main_loop:    现在只打一行日志
  layers_exit:  反序 exit
```

## 2. main.c

### 第 1—27 行：include 与层表

```c
#include <stdlib.h>
#include <string.h>

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
```

依赖顺序写成数据：display 必须第一（input 的几何、font 的像素都依赖它），
input 在 font 前（同层表内 init 顺序即此）。行序是唯一的依赖声明，
判据 [1r] 从表里删掉一行后其余 5 层照常启停，证明层间没有隐式耦合——
表不完整时程序仍以残余层运行，错误在 init 行数判据上显形。
`const` 让表进只读段，运行期不可改。

### 第 29—61 行：回滚与顺序 init

```c
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
```

`layers_exit(i)` 的参数语义是"前 i 层已经成功"：下标从 `i-1` 倒数到 0，
正好是已成功的那几层。从 `i` 开始会把失败层自己也 exit 一遍——各层的
exit 都幂等（`g_inited` 挡着），但注释把约定写明，等价写法里这个最不容易
在层表增删时出错。`main_loop` 目前是占位：页面系统（刀 9）落地前没有可跑
的东西，一行日志证明执行到了这里。

### 第 63—100 行：main

```c
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

日志重定向在任何层 init 之前做，让后续所有 `LOG_*` 直接进文件。报错分支
按 `os_errno` 是否为 0 分两种格式：项目级拒绝（如 `LOG_FILE` 空串）没有
系统错误可带，系统级失败带上 `strerror`——两个通道的信息都在
（common 篇第 3 节）。判据 [6] 断言这两种输出的精确文本。
`layers_init` 失败时直接返回 1，此时没有任何层成功（或已回滚），无需 exit；
正常路径 `layers_exit(6)` 反序关全部层。进程退出码映射：主循环成功 0，
其余 1。

## 3. ui / page / business：同一形状的空壳

三个文件同构，差异只有层名与 TODO 注释。以 ui 为例，其余两份逐一引用。

### ui/ui_manager.h 第 1—13 行

```c
#ifndef __UI_MANAGER_H
#define __UI_MANAGER_H

/*
 * ui 层对外接口。
 * 这里只放函数声明, 不放内部结构体定义 -- 别的层看不见本层的内部状态,
 * 才谈得上以后能整层换掉。
 */

int  ui_init(void);
void ui_exit(void);

#endif /* __UI_MANAGER_H */
```

头文件注释是分层规则本身：内部结构不进公开头。三个层的公开面都是两个函数，
将来加控件、页面栈、业务调度时，公开面在各自头文件里扩，别层不改。

### ui/ui_manager.c 第 1—27 行

```c
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
```

### page/page_manager.c 第 6—27 行（.h 与 ui 同构，层名不同）

```c
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
```

### business/business_manager.c 第 6—27 行（.h 与 ui 同构，层名不同）

```c
int business_init(void)
{
	if (g_inited)
		return ERR_OK;

	/* TODO 业务逻辑, 项目整合阶段填, 这里是整个程序真正干活的地方 */

	g_inited = 1;
	LOG_INFO("business init OK");
	return ERR_OK;
}
```

三份空壳只有 TODO 注释不同，各自的依赖声明：ui 要 display+font，page 要
ui+input，business 在整合阶段填。幂等模式相同：`g_inited` 挡住重复 init 与
未 init 的 exit，回滚路径（`layers_exit`）对失败层调用 exit 时靠它兜住。

## 4. 执行顺序

```
main:  [LOG_FILE] → log_redirect(失败即退 1)
       → layers_init: display ✓ input ✓ font ✓ ui ✓ page ✓ business ✓
       → main_loop(一行日志) → layers_exit(6): business → page → ui → font → input → display
失败:  第 i 层 init 失败 → 打印层名与错误码 → layers_exit(i) 反滚 → 退 1
例:    font 失败(i=2) → exit input, display; ui/page/business 从未 init, 不碰
```

## 5. 容易读错的地方

- 层表顺序就是依赖顺序，调整顺序前先看各层 TODO 注释里声明的依赖。
- `layers_exit(i)` 的 i 是"已成功层数"，失败层不在其中。
- 三个空壳的 init 里 `g_inited = 1` 在 TODO 之后：将来填实现时，资源申请
  放 TODO 处，失败要在此前返回，不能走到 `g_inited = 1` 之后。
- 层间只经公开头交互（如 font 调 `disp_blend_pixel`）；空壳的 TODO 是规划，
  不构成现有依赖，判据 [1r] 专门证明了这一点。

## 6. 消费者清单

- 判据：`check_core.sh` [1]（启停顺序、正反各 6 行）、[1r]（删行注错）。
- `page_manager.c` 出现在 [10r] 注错里（往它头部塞 `/dev/fb0` 引用，
  验分层边界判据见红）。
- 未来的 ui/page/business 实现（路线图刀 9）在 TODO 处展开，公开头随之扩。
