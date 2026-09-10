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

// 日志重定向
int log_redirect(const char *path)
{
	int fd;  // 刚打开的日志文件

	// 没有提供文件路径时无法开启文件日志，报告参数错误
	if (path == NULL || path[0] == '\0')
		return ERR_PARAM;

	//打开 path 指定的文件；文件不存在就创建，存在就追加写入
	fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);  //0644 是文件权限，表示文件拥有者可读写，其他人只读
	if (fd < 0)
		return ERR_IO;

	// 将 stderr 重定向到 fd
	if (dup2(fd, STDERR_FILENO) < 0) {
		close(fd);
		return ERR_IO;
	}

	// 关闭 fd
	close(fd);
	return ERR_OK;
}
