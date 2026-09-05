# common 逐行精读

对应代码：`project/include/common.h`（61 行）与 `project/common.c`（15 行）。

前置：C 预处理器的执行时机，见 [`notes/01_应用编程/01_工具链与构建系统.md`](../../../01_应用编程/01_工具链与构建系统.md)
第 3 节（GCC 的四个步骤，预处理这一步）。

---

## 1. 文件定位

`include/common.h` 是全项目唯一的公共头文件，六层和 `main.c` 全都包含它。
它不定义任何业务数据结构，只定义三样东西：错误码、日志宏、一个数组长度宏。

它的存在理由是"不允许各层自己发明错误码和日志格式"。
六层是分别在六章里写出来的，中间隔着几个月。没有这个文件的话，
显示层会返回 `-1`，输入层会返回 `-EIO`，字体层会返回 `0` 表示失败，
到项目整合的时候没有一个上层能统一判断。

`common.c` 只有一个函数，把错误码翻译成字符串。它单独成文件而不是写成
头文件里的 `static inline`，是因为它是一张会长大的表，
放在头文件里会被每个 `.c` 各展开一份。

---

## 2. 包含保护与唯一的系统头（第 1 到 4 行）

```c
#ifndef __COMMON_H
#define __COMMON_H

#include <stdio.h>
```

包含保护用的是双下划线前缀加文件名。同一个 `.c` 可能通过两条路径包含到它
（自己直接包含一次，再经某层的头文件间接包含一次），没有这层保护就是重复定义。

`#include <stdio.h>` 放在这里不是为了方便，是**日志宏用到了 `fprintf` 和 `stderr`**。
宏在展开处才被编译，如果这个头文件不带上 `stdio.h`，
那么每个用到 `LOG_INFO` 的 `.c` 都得自己先包含 `stdio.h`，
少一个就报"隐式声明 fprintf"。宏自带依赖，这是宏和函数的一个实际差别。

尖括号而不是双引号：`stdio.h` 要从工具链的系统目录里找，
交叉编译时会自动落到 ARM 那一份上。用双引号会先在当前目录找，
在这里没有意义。

---

## 3. 错误码（第 11 到 25 行）

```c
/*
 * 统一错误码。约定: 0 表示成功, 负数表示失败, 任何层的 init 都不许返回正数。
 * 上层只需判断 != ERR_OK, 需要具体原因时用 err_str() 转成可读字符串。
 */
enum {
	ERR_OK       =  0,   /* 成功 */
	ERR_PARAM    = -1,   /* 参数非法 */
	ERR_NOMEM    = -2,   /* 内存不足 */
	ERR_IO       = -3,   /* 设备打开或读写失败 */
	ERR_NOTSUP   = -4,   /* 功能未实现, 或当前平台不支持 */
	ERR_NOTFOUND = -5,   /* 找不到指定对象 */
	ERR_BUSY     = -6,   /* 资源被占用 */
};

const char *err_str(int err);
```

用匿名 `enum` 而不是一串 `#define`。区别在调试器里：
`enum` 的名字进符号表，`gdb` 里 `p ret` 能显示名字；`#define` 在预处理阶段就没了，
调试器只能给你看 `-3`。代价是 `enum` 的成员是 `int` 类型，
不能像 `#define` 那样用在 `#if` 里，这里用不到。

**负数不是随手挑的，是为了让"成功"这个判断只有一种写法。**
约定里那句"任何层的 init 都不许返回正数"是给上层用的：
上层可以写 `if (ret != ERR_OK)`，也可以写 `if (ret < 0)`，两种写法等价。
如果允许正数表示"成功但有情况"，这两种写法就会分叉，
而分叉的地方在几个月后加新层时最容易写错。

此处假设各层不会自己 `return -1` 而绕过这张表，由**代码评审**保证；
若不成立，`err_str()` 会返回 `"invalid parameter"`，
把一个 IO 错误报成参数错误，比不报还坏。这是一处目前没有守门人的地方。

---

## 4. 日志级别开关（第 27 到 36 行）

```c
#ifndef LOG_LEVEL
#define LOG_LEVEL 2
#endif
```

`#ifndef` 包住 `#define`，效果是"命令行没给就用默认值"。
命令行怎么给见 `Makefile` 精读的 `CFLAGS_EXTRA`：

```
    make CFLAGS_EXTRA=-DLOG_LEVEL=0
```

`-DLOG_LEVEL=0` 相当于在每个 `.c` 的第一行插一句 `#define LOG_LEVEL 0`，
所以这里的 `#ifndef` 不成立，默认值不生效。

**级别在编译期决定，不在运行期。** 关掉的级别整条语句被预处理器删干净，
产物里连字符串常量都不剩。运行期开关（一个全局变量加一个 `if`）做不到这一点：
字符串还在，`if` 还在，只是不打印。嵌入式上这两件事都要钱：
字符串占 flash，`if` 占指令周期。

---

## 5. 日志宏（第 38 到 57 行）

```c
#define LOG_RAW(tag, fmt, ...) \
	fprintf(stderr, "[%s] %s:%d " fmt "\n", tag, __FILE__, __LINE__, ##__VA_ARGS__)
```

这一行里有四个记号值得单独看。

**`fmt` 不带引号地拼在字符串中间。** `"[%s] %s:%d " fmt "\n"` 利用的是 C 的
相邻字符串字面量自动拼接：调用方传 `"%s init OK"`，展开后得到
`"[%s] %s:%d %s init OK\n"`，是一个完整的字面量。
这要求 `fmt` **必须是字面量**，传一个 `char *` 变量进来会编译不过。
这是有意的：`printf(变量)` 是格式化字符串漏洞的经典形状，这里从语法上堵死。

**`__FILE__` 和 `__LINE__` 在展开处取值。** 它们由预处理器替换成宏被展开的那个
文件名和行号，不是本文件的。所以日志里显示的是 `display/disp_manager.c:14`，
指向真正打日志的那一行。

**`##__VA_ARGS__` 是 GNU 扩展。** 作用是零个可变参数时吞掉前面那个逗号。
写 `LOG_INFO("hello")` 时，标准写法 `__VA_ARGS__` 展开成
`..., __LINE__, )`，多一个逗号，编译报错；`##` 版本会把它吃掉。
代价是这一行不是标准 C，换成 clang 也能用，换成 MSVC 不行。
本仓只用 gcc，接受这个代价。

**输出到 `stderr` 而不是 `stdout`。** 两个理由：`stderr` 是无缓冲的，
程序崩溃时已经打出来的日志不会跟着缓冲区一起丢；
以及日志和程序的正常输出分开，`./product_tool > result.txt` 时日志仍然在屏幕上。
这一条在第 5 组判据里被用到：`LOG_LEVEL=0` 时量的是
`./build/x86/product_tool 2>&1 | wc -l`，`2>&1` 就是为了把 `stderr` 收进来。

三组开关的形状一样，以 `LOG_ERR` 为例：

```c
#if LOG_LEVEL >= 1
#define LOG_ERR(fmt, ...)   LOG_RAW("E", fmt, ##__VA_ARGS__)
#else
#define LOG_ERR(fmt, ...)   do {} while (0)
#endif
```

关掉时定义成 `do {} while (0)` 而不是定义成空。空定义会让

```c
    if (x)
        LOG_ERR("bad");
    else
        foo();
```

在关掉日志之后变成 `if (x) ; else foo();`——这一句碰巧还能编过。
换成 `if (x) LOG_ERR("bad"); else foo();` 里的展开更糟：
有些形状会让 `else` 找不到配对的 `if`。`do {} while (0)` 是一条完整语句，
后面可以跟分号，放在任何位置都和一条普通语句等价。

---

## 6. ARRAY_SIZE（第 59 行）

```c
#define ARRAY_SIZE(a)  ((int)(sizeof(a) / sizeof((a)[0])))
```

数组总字节数除以单个元素字节数。外面套 `(int)` 是因为 `sizeof` 的结果是
`size_t`（无符号），拿去和 `int` 类型的循环变量比较会触发
"有符号与无符号比较"的警告，而本仓的 `CFLAGS` 里有 `-Wall -Wextra`。

此处假设传进来的是**真数组**，由调用点保证；若传进来的是指针，
`sizeof(a)` 变成指针宽度（本机 8，ARM 上 4），结果是一个毫无意义的小数字，
而且不报错。`main.c` 里唯一的调用点 `ARRAY_SIZE(g_layers)` 传的是文件作用域的数组，
前提成立。

---

## 7. common.c：错误码翻译表（全文件 15 行）

```c
#include "common.h"

const char *err_str(int err)
{
	switch (err) {
	case ERR_OK:       return "ok";
	...
	default:           return "unknown error";
	}
}
```

返回 `const char *` 指向字符串字面量，字面量在 `.rodata` 段里，
生命周期是整个程序，所以返回它的指针是安全的，调用方不需要释放。

`switch` 而不是数组下标。错误码是负数，用数组要先取反再当下标，
多一次心算，而且新增一个不连续的错误码时会静默错位。
`switch` 加 `default` 在任何输入下都有确定的返回值。

`default` 这一支不能省。`err_str(-99)` 必须返回点什么，
函数不能走到结尾而没有 `return`——那是未定义行为，
`-Wall` 会报 "control reaches end of non-void function"。

---

## 8. 执行顺序

这两个文件里的东西分布在三个完全不同的时刻，混起来读会读错。

| 时刻 | 谁在干活 | 这时候发生了什么 |
|---|---|---|
| 预处理（编译之前） | cpp | `LOG_LEVEL` 的值定下来；关掉的那几级宏被替换成 `do {} while (0)`；`__FILE__` / `__LINE__` 被替换成常量 |
| 编译 | cc1 | `enum` 成员变成常量，`ARRAY_SIZE` 已经是一个编译期常数 |
| 运行 | 程序 | 只剩下 `fprintf` 调用和 `err_str` 的 `switch` |

第一行的直接后果是：**日志级别是编译期属性，同一份源码编出来的两个 `.bin`
行为不同。** 判据第 5 组量的就是这件事。

---

## 9. 容易读错的地方

**`#include <stdio.h>` 不是多余的**，日志宏用了 `fprintf` 和 `stderr`。删掉它，
所有没有自己包含 `stdio.h` 的 `.c` 都会报隐式声明。

**`LOG_LEVEL=0` 之后程序还是有输出的**，只是没有日志输出。
判据里量到 0 行，是因为这个骨架当前除了日志之外不打印任何东西。
以后 `business` 层开始打业务信息时，这条判据的期望值要跟着改。

**`##__VA_ARGS__` 里的 `##` 不能删。** 它不是"连接"的意思，
在这个位置它的作用是条件地删掉前一个逗号。

**`ARRAY_SIZE` 对指针不报错。** 它是本文件里唯一一个前提不成立时静默给错值的宏。

---

## 10. 消费者

| 文件 | 用到的部分 |
|---|---|
| `main.c` | 错误码、`LOG_ERR`、`LOG_INFO`、`ARRAY_SIZE`、`err_str()` |
| `display/disp_manager.c` 等六份 | `ERR_OK`、`LOG_INFO` |
| `check.sh` 第 100 到 102 行 | `LOG_LEVEL` 这个编译期开关 |
| `Makefile` 第 30 行 | 通过 `CFLAGS_EXTRA` 把 `-DLOG_LEVEL=` 传进来 |

`check.sh` 第 69 到 72 行临时造出来的那个 `display/disp_dummy.c` 也包含它，
用的是 `ERR_NOTSUP`。那个文件只在判据运行期间存在。
