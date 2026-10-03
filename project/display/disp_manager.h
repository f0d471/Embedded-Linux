#ifndef __DISP_MANAGER_H
#define __DISP_MANAGER_H

/* 一个颜色分量在像素里的位置: 从第 offset 位起, 占 length 位 */
struct disp_field {
	int offset;
	int length;
};

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

/* 一个显示后端。每个后端定义一份, 在自己的 xxx_register 里挂进链表 */
struct disp_ops {
	const char *name;
	int  (*open)(struct disp_buf *out);
	void (*close)(void);
	int  (*flush)(const struct disp_region *r);
	struct disp_ops *next;
};

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
