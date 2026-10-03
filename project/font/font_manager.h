#ifndef __FONT_MANAGER_H
#define __FONT_MANAGER_H

#include <stddef.h>

struct font_text_metrics {
	/* 相对传入 pen/baseline 的墨迹外框；没有墨迹时 w/h 为 0 */
	int ink_x;
	int ink_y;
	int ink_w;
	int ink_h;
	int advance_x_26_6;
	int advance_y_26_6;
	size_t codepoints;
	size_t missing;
	size_t covered_pixels;
	size_t drawn_pixels;
	size_t clipped_pixels;
};

int  font_init(void);
void font_exit(void);

int font_select(const char *provider, const char *font_path, int face_index);
int font_set_pixel_size(int px);

/* bad_offset 在 UTF-8 非法时返回首个坏字节下标，成功时写为 (size_t)-1。 */
int font_measure_utf8(const char *text, size_t len,
		      struct font_text_metrics *out, size_t *bad_offset);
int font_draw_utf8(const char *text, size_t len, int x, int baseline_y,
		   unsigned int rgb, struct font_text_metrics *out,
		   size_t *bad_offset);

#endif /* __FONT_MANAGER_H */
