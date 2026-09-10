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

const char *err_str(int err);

// 日志重定向
int log_redirect(const char *path);

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

#endif /* __COMMON_H */
