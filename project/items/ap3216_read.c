/* ap3216_read -- 08 章 I2C 测试项。
 * 通过 i2c-dev(/dev/i2c-N) 直接读 AP3216C 光感/距离/红外传感器:
 * 先写系统配置寄存器 0x00 打开 ALS+PS+IR 三路, 再读 0x0A..0x0F 六个数据
 * 寄存器。整个器件只有 7 位地址 0x1e, 总线号板上不固定, 默认自动探测。
 *
 *   ap3216_read [--bus N] [--loop COUNT INTERVAL_MS]
 *
 * 单次读打印一行; --loop 连读 COUNT 次, 中间隔 INTERVAL_MS 毫秒,
 * 遮光判据靠前后两次的 als 差值。
 */

#include <errno.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "common.h"

#define AP3216_ADDR        0x1e
#define AP3216_REG_SYS_CFG 0x00
#define AP3216_REG_ALS_L   0x0a
#define AP3216_REG_ALS_H   0x0b
#define AP3216_REG_IR_L    0x0c
#define AP3216_REG_IR_H    0x0d
#define AP3216_REG_PS_L    0x0e
#define AP3216_REG_PS_H    0x0f

/* 数据手册给出的换算: 每个计数控 0.35 lux(环境光 16 位模式) */
#define ALS_LUX_PER_COUNT 0.35

static int g_fd = -1;

/* 一次"写寄存器地址 + 读 1 字节"。i2c-dev 的 write/read 就是这么用的:
 * write 把要访问的寄存器号发过去, 紧跟的 read 从那个寄存器搬数据。 */
static int read_reg(unsigned char reg, unsigned char *out)
{
	ssize_t got;

	if (write(g_fd, &reg, 1) != 1)
		return -1;
	do {
		got = read(g_fd, out, 1);
	} while (got < 0 && errno == EINTR);
	return got == 1 ? 0 : -1;
}

static int write_reg(unsigned char reg, unsigned char value)
{
	unsigned char buf[2] = { reg, value };

	return write(g_fd, buf, 2) == 2 ? 0 : -1;
}

/* 总线号不写死: 逐个 open + I2C_SLAVE + 读一次配置寄存器, 谁应答用谁。
 * read_reg/write_reg 只认 g_fd, 所以探测前就要把候选 fd 挂上去;
 * 探测失败先摘下来再 close, 否则下一个总线的探测会写到一个已关闭的 fd。 */
static int open_sensor(int forced_bus, int *real_bus)
{
	char path[32];
	unsigned char cfg;
	int bus, fd;

	for (bus = (forced_bus >= 0 ? forced_bus : 0);
	     bus <= (forced_bus >= 0 ? forced_bus : 8); bus++) {
		snprintf(path, sizeof(path), "/dev/i2c-%d", bus);
		fd = open(path, O_RDWR);
		if (fd < 0)
			continue;
		g_fd = fd;
		if (ioctl(fd, I2C_SLAVE, AP3216_ADDR) < 0 ||
		    read_reg(AP3216_REG_SYS_CFG, &cfg) < 0) {
			g_fd = -1;
			close(fd);
			continue;
		}
		*real_bus = bus;
		return 0;
	}
	return -1;
}

static int read_once(int bus)
{
	unsigned char als_l, als_h, ir_l, ir_h, ps_l, ps_h;
	unsigned als, ir, ps;

	if (write_reg(AP3216_REG_SYS_CFG, 0x03) < 0) {
		fprintf(stderr, "ap3216: write cfg: %s\n", strerror(errno));
		return 1;
	}
	/* 三路转换最长大约 100ms, 写完立刻读会把上一轮的旧值读出来 */
	usleep(200 * 1000);

	if (read_reg(AP3216_REG_ALS_L, &als_l) < 0 ||
	    read_reg(AP3216_REG_ALS_H, &als_h) < 0 ||
	    read_reg(AP3216_REG_IR_L, &ir_l) < 0 ||
	    read_reg(AP3216_REG_IR_H, &ir_h) < 0 ||
	    read_reg(AP3216_REG_PS_L, &ps_l) < 0 ||
	    read_reg(AP3216_REG_PS_H, &ps_h) < 0) {
		fprintf(stderr, "ap3216: read data: %s\n", strerror(errno));
		return 1;
	}
	als = (als_h << 8) | als_l;
	ir = (ir_h << 8) | ir_l;
	ps = ((ps_h & 0x3f) << 4) | (ps_l & 0x0f);
	printf("ap3216 bus=%d addr=0x%02x als=%u ir=%u ps=%u lux=%.1f\n",
	       bus, AP3216_ADDR, als, ir, ps, als * ALS_LUX_PER_COUNT);
	return 0;
}

int main(int argc, char **argv)
{
	int bus = -1, real_bus = -1;
	int loop = 1, interval_ms = 500, i, bad = 0;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--bus") == 0 && i + 1 < argc)
			bus = atoi(argv[++i]);
		else if (strcmp(argv[i], "--loop") == 0 && i + 2 < argc) {
			loop = atoi(argv[++i]);
			interval_ms = atoi(argv[++i]);
		}
	}

	if (open_sensor(bus, &real_bus) < 0) {
		fprintf(stderr, "ap3216: no sensor at 0x%02x on /dev/i2c-*\n",
			AP3216_ADDR);
		return 1;
	}
	for (i = 0; i < loop; i++) {
		if (i > 0)
			usleep((useconds_t)interval_ms * 1000);
		if (read_once(real_bus) != 0)
			bad++;
	}
	close(g_fd);
	return bad != 0;
}
