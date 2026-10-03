# common 逐行精读

对应代码：`project/include/common.h`（50 行）、`project/common.c`（51 行）。

## 1. 文件定位

错误码、日志宏与日志重定向，全项目唯一没有层归属的公共件。所有 `.c` 都包含
`common.h`；`log_redirect()` 由 `main.c` 在任何层启动之前调用一次。
判据在 `check_core.sh` 的 [5]（日志开关）与 [6]（落文件、O_APPEND、errno 带出）。

前置知识：[从零开始读写 project 代码](../00-从零开始读写项目代码.md)第 6/8 节
（位运算、错误码与资源回滚）；第 02 章笔记的文件 IO 部分。

## 2. include/common.h

### 第 1—15 行：guard 与错误码

```c
#ifndef __COMMON_H
#define __COMMON_H

#include <stdio.h>

//统一错误码。约定: 0 表示成功, 负数表示失败, 任何层的 init 都不许返回正数
enum {
	ERR_OK       =  0,   /* 成功 */
	ERR_PARAM    = -1,   /* 参数非法 */
	ERR_NOMEM    = -2,   /* 内存不足 */
	ERR_IO       = -3,   /* 设备打开或读写失败 */
	ERR_NOTSUP   = -4,   /* 功能未实现, 或当前平台不支持 */
	ERR_NOTFOUND = -5,   /* 找不到指定对象 */
	ERR_BUSY     = -6,   /* 资源被占用 */
};
```

错误码用匿名 `enum` 而非 `#define`：枚举常量进编译器的符号表，调试器能按名字显示，
`#define` 做不到。约定"负数失败"写在本文件顶部，各层返回它自己的错误码时
不需要再传额外信息——调用方只判断"是不是 `ERR_OK`"，人读日志时才看具体码。
`ERR_BUSY` 在 input 层有专用语义（超时、无数据），与"资源被占用"的字面义偏离，
该层在自己的头文件注释里说明了这个复用。

### 第 17—20 行：两个函数声明

```c
const char *err_str(int err);

// 日志重定向，os_errno 不能为空；成功时为 0，系统调用失败时为 errno
int log_redirect(const char *path, int *os_errno);
```

`os_errno` 是输出参数，注释写明"不能为空"：调用方必须传地址，函数内不替调用方
容忍 `NULL`（见 `common.c` 第 28 行）。项目协议（错误码）与操作系统事实（errno）
分两个通道返回，`main.c` 打日志时两个都打。

### 第 22—48 行：日志宏

```c
//日志级别开关
#ifndef LOG_LEVEL
#define LOG_LEVEL 2
#endif

#define LOG_RAW(tag, fmt, ...) \
	fprintf(stderr, "[%s] %s:%d " fmt "\n", tag, __FILE__, __LINE__, ##__VA_ARGS__) //__VA_ARGS__ 是 GNU 扩展, 作用是零个可变参数时吞掉前面那个逗号

#if LOG_LEVEL >= 1  // 错误级别
#define LOG_ERR(fmt, ...)   LOG_RAW("E", fmt, ##__VA_ARGS__)
#else
#define LOG_ERR(fmt, ...)   do {} while (0)
#endif

#if LOG_LEVEL >= 2  // 信息级别
#define LOG_INFO(fmt, ...)  LOG_RAW("I", fmt, ##__VA_ARGS__)
#else
#define LOG_INFO(fmt, ...)  do {} while (0)
#endif

#if LOG_LEVEL >= 3  // 调试级别
#define LOG_DBG(fmt, ...)   LOG_RAW("D", fmt, ##__VA_ARGS__)
#else
#define LOG_DBG(fmt, ...)   do {} while (0)
#endif

#define ARRAY_SIZE(a)  ((int)(sizeof(a) / sizeof((a)[0])))
```

`##__VA_ARGS__` 解决的是 `LOG_INFO("framework is up")` 这类无参数调用：标准 C 的
变参宏至少要求一个实参占住 `...`，`##` 让前置逗号在变参为空时消失。这是 GNU 扩展，
gcc/clang 都支持，MSVC 不支持——本项目只在 gcc 系工具链上构建。

`do {} while (0)` 让关闭的日志在 `if (x) LOG_INFO(...); else ...` 里仍是单条语句，
宏展开后不吞掉调用者的 `else`。日志在预处理期被替换成空语句，`-DLOG_LEVEL=0`
构建的产物里连格式字符串都不存在（判据 [5] 数到终端输出 0 行），这是编译期裁剪，
发生在编译前而不是运行时。

`LOG_RAW` 固定输出到 `stderr`：stderr 无缓冲，每条日志一次 `write(2)`，13 条日志
正好 13 次 write（判据 [6] 用 strace 数过），`stdout` 有缓冲没有这个性质。
`%s:%d` 打 `__FILE__`/`__LINE__`，定位调用点不用查。

`ARRAY_SIZE` 只用于真正的数组（`main.c` 的 `g_layers`）；数组退化为指针后
`sizeof` 得到指针大小，除法结果是错的，所以它不能用在函数参数上。

## 3. common.c

### 第 1—20 行：错误码翻译

```c
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

#include "common.h"

// 错误码翻译表
const char *err_str(int err)
{
	switch (err) {
	case ERR_OK:       return "ok";
	case ERR_PARAM:    return "invalid parameter";
	case ERR_NOMEM:    return "out of memory";
	case ERR_IO:       return "device io failed";
	case ERR_NOTSUP:   return "not supported";
	case ERR_NOTFOUND: return "not found";
	case ERR_BUSY:     return "busy";
	default:           return "unknown error";
	}
}
```

`default` 分支兜住未定义的错误码，返回值永远可用作 `%s` 参数。函数只做映射，
不做判断；判空之类的策略留在调用方。

### 第 22—51 行：log_redirect

```c
// 日志重定向
int log_redirect(const char *path, int *os_errno)
{
	int fd;
	int saved_errno;

	if (os_errno == NULL)
		return ERR_PARAM;

	*os_errno = 0;
	if (path == NULL || path[0] == '\0')
		return ERR_PARAM;

	fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd < 0) {
		*os_errno = errno;
		return ERR_IO;
	}

	if (dup2(fd, STDERR_FILENO) < 0) {
		// close 也可能改 errno，先保存 dup2 的失败原因
		saved_errno = errno;
		close(fd);
		*os_errno = saved_errno;
		return ERR_IO;
	}

	close(fd);
	return ERR_OK;
}
```

三段意图。`O_APPEND` 让多次运行的日志接着写（判据 [6]：两次运行后文件 26 行），
内核保证每次 `write` 原子地追加到末尾。`dup2(fd, STDERR_FILENO)` 把 fd 2 接到
文件上：之后全项目所有 `fprintf(stderr, ...)` 不改一行就落到文件里；`dup2` 成功
会先关掉原来的 fd 2。最后 `close(fd)` 关掉中间 fd——它已经完成使命，不关就泄漏。

失败路径的资源顺序：open 成功而 dup2 失败时，fd 已占用必须归还；`close()` 本身
可能改写 errno，所以先用 `saved_errno` 保存 dup2 的失败原因再 close，报给调用方的
必须是 dup2 的原因。此处假设 `close` 不覆盖 `saved_errno` 之后再被读取——它先读后
close，顺序保证了这一点。

`*os_errno = 0` 在参数检查之后立即执行：调用方看到的 0 表示"没有系统调用失败"，
项目级拒绝（`ERR_PARAM`）不带系统错误。判据 [6r3] 注错删掉 `*os_errno = errno;`
后，`main.c` 的日志从 `device io failed (No such file or directory)` 退化成
`device io failed`，这条判据见红。

## 4. 执行顺序

```
成功:  判参 → *os_errno=0 → open(成功, fd=3) → dup2(fd,2)(fd2 接文件,
       旧 stderr 被关) → close(3) → ERR_OK
失败1: os_errno==NULL 或 path 空  → ERR_PARAM(不碰 open)
失败2: open 失败                  → *os_errno=errno, ERR_IO(fd 未成功, 无可归还)
失败3: dup2 失败                  → saved_errno=errno → close(3) → ERR_IO
```

每次进程运行至多调用一次，在 `main` 里任何层 init 之前；重复调用没有防护，
也没有需要防护的状态（无全局句柄，fd 3 用完即关）。

## 5. 容易读错的地方

- `##__VA_ARGS__` 里的 `##` 是粘接记号，此处的作用是吞逗号，与字符串拼接无关。
- `LOG_LEVEL=0` 时日志是预处理期消失，不是运行时被静音；产物里没有格式字符串。
- `dup2` 成功后原来的 fd 2（终端）已关闭，回不去了；本函数没有提供恢复路径。
- `close(fd)` 关的是中间 fd（3），fd 2 从此由文件顶替，两者此后无关。
- `errno` 只有在系统调用失败时才有意义；先存再用，任何中间函数调用都可能改写它。

## 6. 消费者清单

- 全部层与单测：`ERR_*`、`LOG_*`、`ARRAY_SIZE`。
- `main.c`：`log_redirect()` 与 `err_str()`（日志落文件的完整报错）。
- 判据：`check_core.sh` [5]（LOG_LEVEL=0 零输出）、[6] 及三条注错
  （O_APPEND、dup2、errno 带出）、`TechReports/project/02` 章。
