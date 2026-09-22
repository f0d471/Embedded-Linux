/*
 * display 层管理器。对上提供画布信息和画点/填矩形, 对下按名字选一个后端。
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

/* 把一个 8 位分量缩到 length 位再挪到 offset 位。length 为 8 时 c8 原样返回 */
static unsigned int pack_field(unsigned int c8, const struct disp_field *f)
{
	return (c8 >> (8 - f->length)) << f->offset;
}

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
