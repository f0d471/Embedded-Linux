#ifndef __COMMON_H
#define __COMMON_H

#include <stdio.h>

/*
 * 全项目公共约定。所有层都 include 这一个头文件, 不允许各层自己发明错误码
 * 和日志格式。
 */

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

/*
 * 把 stderr 整条接到一个文件上, 之后所有 LOG_* 都落进这个文件。
 * 成功返回 ERR_OK, 路径为空返回 ERR_PARAM, 文件打不开返回 ERR_IO。
 *
 * 日志走 stderr 而不是 stdout, 是因为 C 标准规定 stderr 不带缓冲: 每条 fprintf
 * 立刻变成一次 write, 板子掉电时不会丢掉还压在缓冲区里的那几 KB。
 * 为什么用 dup2 而不是给每层加一个"日志句柄"参数, 见
 * notes/01_应用编程/02_文件IO.md 第 6 节。
 */
int log_redirect(const char *path);

/*
 * 日志。级别在编译期决定, 关掉的级别整条语句被预处理器删干净, 不留运行时开销。
 *   make CFLAGS_EXTRA=-DLOG_LEVEL=0    全关
 *   0 全关   1 只留错误   2 错误+信息(默认)   3 加上调试
 *
 * ##__VA_ARGS__ 是 GNU 扩展, 作用是零个可变参数时吞掉前面那个逗号。
 */
#ifndef LOG_LEVEL
#define LOG_LEVEL 2
#endif

#define LOG_RAW(tag, fmt, ...) \
	fprintf(stderr, "[%s] %s:%d " fmt "\n", tag, __FILE__, __LINE__, ##__VA_ARGS__)

#if LOG_LEVEL >= 1
#define LOG_ERR(fmt, ...)   LOG_RAW("E", fmt, ##__VA_ARGS__)
#else
#define LOG_ERR(fmt, ...)   do {} while (0)
#endif

#if LOG_LEVEL >= 2
#define LOG_INFO(fmt, ...)  LOG_RAW("I", fmt, ##__VA_ARGS__)
#else
#define LOG_INFO(fmt, ...)  do {} while (0)
#endif

#if LOG_LEVEL >= 3
#define LOG_DBG(fmt, ...)   LOG_RAW("D", fmt, ##__VA_ARGS__)
#else
#define LOG_DBG(fmt, ...)   do {} while (0)
#endif

#define ARRAY_SIZE(a)  ((int)(sizeof(a) / sizeof((a)[0])))

#endif /* __COMMON_H */
