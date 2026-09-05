#include <fcntl.h>
#include <unistd.h>

#include "common.h"

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

int log_redirect(const char *path)
{
	int fd;

	if (path == NULL || path[0] == '\0')
		return ERR_PARAM;

	/*
	 * O_APPEND 不只是"从末尾开始写"。它让内核在每次 write 之前把写位置移到当前
	 * 文件末尾, 而且"移位置"和"写"合起来是一个原子操作。
	 * 换成 lseek(fd, 0, SEEK_END) 加 write 两步, 两个进程同时写同一个日志时会
	 * 互相覆盖 -- 实测每次丢掉的量还不一样, 见 02 章第 3.2 节。
	 *
	 * 0644 是请求的权限, 不是最终权限: 内核会再和进程的 umask 相与,
	 * umask 022 时落地的是 0644 & ~022 = 0644。
	 */
	fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd < 0)
		return ERR_IO;

	/*
	 * 日志全部走 stderr, 所以只要把 2 号槽换掉, 六层里一行代码都不用改,
	 * 日志格式和级别开关也全都不动。这就是 dup2 存在的理由:
	 * 它改的是 fd 表里那一格指向谁, 不是改调用者。
	 *
	 * dup2 会先把原来的 2 号关掉, 再让 2 号指向 fd 背后的同一个 struct file。
	 */
	if (dup2(fd, STDERR_FILENO) < 0) {
		close(fd);
		return ERR_IO;
	}

	/*
	 * 2 号已经指向那个 struct file 了, fd 这个编号是多余的。
	 * 不关掉的话每跑一次就白占一个编号, /proc/<pid>/fd 里也会多出一条
	 * 指向同一个文件、谁也不用的记录。关掉 fd 不会影响 2 号:
	 * struct file 上有引用计数, 减到 0 才真正关闭。
	 */
	close(fd);
	return ERR_OK;
}
