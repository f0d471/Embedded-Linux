/*
 * 假显存后端: 用一块 malloc 出来的内存冒充 framebuffer。
 *
 * 存在的理由有两个: WSL 上没有 /dev/fb0, 本后端让整条链路在电脑上跑通;
 * 以及它的行宽故意大于一行像素占的字节数, 能暴露"把行宽当成
 * 宽 x 每像素字节数"这类在真板子上看不出来的错误。
 *
 * 环境变量:
 *     DISP_MEM        宽x高x位深x行宽, 缺省 64x32x32x320
 *     DISP_MEM_DUMP   关闭时把整块内存原样写入该路径
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"

static unsigned char *g_mem;   /* 假显存首地址, NULL 表示未打开 */
static size_t g_size;          /* 假显存总字节数 */

static int mem_open(struct disp_buf *out)
{
	const char *spec = getenv("DISP_MEM");
	int w = 64, h = 32, bpp = 32, ll = 320;
	int y;

	if (spec != NULL && sscanf(spec, "%dx%dx%dx%d", &w, &h, &bpp, &ll) != 4) {
		LOG_ERR("bad DISP_MEM: %s", spec);
		return ERR_PARAM;
	}

	if (w <= 0 || h <= 0 || (bpp != 16 && bpp != 32) || ll < w * bpp / 8) {
		LOG_ERR("bad geometry %dx%dx%d ll %d", w, h, bpp, ll);
		return ERR_PARAM;
	}

	g_size = (size_t)ll * h;
	g_mem = malloc(g_size);
	if (g_mem == NULL)
		return ERR_NOMEM;

	/* 像素区刷黑, 行尾填充区填 0xAA 当哨兵: 谁写出界, 谁就会把它冲掉 */
	for (y = 0; y < h; y++) {
		memset(g_mem + y * ll, 0x00, w * bpp / 8);
		memset(g_mem + y * ll + w * bpp / 8, 0xAA, ll - w * bpp / 8);
	}

	out->xres = w;
	out->yres = h;
	out->bpp = bpp;
	out->line_length = ll;
	out->base = g_mem;

	if (bpp == 32) {
		/* xRGB8888: 最高 8 位不用 */
		out->red.offset = 16;   out->red.length = 8;
		out->green.offset = 8;  out->green.length = 8;
		out->blue.offset = 0;   out->blue.length = 8;
	} else {
		/* RGB565: 绿色多一位 */
		out->red.offset = 11;   out->red.length = 5;
		out->green.offset = 5;  out->green.length = 6;
		out->blue.offset = 0;   out->blue.length = 5;
	}

	return ERR_OK;
}

static void mem_close(void)
{
	const char *dump;
	FILE *fp;

	if (g_mem == NULL)
		return;

	/* 只倒原始字节, 统计交给外部脚本: 自己数自己画的东西, 判据永远 PASS */
	dump = getenv("DISP_MEM_DUMP");
	if (dump != NULL) {
		fp = fopen(dump, "wb");
		if (fp != NULL) {
			fwrite(g_mem, 1, g_size, fp);
			fclose(fp);
		} else {
			LOG_ERR("cannot open dump file %s", dump);
		}
	}

	free(g_mem);
	g_mem = NULL;
	g_size = 0;
}

static int mem_flush(const struct disp_region *r)
{
	(void)r;
	return ERR_OK;
}

static struct disp_ops g_mem_ops = {
	.name = "mem",
	.open = mem_open,
	.close = mem_close,
	.flush = mem_flush,
};

void memdisp_register(void)
{
	disp_register(&g_mem_ops);
}
