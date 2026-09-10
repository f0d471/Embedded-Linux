# main.c 逐行精读

对应代码：`project/main.c`，107 行。

前置：函数指针的写法与 `common.h` 里的错误码、日志宏，
见 [common 逐行精读](common-逐行精读.md)。

---

## 1. 文件定位

整个程序的入口，也是唯一一个知道"一共有几层、按什么顺序起"的文件。

它的约束写在文件头注释里，是全仓最硬的一条：

```
 * 这个文件里不允许出现任何具体硬件操作 -- 不 open 设备节点, 不碰 mmap,
 * 不认识 /dev 下的任何路径。它只做三件事:
 *   1. 按依赖顺序把各层拉起来
 *   2. 跑主循环
 *   3. 反序把各层关掉
 *
 * 这一条守住了, 项目才长得大。破了之后就回不来了。
```

"破了之后就回不来了"不是修辞。一旦 `main.c` 里出现 `open("/dev/fb0")`，
显示层的初始化就分散在两个地方；下一次有人要加第二个显示后端时，
他要同时改 `main.c` 和 `display/`，而 `main.c` 是所有层共用的文件。
这种耦合是单向的：加进去容易，拆出来要动所有已经依赖它的代码。

---

## 2. 包含（第 13 到 22 行）

```c
#include <stdlib.h>

#include "common.h"

#include "display/disp_manager.h"
#include "input/input_manager.h"
#include "font/font_manager.h"
#include "ui/ui_manager.h"
#include "page/page_manager.h"
#include "business/business_manager.h"
```

九个包含，只有一个系统头 `stdlib.h`，为的是 `getenv`。
`stdio.h` 是被 `common.h` 带进来的，
`main.c` 自己不直接用它。系统头和项目头之间空一行分开，
是为了让"这个文件碰了哪些系统能力"一眼可见 —— 现在只碰了环境变量这一项。

六个层头文件的顺序和层表的顺序一致，也和分层图自底向上的顺序一致。
这个顺序在编译上没有任何作用（六个头文件互不依赖），
它的作用是让人在读到第 34 行的层表时，发现两处顺序一样，
从而确认这不是随手排的。

带目录前缀的写法见[层管理器空壳精读](层管理器空壳-逐行精读.md)第 3.1 节。

---

## 3. 层表（第 24 到 41 行）

```c
struct layer {
	const char *name;
	int  (*init)(void);
	void (*exit)(void);
};

static const struct layer g_layers[] = {
	{ "display",  display_init,  display_exit  },
	{ "input",    input_init,    input_exit    },
	{ "font",     font_init,     font_exit     },
	{ "ui",       ui_init,       ui_exit       },
	{ "page",     page_init,     page_exit     },
	{ "business", business_init, business_exit },
};
```

三个字段。`int (*init)(void)` 读法是从里往外：`init` 是一个指针，
指向一个不带参数、返回 `int` 的函数。括号不能省，`int *init(void)` 是
"返回 `int *` 的函数"，完全不同的东西。

**表驱动而不是六行顺序调用。** 六行顺序调用是这样的：

```c
    display_init();
    input_init();
    ...
```

它能跑，但做不到三件事：拿不到层名去打日志和做判据；
失败回滚要写成六层嵌套的 `goto` 或者六个 `if`；
以及退出时要再手写一遍反序的六行，两处顺序可能对不上。
换成表之后，顺序只写一遍，正序反序都从这一份数据来。

**`name` 字段不是为了好看。** 它是三样东西的唯一来源：
初始化失败时日志里的层名、六个 `*_init()` 自己打的那行日志里的层名
（那是各层自己写的字面量，与这里独立）、以及 `check.sh` 期望值的对照对象。

**`static const`。** `static` 让这张表不进全局符号表；
`const` 让它落进 `.rodata` 段，写它会段错误。这张表在运行期不该变，
把它放进只读段是用硬件来保证这件事。

层表和分层图的对应：

```
    g_layers[5]  business    <-- 最后 init, 最先 exit
    g_layers[4]  page
    g_layers[3]  ui
    g_layers[2]  font
    g_layers[1]  input
    g_layers[0]  display     <-- 最先 init, 最后 exit
```

数组下标由小到大就是自底向上。这个方向选定之后，
正序循环是 `i++`，反序循环是 `i--`，两个循环都不用做下标换算。

---

## 4. 反序退出（第 43 到 50 行）

```c
/* 反序退出前 n 层。n 等于层数就是全部退出 */
static void layers_exit(int n)
{
	int i;

	for (i = n - 1; i >= 0; i--)
		g_layers[i].exit();
}
```

参数是"前 n 层"而不是"从第几层开始"。这个选择让两个调用点都很自然：
正常退出传 `ARRAY_SIZE(g_layers)`，失败回滚传"已经成功的层数"。
两者都是"已经起来了几层"这个语义，调用方不需要做减一。

`i = n - 1` 起步。`n` 是个数，下标从 `n-1` 开始，这是把个数转成末位下标。
`n` 为 0 时循环一次都不进，对应"第一层就失败了，没有任何东西要回滚"。

此处假设 `n` 不超过数组长度，由**两个调用点**保证：
一个传数组长度，一个传循环变量 `i`，而 `i` 在那个位置一定小于数组长度。
若不成立，`g_layers[i].exit()` 会读到数组外的内存并当函数指针跳过去。
这里没有做范围检查，因为这个函数是 `static` 的，
调用点只有本文件里的两处，两处都看得见。

---

## 5. 正序初始化与失败回滚（第 52 到 67 行）

```c
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
```

**`layers_exit(i)` 里的 `i` 恰好就是已成功的层数。** 这是循环变量语义带来的：
进入第 `i` 次迭代时，下标 0 到 `i-1` 的层都已经成功了，一共 `i` 层。
第 `i` 层自己刚失败，不能退。所以传 `i` 而不是 `i+1` 或 `i-1`。

这是本文件里最容易写错的一行。写成 `layers_exit(i + 1)` 会对一个初始化失败的层
调 `exit`；写成 `layers_exit(i - 1)` 会漏掉一层不退。
两种错法都不会立刻出现象，只在某层第一次真的初始化失败的那天才炸，
而那一天多半是在板子上。

画出来：

```
    i=0  display  init OK
    i=1  input    init OK
    i=2  font     init FAIL
                    |
                    v
             layers_exit(2)
                    |
                    +--> g_layers[1].exit()   input
                    +--> g_layers[0].exit()   display
             font 没 init 成功, 不在回滚范围内
```

**错误码原样返回。** `return ret` 而不是 `return -1`：
上层需要知道是哪一类失败，而不只是"失败了"。
`err_str(ret)` 在日志里已经把它翻成了人话，返回值留给程序判断。

`ARRAY_SIZE(g_layers)` 在编译期就是常数 6，
所以这个循环的边界不需要维护，加一层就自动变成 7。

---

## 6. 主循环与入口（第 69 到 107 行）

```c
static int main_loop(void)
{
	/* TODO 项目整合阶段: 交给 page 层跑页面事件循环 */
	LOG_INFO("framework is up, no page to run yet");
	return ERR_OK;
}
```

现在打一行日志就返回。它存在的理由和六层空壳一样：
把位置占住，并且用 `TODO` 写明以后是谁来填。
它返回 `int` 而不是 `void`，是因为以后主循环会因为出错而中断，
那时需要把原因带出来。

```c
int main(int argc, char **argv)
{
	int ret;
	const char *log_path;

	(void)argc;
	(void)argv;

	/* 注释见源码第 84 到 88 行 */
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
```

**日志重定向必须排在 `layers_init()` 前面。** 这一段如果挪到初始化后面，
六层的 12 条 `init OK` / `exit OK` 里，前 6 条已经打到终端去了，
日志文件只剩 7 行。判据 `[6]` 期望的是 13 行，挪一下就会红。
这条顺序约束和层表那条（靠后的层可以用靠前的层）是同一类东西：
**能观测的就写成判据，写不成判据的就写进注释。**

**`getenv` 返回 `NULL` 和返回 `""` 是两回事。** `LOG_FILE` 没设是 `NULL`，
`LOG_FILE=` 这样写是 `""`。这里只判 `NULL`，空串那一半交给
`log_redirect` 内部去判并返回 `ERR_PARAM`（见 [common 精读](common-逐行精读.md) 第 9.1 节）。
分工的理由是：**参数合法性归被调方，"要不要调"归调用方。**

**重定向失败是致命的，直接 `return 1`。** 不是"退回到终端继续跑"。
理由是：用户显式设了 `LOG_FILE`，说明他要的就是那份日志；
静默地降级成打到终端，等于跑完了才发现什么都没留下。
这时 `LOG_ERR` 仍显示在原来的终端上，因为 `dup2` 没成功，`stderr` 的去向没有改变。

**`(void)argc;` 是在关警告。** `CFLAGS` 里有 `-Wextra`，它包含 `-Wunused-parameter`，
不用的参数会报警告。`main` 的签名不能改，所以用 `(void)` 把它们"用"一次。
以后开始解析命令行参数时，这两行删掉。

**`layers_init()` 失败之后直接 `return 1`，不调 `layers_exit()`。**
因为 `layers_init()` 内部已经回滚过了。在这里再调一次，
会对已经 `exit` 过的层再 `exit` 一次——虽然各层的幂等保护挡得住，
但语义上是重复的，而且掩盖了"谁负责回滚"这个问题。
责任划分是：谁初始化到一半失败，谁自己回滚干净。

**返回值只有 0 和 1。** shell 的退出码是 8 位无符号数，
直接 `return ret` 的话，`ERR_IO`（-3）会变成 253，
既不是约定的错误码也不好读。判据量的是退出码等于 0，
所以这里必须收敛到 0 和 1 两个值。

`main_loop()` 失败时仍然走 `layers_exit()` 再退出，不是提前 `return`。
主循环出错和初始化出错是两回事：这时六层都是起来的，必须全部关掉。

---

## 7. 执行顺序

一次正常运行的完整时间轴：

| 步 | 位置 | 动作 | 可观测输出 |
|---|---|---|---|
| 0 | `main` 第 89 到 96 行 | 查 `LOG_FILE`，设了就 `log_redirect()` | 无（此后的输出全落进那个文件） |
| 1 | `main` 第 98 行 | 调 `layers_init()` | 无 |
| 2 | `layers_init` i=0..5 | 依次调六个 `init` | 六行 `xxx init OK` |
| 3 | `main` 第 102 行 | 调 `main_loop()` | 一行 `framework is up...` |
| 4 | `main` 第 104 行 | `layers_exit(6)` | 六行 `xxx exit OK`，顺序反过来 |
| 5 | `main` 第 106 行 | 返回 0 | 退出码 0 |

六层各两行加 `framework is up` 一行，一次运行正好 **13 行**。
判据 `[6]` 里那几个 13 和 26 就是这么来的。

一次第三层失败的运行：

| 步 | 位置 | 动作 | 可观测输出 |
|---|---|---|---|
| 1 | `layers_init` i=0,1 | display、input 成功 | 两行 `init OK` |
| 2 | `layers_init` i=2 | font 返回非 `ERR_OK` | 一行 `font_init failed: <原因>` |
| 3 | `layers_exit(2)` | 反序退 input、display | 两行 `exit OK` |
| 4 | `main` 第 100 行 | 返回 1 | 退出码 1 |

第二张表目前**没有判据覆盖**，因为六层空壳全都无条件返回 `ERR_OK`，
构造不出失败。等某一层真的会失败之后要补一条。

---

## 8. 容易读错的地方

**`layers_exit(i)` 里的 `i` 不是"最后成功的那层的下标"，是"成功的层数"。**
两者差一，这是本文件唯一一个容易差一的地方。

**`layers_init()` 失败后 `main` 不再调 `layers_exit()`，不是漏了。** 见第 6 节。

**`(void)argc;` 不是无用语句**，去掉会在 `-Wextra` 下产生警告。

**层表里的 `name` 和各层自己日志里的层名是两份独立的字符串。**
`display_init()` 打的是 `LOG_INFO("display init OK")`，那个 `"display"` 写在
`display/disp_manager.c` 里，不是从层表读的。改层名要改两处。
判据量的是各层自己打的那一份。

**`return (ret == ERR_OK) ? 0 : 1;` 里 `ret` 是 `main_loop()` 的返回值**，
不是 `layers_init()` 的——后者已经在第 100 行提前返回了。

---

## 9. 消费者

| 文件 | 关系 |
|---|---|
| 六层的 `*_manager.h` | 被本文件包含，提供十二个函数声明 |
| `include/common.h` | 提供错误码、日志宏、`ARRAY_SIZE`、`err_str()` |
| `Makefile` 第 25 行 | `$(wildcard *.c)` 把本文件收进源文件列表 |
| `check.sh` 第 45 行 | `sed '/{ "business",/d'` 删掉层表里 business 那一行（源码第 40 行）做注错 |
| `check.sh` 第 50 行 | 从原目录复制一份 `main.c` 回来还原 |
| `check.sh` 第 104 到 144 行 | `LOG_FILE` 这条通路，以及 13 / 26 这两个行数 |

`check.sh` 那个 `sed` 匹配的是 `{ "business",` 这个字面形状。
层表的写法改成别的对齐方式（比如去掉 `"business"` 后面那个逗号前的空格），
这条注错会静默失效——它会删不掉任何东西，然后判据照常绿。
这是一处**注错本身可能失效而无人察觉**的地方，改层表格式时要回来跑一次
`check.sh` 确认 `[1r]` 那一组仍然报红。
