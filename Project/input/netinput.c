#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "common.h"
#include "input/input_internal.h"

/*
 * netinput: 把 TCP 对端发来的输入事件记录喂给 input 层, 当第二个输入源。
 *
 * 线上格式是 20 字节定长小端记录, 内容与 evdev 的 struct input_event 同构
 * (type/code/value + 时间戳)。TCP 是字节流没有边界, 定长 + magic 让收端
 * 只靠字节数就能重新对齐; 校验不过的客户端整条连接丢弃, 服务继续等下一个。
 *
 *   offset  size  field
 *   0       2     magic  = 0x6e49, 线上字节 49 6e ("In")
 *   2       2     type   (EV_SYN / EV_KEY / EV_REL / EV_ABS)
 *   4       2     code
 *   6       2     pad    (对齐用, 收端不检查)
 *   8       4     value
 *   12      4     sec
 *   16      4     usec
 *
 * x86 和 ARM 都是小端, 记录按字节原样收发, 不做字节序转换;
 * 协议里显式写死这一点, 大端机器接入前要先改这里。
 */

#define NETINPUT_MAGIC      0x6e49
#define NETINPUT_DEFAULT_PORT 23232

struct netinput_record {
	uint16_t magic;
	uint16_t type;
	uint16_t code;
	uint16_t pad;
	int32_t  value;
	int32_t  sec;
	int32_t  usec;
} __attribute__((packed));

_Static_assert(sizeof(struct netinput_record) == 20,
	       "netinput wire record must stay 20 bytes");

static int g_listen = -1;
static int g_client = -1;
static struct netinput_record g_rec;
static size_t g_have;

static int set_nonblock(int fd)
{
	int flags = fcntl(fd, F_GETFL, 0);

	if (flags < 0)
		return -1;
	return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static int netinput_open(struct input_source_info *out)
{
	struct sockaddr_in addr;
	const char *port_str;
	long port;
	int fd;

	port_str = getenv("NETINPUT_PORT");
	port = port_str != NULL ? strtol(port_str, NULL, 10)
				: NETINPUT_DEFAULT_PORT;
	if (port <= 0 || port > 65535)
		return ERR_PARAM;

	fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0)
		return ERR_IO;
	if (set_nonblock(fd) < 0) {
		close(fd);
		return ERR_IO;
	}

	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_ANY);
	addr.sin_port = htons((uint16_t)port);
	/* SO_REUSEADDR: TIME_WAIT 里也能立刻重绑, 判据要连跑好几轮 */
	int one = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    listen(fd, 4) < 0) {
		close(fd);
		return ERR_IO;
	}

	g_listen = fd;
	g_client = -1;
	g_have = 0;

	memset(out, 0, sizeof(*out));
	snprintf(out->name, sizeof(out->name), "netinput");
	snprintf(out->path, sizeof(out->path), "tcp:0.0.0.0:%ld", port);
	out->has_relative = 1;
	out->has_absolute = 1;
	out->has_keys = 1;
	out->abs_x_min = 0;
	out->abs_x_max = 4095;
	out->abs_y_min = 0;
	out->abs_y_max = 4095;
	return ERR_OK;
}

static void netinput_drop_client(void)
{
	if (g_client >= 0) {
		close(g_client);
		g_client = -1;
	}
	g_have = 0;
}

static void netinput_close(void)
{
	netinput_drop_client();
	if (g_listen >= 0) {
		close(g_listen);
		g_listen = -1;
	}
}

static int netinput_get_fds(int *fds, int max)
{
	int n = 0;

	if (max < 1)
		return ERR_PARAM;
	fds[n++] = g_listen;
	if (g_client >= 0 && n < max)
		fds[n++] = g_client;
	return n;
}

/* 校验不过的记录说明对端不是本协议的客户端, 整条连接丢弃。 */
static int record_valid(const struct netinput_record *rec)
{
	if (rec->magic != NETINPUT_MAGIC)
		return 0;
	if (rec->type > EV_MAX || rec->code > KEY_MAX)
		return 0;
	if (rec->usec < 0 || rec->usec >= 1000000)
		return 0;
	return 1;
}

static int netinput_read_raw(struct input_raw_event *out)
{
	ssize_t got;

	if (out == NULL || g_listen < 0)
		return ERR_PARAM;

	/* 还没有客户端: 监听 fd 可读才走到这里, accept 一个进来。
	 * 本轮不产事件, 让下一轮 poll 把客户端 fd 也挂进监听集。 */
	if (g_client < 0) {
		g_client = accept(g_listen, NULL, NULL);
		if (g_client < 0)
			return ERR_BUSY;
		if (set_nonblock(g_client) < 0) {
			netinput_drop_client();
			return ERR_BUSY;
		}
		g_have = 0;
		return ERR_BUSY;
	}

	/* 攒够一整条记录为止; 半条留在 g_rec 里等下一轮。 */
	while (g_have < sizeof(g_rec)) {
		got = read(g_client, (char *)&g_rec + g_have,
			   sizeof(g_rec) - g_have);
		if (got > 0) {
			g_have += (size_t)got;
			continue;
		}
		if (got < 0 && errno == EINTR)
			continue;
		if (got < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
			return ERR_BUSY;
		/* EAGAIN = 这批数据读完了, 半条记录等下一轮接着攒;
		 * EOF/复位/错误 = 对端没了。 */
		netinput_drop_client();
		/* 客户端没了只影响这一条连接, 服务继续等下一个客户端 */
		return ERR_BUSY;
	}

	g_have = 0;
	if (!record_valid(&g_rec)) {
		netinput_drop_client();
		return ERR_BUSY;
	}
	out->sec = g_rec.sec;
	out->usec = g_rec.usec;
	out->type = g_rec.type;
	out->code = g_rec.code;
	out->value = g_rec.value;
	return ERR_OK;
}

static struct input_provider g_netinput = {
	.name = "netinput",
	.open = netinput_open,
	.close = netinput_close,
	.get_fds = netinput_get_fds,
	.read_raw = netinput_read_raw,
};

void netinput_register(void)
{
	input_register(&g_netinput);
}
