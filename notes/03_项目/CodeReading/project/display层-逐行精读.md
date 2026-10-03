# display 层逐行精读

对应代码：`project/display/disp_manager.h`（46 行）、`disp_manager.c`（195 行）、
`memdisp.c`（112 行）、`framebuffer.c`（98 行）。

## 1. 文件定位

对上提供画布信息与画点/混色/填矩形，对下按名字选一个后端。两个后端：
`framebuffer.c` 开真设备（全项目唯一认识 `linux/fb.h` 的文件），`memdisp.c` 用
malloc 内存冒充显存（WSL 可跑、行尾带哨兵）。上游是 font 层的
`disp_blend_pixel()`、单测 `disp_test` 与未来的 ui/page。

前置知识：[从零开始读写 project 代码](../00-从零开始读写项目代码.md)第 5 节
（函数指针与链表）、第 6 节（位运算与颜色）；第 03 章笔记（Framebuffer）。

```
font / ui / disp_test          font / ui / disp_test
        │ disp_put_pixel              │ disp_blend_pixel
        ▼                             ▼
┌──────────────────────── disp_manager.c ────────────────────────┐
│  pack_field(位段拼色)   unpack_field(位段展开)   fill_rect 裁剪 │
└───────┬────────────────────────────────────────┬───────────────┘
        │ g_cur->open/close/flush                 │
   framebuffer.c(/dev/fb0, ioctl+mmap)      memdisp.c(malloc, 0xAA 哨兵)
```

## 2. disp_manager.h

### 第 1—8 行：guard 与位段

```c
#ifndef __DISP_MANAGER_H
#define __DISP_MANAGER_H

/* 一个颜色分量在像素里的位置: 从第 offset 位起, 占 length 位 */
struct disp_field {
	int offset;
	int length;
};
```

`disp_field` 是像素格式的事实来源。板上插 HDMI 时驱动把模式从 xRGB8888 切成
RGB565，位段随模式变化，所以任何代码都不得写死"红在 16..23 位"，一律从
`disp_buf` 现场读。

### 第 10—23 行：画布与矩形

```c
/* 后端交给 manager 的"一块能画的内存"。上层只读 */
struct disp_buf {
	int  xres;
	int  yres;
	int  bpp;
	int  line_length;          /* 一行的字节数, 不一定等于 xres * bpp / 8 */
	struct disp_field red, green, blue;
	unsigned char *base;
};

/* 一块矩形区域, 左闭右开: 覆盖 x <= X < x + w */
struct disp_region {
	int x, y, w, h;
};
```

`line_length` 单独存在的理由：板上 1280x720x16 时它是 2560 = 1280x2，1024x600x32
时是 4096 = 1024x4，两者相等；但假显存故意配成 64x32x32x320（一行只需 256 字节，
给 320），行尾 64 字节是哨兵区——把行宽算成 `xres * bpp / 8` 的错误只在有填充的
显存上暴露（判据 [7r1]/[7r2] 专门对照了这一点）。`base` 注释"上层只读"：
真显存是 mmap 的共享映射，越界写会写坏别人的内存。

矩形是左闭右开约定：`x <= X < x+w`。后面 `fill_rect` 的裁剪与 `disp_test` 的
图案设计都用这个约定。

### 第 25—32 行：后端接口

```c
/* 一个显示后端。每个后端定义一份, 在自己的 xxx_register 里挂进链表 */
struct disp_ops {
	const char *name;
	int  (*open)(struct disp_buf *out);
	void (*close)(void);
	int  (*flush)(const struct disp_region *r);
	struct disp_ops *next;
};
```

五个成员就是后端要回答的全部问题：叫什么、把画布交出来、归还、提交区域、
链上下一个。`open` 的参数是出参（调用方提供 `disp_buf` 存储），与
`font_bitmap` 的借用不同——`disp_buf` 的字段是后端抄进去的值，`base` 指向的
内存生命周期由后端管，`close` 之后失效。

### 第 34—46 行：对外函数

```c
void disp_register(struct disp_ops *ops);

int  display_init(void);
void display_exit(void);

/* 上层接口。颜色一律是 0x00RRGGBB, 拼成什么像素值由本层决定 */
const struct disp_buf *disp_get_buf(void);
int  disp_put_pixel(int x, int y, unsigned int rgb);
int  disp_blend_pixel(int x, int y, unsigned int rgb, unsigned char alpha);
int  disp_fill_rect(const struct disp_region *r, unsigned int rgb);
int  disp_flush(const struct disp_region *r);

#endif /* __DISP_MANAGER_H */
```

颜色契约写在注释里：上层永远给 8 位分量的 `0x00RRGGBB`，位段拼色由本层按
`g_buf` 现场做。`disp_blend_pixel` 是 04 章为灰度字形加的入口，多一个
`alpha` 参数；其余四个是骨架期就定下的。

## 3. disp_manager.c

### 第 1—19 行：说明与全局

```c
/*
 * display 层管理器。对上提供画布信息和画点/混色/填矩形, 对下按名字选一个后端。
 *
 * 后端选择来自环境变量 DISP_DEV, 缺省 fb。缺省不做"fb 打不开就退回 mem"的回退,
 * 否则板上出问题时程序会静默画进一块没人看的内存。
 */

#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"

extern void fb_register(void);
extern void memdisp_register(void);

static struct disp_ops *g_list;   /* 所有注册过的后端 */
static struct disp_ops *g_cur;    /* 当前选中的后端, NULL 表示未启动 */
static struct disp_buf  g_buf;    /* 当前后端交出来的画布 */
```

头部注释记录了一个设计决定：init 失败就失败，不做静默回退。板上 fb 打不开时
程序当场退出，问题在上板那一刻暴露；静默回退会把故障推迟到"画了但没人看见"。
`extern` 声明避免为两个 register 函数单独开头文件——它们只在这一处被调。

### 第 21—35 行：注册与查找

```c
void disp_register(struct disp_ops *ops)
{
	ops->next = g_list;
	g_list = ops;
}

static struct disp_ops *disp_find(const char *name)
{
	struct disp_ops *p;

	for (p = g_list; p != NULL; p = p->next)
		if (strcmp(p->name, name) == 0)
			return p;
	return NULL;
}
```

头插注册：新节点的 `next` 指向旧链头，再改链头。两步顺序不能换，否则丢掉旧链。
`disp_register` 不判 `NULL`——display 层的两个调用点都是本目录的静态对象，
前提由 `display_init` 固定的注册顺序保证；font 层的同名函数判了 `NULL`，
因为它的 provider 还会被单测注册（见 font 篇）。两处差异是各自上游的实际约定，
不是疏忽。

### 第 37—68 行：display_init

```c
int display_init(void)
{
	const char *name;
	int ret;

	if (g_cur != NULL)
		return ERR_OK;

	/* 每轮重建链表。少了这一行, 第二轮注册会让节点的 next 指向自己, disp_find 死循环 */
	g_list = NULL;
	fb_register();
	memdisp_register();

	name = getenv("DISP_DEV");
	if (name == NULL)
		name = "fb";

	g_cur = disp_find(name);
	if (g_cur == NULL) {
		LOG_ERR("no display backend named %s", name);
		return ERR_NOTFOUND;
	}

	ret = g_cur->open(&g_buf);
	if (ret != ERR_OK) {
		g_cur = NULL;
		return ret;
	}

	LOG_INFO("display init OK");
	return ERR_OK;
}
```

第 46 行 `g_list = NULL` 是踩过坑的补丁：后端是静态对象，init/exit/init 两轮时
`memdisp_register` 会在已经是链尾的节点上再做一次头插，`ops->next` 指向自己，
`disp_find` 沿链死循环。exit 里没有清 `g_list`（见第 70—80 行），清链的职责
放在 init 开头，"每轮重建"的语义只写一处。

选后端失败（`ERR_NOTFOUND`）与 open 失败（透传后端错误码）分开报：
前者是配置错，后者是设备错，板上排查时第一步就是分辨这两条日志。

### 第 70—87 行：exit 与 get_buf

```c
void display_exit(void)
{
	if (g_cur == NULL)
		return;

	g_cur->close();
	memset(&g_buf, 0, sizeof(g_buf));
	g_cur = NULL;

	LOG_INFO("display exit OK");
}

const struct disp_buf *disp_get_buf(void)
{
	if (g_cur == NULL)
		return NULL;
	return &g_buf;
}
```

exit 幂等：未启动直接返回，调用方（`layers_exit` 回滚路径）不需要问"启动过吗"。
`memset` 清画布描述，防止 exit 后 `disp_get_buf` 返回残留几何——虽然 `g_cur==NULL`
已经让它返回 NULL，双保险的成本是一次 32 字节清零。

### 第 89—102 行：位段拼色与展开

```c
/* 把一个 8 位分量缩到 length 位再挪到 offset 位。length 为 8 时 c8 原样返回 */
static unsigned int pack_field(unsigned int c8, const struct disp_field *f)
{
	return (c8 >> (8 - f->length)) << f->offset;
}

/* 把 framebuffer 位段展开回 0..255，供 alpha 混色读取背景。 */
static unsigned int unpack_field(unsigned int pixel, const struct disp_field *f)
{
	unsigned int mask = (1u << f->length) - 1;
	unsigned int value = (pixel >> f->offset) & mask;

	return (value * 255u + mask / 2) / mask;
}
```

`pack_field` 右移丢弃低位（高位对齐），RGB565 红 5 位时 `0xff >> 3 = 0x1f`。
`length==8` 时 `8-8=0`，移位为零次，原样返回——32 位格式不需要特判。

`unpack_field` 的 `(value * 255 + mask/2) / mask` 是把 `length` 位数值等比放大回
8 位的四舍五入：5 位最大值 31 → `(31*255+15)/31 = 255`，两端对齐。混色的背景
读数必须经过这一步，否则 5 位背景直接当 8 位用，半透明结果整体偏暗。

`mask = (1u << f->length) - 1` 用 `1u`：`length` 为 32 时 `1 << 32` 是未定义行为，
`unsigned` 至少保证 31 位内安全；本项目位段最长 8 位，这里是写法上的设防。

### 第 104—131 行：disp_put_pixel

```c
int disp_put_pixel(int x, int y, unsigned int rgb)
{
	unsigned char *p;
	unsigned int v;

	if (g_cur == NULL)
		return ERR_PARAM;
	if (x < 0 || y < 0 || x >= g_buf.xres || y >= g_buf.yres)
		return ERR_PARAM;

	v = pack_field((rgb >> 16) & 0xff, &g_buf.red)
	  | pack_field((rgb >> 8) & 0xff, &g_buf.green)
	  | pack_field(rgb & 0xff, &g_buf.blue);

	/* 行宽用 line_length, 不是 xres * bpp / 8: 两者只在行尾有填充时才不同 */
	p = g_buf.base + y * g_buf.line_length + x * (g_buf.bpp / 8);
	switch (g_buf.bpp) {
	case 16:
		*(unsigned short *)p = v;
		break;
	case 32:
		*(unsigned int *)p = v;
		break;
	default:
		return ERR_NOTSUP;
	}
	return ERR_OK;
}
```

地址公式 `base + y * line_length + x * bpp/8` 是本层最核心的一行：行距用
`line_length`（字节），列距用每像素字节数，两个独立的量。判据 [7r1] 把它注错成
`y * (xres * bpp / 8)`，行尾有填充的假显存上像素分布立刻错位；[7r2] 再证明同一个
错误在无填充的 64x32x32x256 上看不出来——这就是假显存故意配 320 行宽的理由。

16/32 位各一次直接写；对齐由后端保证（fb 的 mmap 基址页对齐、memdisp 是
malloc 结果），`x * bpp/8` 恒为偶数，`unsigned short` 写入不会踩到未对齐地址。
其它位深显式拒绝，不猜。

### 第 133—166 行：disp_blend_pixel（04 章新增）

```c
int disp_blend_pixel(int x, int y, unsigned int rgb, unsigned char alpha)
{
	unsigned char *p;
	unsigned int old, br, bg, bb, fr, fg, fb, mixed;

	if (g_cur == NULL)
		return ERR_PARAM;
	if (x < 0 || y < 0 || x >= g_buf.xres || y >= g_buf.yres)
		return ERR_PARAM;
	if (alpha == 0)
		return ERR_OK;
	if (alpha == 255)
		return disp_put_pixel(x, y, rgb);

	p = g_buf.base + y * g_buf.line_length + x * (g_buf.bpp / 8);
	if (g_buf.bpp == 16)
		old = *(unsigned short *)p;
	else if (g_buf.bpp == 32)
		old = *(unsigned int *)p;
	else
		return ERR_NOTSUP;

	br = unpack_field(old, &g_buf.red);
	bg = unpack_field(old, &g_buf.green);
	bb = unpack_field(old, &g_buf.blue);
	fr = (rgb >> 16) & 0xff;
	fg = (rgb >> 8) & 0xff;
	fb = rgb & 0xff;
	fr = (fr * alpha + br * (255 - alpha) + 127) / 255;
	fg = (fg * alpha + bg * (255 - alpha) + 127) / 255;
	fb = (fb * alpha + bb * (255 - alpha) + 127) / 255;
	mixed = (fr << 16) | (fg << 8) | fb;
	return disp_put_pixel(x, y, mixed);
}
```

两个边界分支各有语义：`alpha==0` 完全透明，直接返回，省一次读显存；
`alpha==255` 完全不透明，等价于画点，转调 `disp_put_pixel` 复用它的位段与
越界逻辑。中间值才走"读背景 → 展开 → 混合 → 经 `0x00RRGGBB` 写回"的完整链，
写回时 `pack_field` 再把分量压回真实位段。

混合式 `+ 127) / 255` 是四舍五入的整数写法（`/255` 换成 `>>8` 时加 128，
这里直接除以 255 配 127 偏置）。手算例：背景 `0x204060`、前景 `0xe0a020`、
alpha=64 的红通道 `(224×64 + 32×191 + 127)/255 = 80`，判据 [11] 的探针
第二个像素 `00505850` 即此值。前提：`alpha` 在 0..255 内，`unsigned char`
保证了这一点；背景像素值不超过位段范围，由写入口保证。

### 第 168—195 行：fill_rect 与 flush

```c
/*
 * 裁剪后逐点画。put_pixel 自己也挡越界, 所以裁剪在功能上是冗余的,
 * 留着是为了不白跑屏外的点, 也为了将来 fill_rect 直接写内存时仍有一道边界。
 */
int disp_fill_rect(const struct disp_region *r, unsigned int rgb)
{
	int x0, y0, x1, y1, x, y;

	if (g_cur == NULL || r == NULL)
		return ERR_PARAM;

	x0 = r->x < 0 ? 0 : r->x;
	y0 = r->y < 0 ? 0 : r->y;
	x1 = r->x + r->w > g_buf.xres ? g_buf.xres : r->x + r->w;
	y1 = r->y + r->h > g_buf.yres ? g_buf.yres : r->y + r->h;

	for (y = y0; y < y1; y++)
		for (x = x0; x < x1; x++)
			disp_put_pixel(x, y, rgb);
	return ERR_OK;
}

int disp_flush(const struct disp_region *r)
{
	if (g_cur == NULL)
		return ERR_PARAM;
	return g_cur->flush(r);
}
```

注释回答了"有了 put_pixel 的边界检查，为什么这里还要裁剪"：省掉屏外点的函数
调用，并且未来改为整块 memcpy 时仍有一道边界。判据 [7r6] 注错删掉右边界裁剪，
输出分布不变（证明冗余边界确实兜住了），这条判据钉住的是"以后改写法时不能
没有它"。

`disp_flush` 只透传。单缓冲模型下两个后端的 flush 都是空的（写进去下一场就
扫出来了），接口留给以后的双缓冲/脏矩形。

## 4. memdisp.c

### 第 1—21 行：存在理由与全局

```c
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
```

### 第 23—69 行：mem_open

```c
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
```

哨兵是本后端的核心设计：像素区黑、填充区 `0xAA`，任何越界写都会把 `0xAA`
冲掉，独立计数脚本（count.sh/count.py）数填充区还剩几个 `0xAA` 就能抓住
越界（判据 [11] 的 `pad_AA 2048`）。几何校验里 `ll < w * bpp / 8` 拒绝
比像素区还窄的行宽——那不是"有填充的显存"，是不一致的参数。

位段这里写死两种，与 fb 后端"从 var 抄"形成对照：假显存自己就是位段定义者，
抄无可抄。

### 第 71—112 行：close、flush、注册

```c
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
```

第 79 行注释是判据体系的原则：被测程序只交原始字节，计数由
`unittest/count.sh`、`count.py` 两份互不共享代码的实现独立算
（判据 [7] 还有两条实现互校）。判据写进被测对象，它就永远不会红。
`(void)r` 显式吞掉未用参数，配合 `-Wextra -Werror`。

## 5. framebuffer.c

### 第 1—24 行：说明与全局

```c
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
```

两个初值都是纠错写法：fd 0 是合法描述符（stdin），"未打开"必须用 -1 表示；
mmap 失败返回 `MAP_FAILED`，用 `NULL` 判断会把它当成功。

### 第 26—37 行：fb_close

```c
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
```

每种资源自带"在不在"判断与状态复位，open 的任何失败分支直接 `fb_close()`
不会有二次释放。这是本仓资源清理的固定形状，font 层的 `freetype_close` 同型。

### 第 39—79 行：fb_open

```c
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
```

`var`（可变参数：分辨率、位深、位段）与 `fix`（固定参数：行宽、显存总量）
分两次 ioctl 问，各管各的。只映射一屏是刻意的：`smem_len` 有 32 MiB，
越界写多映射的部分不报错只写坏；映射一屏时越界写当场 `SIGSEGV`，错误在
第一现场暴露。判据 [8] 用 `/dev/null`（能 open，ioctl 必 ENOTTY）钉住
"open 成功、ioctl 失败"这个中间态的系统调用序列 `openat ioctl close`。

位段四行从 `var` 现抄，板上实测 1024x600x32 与 1280x720x16 两种模式都靠
这一段自适应，`disp_put_pixel` 不需要知道模式存在。

### 第 81—98 行：flush 与注册

```c
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
```

## 6. 执行顺序

```
成功:  display_init → 重建链表 → fb_register + memdisp_register
       → DISP_DEV 选后端 → open 问几何/位段/拿内存 → g_buf 就绪
       → put_pixel / blend_pixel / fill_rect 任意次 → flush(空)
       → display_exit → close 归还 fd 与映射

失败1: DISP_DEV=nosuch        → ERR_NOTFOUND(链表在, 无资源)
失败2: fb 后端 open 失败       → fb_close 归还已取得的资源, g_cur=NULL
失败3: mem 后端 malloc 失败    → ERR_NOMEM
退出后: g_list 仍在, g_cur=NULL; 下轮 init 开头重建链表
```

层序前提：input 层 init 要读 `disp_get_buf()` 的几何（假屏宽高），
font 层 draw 要写像素，所以层表里 display 排第一（见 main 篇）。

## 7. 容易读错的地方

- `line_length` 与 `xres * bpp / 8` 只在行尾有填充时不同；假显存配 320 就是为了
  让这个不同可见。判据 [7r2] 证明无填充时错误静默。
- `disp_field` 是"从第 offset 位起占 length 位"，RGB565 的绿在 5..10；
  读反成"高到低"会把拼色写错（判据 [7r5] 注错不缩位见红）。
- `unpack_field` 不是简单左对齐补零，是等比放大加四舍五入；直接
  `value << (8-length)` 会让 5 位最大值 31 变成 248 而非 255。
- mmap 的返回值失败是 `MAP_FAILED`；fd 的"未打开"是 -1，0 是合法 fd。
- 单缓冲下 flush 为空是模型决定的，调用它不产生任何效果；双缓冲接进来时
  flush 才有语义。

## 8. 消费者清单

- font 层：`disp_blend_pixel`（逐像素混色）、`disp_get_buf`（裁剪边界与几何）。
- `unittest/disp_test.c` 与 input 单测：画布、图案、几何。
- 判据：`check_core.sh` [7]~[10]（像素对账、fb 失败路径、ASan、分层边界），
  `check_font_input.sh` [11]（0xAA 哨兵）。
- 未来的 ui/page：同样只依赖 `disp_manager.h` 的六个入口。
