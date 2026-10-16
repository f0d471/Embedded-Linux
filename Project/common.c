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
