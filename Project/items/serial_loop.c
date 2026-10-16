/* serial_loop -- 09 章串口测试项。
 * termios 配置 115200-8-N-1 raw 模式, 发 N 帧自带校验和的 PING 帧,
 * 逐帧等对端原样回显并核对。对端可以是一根跳线(自发自收),
 * 也可以是判据脚本里的伪终端回显器。
 *
 *   serial_loop <device> [--count N] [--probe]
 *
 * --probe 只 open + tcgetattr/tcsetattr + close, 不发数据,
 * 用于板上验证串口设备在、termios 调得动, 不干扰控制台。
 * 帧格式: "PING <序号4位16进制> <校验和2位16进制>\n",
 * 校验和 = 除校验和与其前导空格之外全部字节的异或, 即帧的前 10 字节。
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include "common.h"

#define FRAME_LEN 13     /* "PING xxxx yy\n" = 5+4+1+2+1 */

static int configure(int fd)
{
	struct termios tio;

	if (tcgetattr(fd, &tio) != 0)
		return -1;
	cfmakeraw(&tio);
	cfsetispeed(&tio, B115200);
	cfsetospeed(&tio, B115200);
	tio.c_cflag |= CLOCAL | CREAD;   /* 忽略调制解调器线, 打开接收 */
	tio.c_cc[VMIN] = 0;              /* read 不等满缓冲 */
	tio.c_cc[VTIME] = 10;            /* 1 秒内没数据就返回 */
	return tcsetattr(fd, TCSANOW, &tio);
}

/* 填一帧, 返回总长(恒为 FRAME_LEN)。校验和覆盖前面 10 个字节。 */
static int frame_build(int seq, char *out)
{
	unsigned char sum = 0;
	int n, i;

	n = sprintf(out, "PING %04x ", seq & 0xffff);
	for (i = 0; i < n; i++)
		sum ^= (unsigned char)out[i];
	n += sprintf(out + n, "%02x\n", sum);
	return n;
}

static int frame_check(const char *frame, int len)
{
	unsigned int got = 0;
	unsigned char sum = 0;
	int i;

	if (len != FRAME_LEN || strncmp(frame, "PING ", 5) != 0)
		return 0;
	for (i = 0; i < len - 3; i++)
		sum ^= (unsigned char)frame[i];
	if (sscanf(frame + len - 3, "%2x", &got) != 1)
		return 0;
	return sum == (unsigned char)got;
}

int main(int argc, char **argv)
{
	const char *device;
	int count = 5, probe = 0, fd, i, ok = 0;
	char sent[FRAME_LEN + 1], recv[FRAME_LEN + 1];

	if (argc < 2) {
		fprintf(stderr, "usage: %s <device> [--count N] [--probe]\n",
			argv[0]);
		return 2;
	}
	device = argv[1];
	for (i = 2; i < argc; i++) {
		if (strcmp(argv[i], "--count") == 0 && i + 1 < argc)
			count = atoi(argv[++i]);
		else if (strcmp(argv[i], "--probe") == 0)
			probe = 1;
	}

	fd = open(device, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) {
		fprintf(stderr, "serial: open %s: %s\n", device,
			strerror(errno));
		return 1;
	}
	if (configure(fd) != 0) {
		fprintf(stderr, "serial: termios %s: %s\n", device,
			strerror(errno));
		close(fd);
		return 1;
	}
	/* 非阻塞打开是为了 open 永不卡住(有的驱动要等载波);
	 * 配置完再把 O_NONBLOCK 摘掉, read 的 VTIME 超时只在阻塞模式下生效 */
	fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);

	if (probe) {
		struct termios tio;

		printf("serial probe %s: termios ok\n", device);
		if (tcgetattr(fd, &tio) == 0)
			printf("serial probe baud=%d\n",
			       cfgetispeed(&tio) == B115200 ? 115200 : 0);
		close(fd);
		return 0;
	}

	for (i = 0; i < count; i++) {
		int total = 0;

		frame_build(i, sent);
		if (write(fd, sent, FRAME_LEN) != FRAME_LEN) {
			fprintf(stderr, "serial: write: %s\n", strerror(errno));
			close(fd);
			return 1;
		}
		tcdrain(fd);
		while (total < FRAME_LEN) {
			ssize_t n = read(fd, recv + total,
					 (size_t)(FRAME_LEN - total));
			if (n > 0) {
				total += (int)n;
				continue;
			}
			if (n < 0 && errno == EINTR)
				continue;
			break;    /* VTIME 到了还没读满 */
		}
		recv[total < FRAME_LEN ? total : FRAME_LEN] = '\0';
		if (total == FRAME_LEN && memcmp(sent, recv, FRAME_LEN) == 0 &&
		    frame_check(recv, total)) {
			ok++;
			printf("frame %d echo ok: %s", i, recv);
		} else {
			printf("frame %d mismatch: sent %s  got %s\n",
			       i, sent, recv);
		}
	}

	close(fd);
	printf("serial ok=%d/%d\n", ok, count);
	return ok == count ? 0 : 1;
}
