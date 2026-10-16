/*
 * 真显存后端: open /dev/fb0, 两次 ioctl 问出几何与位段, mmap 拿到显存。
 *
 * 全项目只有这个文件认识 linux/fb.h, 上面几层都只看 struct disp_buf。
 * 位段一律从 var 里抄, 不写死 565 或 8888: 板上插 HDMI 时驱动会自己
 * 把模式从 1024x600x32 改成 1280x720x16, 写死的程序必错其一。
 *
 * 环境变量:
 *     DISP_FB   设备路径, 缺省 /dev/fb0
 */

#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/fb.h>

#include "common.h"
#include "display/disp_manager.h"

static int g_fd = -1;                       /* -1 表示未打开, 0 是合法 fd */
static unsigned char *g_base = MAP_FAILED;  /* mmap 失败返回的是 MAP_FAILED 不是 NULL */
static size_t g_size;

/* 幂等: 每种资源自己判断在不在, 所以 open 的任何一个失败分支都能直接调它 */
static void fb_close(void)
{
	if (g_base != MAP_FAILED) {
		munmap(g_base, g_size);
		g_base = MAP_FAILED;
	}
	if (g_fd >= 0) {
		close(g_fd);
		g_fd = -1;
	}
}

static int fb_open(struct disp_buf *out)
{
	struct fb_var_screeninfo var;
	struct fb_fix_screeninfo fix;
	const char *path = getenv("DISP_FB");

	if (path == NULL)
		path = "/dev/fb0";

	g_fd = open(path, O_RDWR);
	if (g_fd < 0) {
		LOG_ERR("open %s failed", path);
		return ERR_IO;
	}
	if (ioctl(g_fd, FBIOGET_VSCREENINFO, &var) < 0 ||
	    ioctl(g_fd, FBIOGET_FSCREENINFO, &fix) < 0) {
		LOG_ERR("FBIOGET_*SCREENINFO failed");
		fb_close();
		return ERR_IO;
	}

	/* 只映射一屏, 不映射 fix.smem_len: 板上 smem 是 32 MiB 而一屏只要 2.4 MiB,
	   多映射出来的部分会把越界写变成静默写坏, 而不是当场 SIGSEGV */
	g_size = (size_t)fix.line_length * var.yres;
	g_base = mmap(NULL, g_size, PROT_READ | PROT_WRITE, MAP_SHARED, g_fd, 0);
	if (g_base == MAP_FAILED) {
		LOG_ERR("mmap %s failed", path);
		fb_close();
		return ERR_IO;
	}

	out->xres = var.xres;
	out->yres = var.yres;
	out->bpp  = var.bits_per_pixel;
	out->line_length = fix.line_length;
	out->red   = (struct disp_field){ var.red.offset,   var.red.length   };
	out->green = (struct disp_field){ var.green.offset, var.green.length };
	out->blue  = (struct disp_field){ var.blue.offset,  var.blue.length  };
	out->base  = g_base;
	return ERR_OK;
}

/* 单缓冲直接映射, 写进去下一帧就扫到了, 没有要提交的东西 */
static int fb_flush(const struct disp_region *r)
{
	(void)r;
	return ERR_OK;
}

static struct disp_ops g_fb_ops = {
	.name  = "fb",
	.open  = fb_open,
	.close = fb_close,
	.flush = fb_flush,
};

void fb_register(void)
{
	disp_register(&g_fb_ops);
}
