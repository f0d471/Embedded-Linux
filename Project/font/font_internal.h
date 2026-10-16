#ifndef __FONT_INTERNAL_H
#define __FONT_INTERNAL_H

#include <stdint.h>

enum font_pixel_mode {
	FONT_PIXEL_MONO = 1,
	FONT_PIXEL_GRAY = 2,
};

/*
 * buffer 是 provider 借给 manager 的只读视图，只保证到下一次 render/close 前有效。
 * pitch 是相邻两行首地址的跨度，允许为负；width 只是有效像素数。
 */
struct font_bitmap {
	int width;
	int rows;
	int pitch;
	enum font_pixel_mode pixel_mode;
	int num_grays;
	int left;
	int top;
	int advance_x_26_6;
	int advance_y_26_6;
	const unsigned char *buffer;
};

struct font_provider {
	const char *name;
	int  (*open)(const char *path, int face_index);
	void (*close)(void);
	int  (*set_pixel_size)(int px);
	int  (*has_codepoint)(uint32_t codepoint);
	int  (*render)(uint32_t codepoint, struct font_bitmap *out);
	struct font_provider *next;
};

void font_register(struct font_provider *provider);
void font_builtin_register(void);
void font_freetype_register(void);

#endif /* __FONT_INTERNAL_H */
