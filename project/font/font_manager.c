#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"
#include "font/font_internal.h"
#include "font/font_manager.h"

static struct font_provider *g_list;
static struct font_provider *g_cur;
static int g_inited;

void font_register(struct font_provider *provider)
{
	if (provider == NULL || provider->name == NULL)
		return;
	provider->next = g_list;
	g_list = provider;
}

static struct font_provider *font_find(const char *name)
{
	struct font_provider *p;

	for (p = g_list; p != NULL; p = p->next)
		if (strcmp(p->name, name) == 0)
			return p;
	return NULL;
}

int font_select(const char *provider, const char *font_path, int face_index)
{
	struct font_provider *next;
	int ret;

	if (!g_inited || provider == NULL)
		return ERR_PARAM;
	next = font_find(provider);
	if (next == NULL)
		return ERR_NOTFOUND;

	if (g_cur != NULL) {
		g_cur->close();
		g_cur = NULL;
	}
	ret = next->open(font_path, face_index);
	if (ret != ERR_OK)
		return ret;
	g_cur = next;
	return ERR_OK;
}

int font_set_pixel_size(int px)
{
	if (g_cur == NULL || px <= 0)
		return ERR_PARAM;
	return g_cur->set_pixel_size(px);
}

int font_init(void)
{
	const char *provider;
	const char *path;
	const char *size_text;
	char *end;
	long px = 24;
	int ret;

	if (g_inited)
		return ERR_OK;

	g_list = NULL;
	font_builtin_register();
	font_freetype_register();
	g_inited = 1;

	provider = getenv("FONT_DEV");
	if (provider == NULL)
		provider = "builtin";
	path = getenv("FONT_FILE");

	ret = font_select(provider, path, 0);
	if (ret != ERR_OK)
		goto fail;

	size_text = getenv("FONT_SIZE");
	if (size_text != NULL) {
		px = strtol(size_text, &end, 10);
		if (*size_text == '\0' || *end != '\0' || px <= 0 || px > 1024) {
			ret = ERR_PARAM;
			goto fail;
		}
	}
	ret = font_set_pixel_size((int)px);
	if (ret != ERR_OK)
		goto fail;

	LOG_INFO("font init OK");
	return ERR_OK;

fail:
	if (g_cur != NULL) {
		g_cur->close();
		g_cur = NULL;
	}
	g_inited = 0;
	return ret;
}

void font_exit(void)
{
	if (!g_inited)
		return;
	if (g_cur != NULL)
		g_cur->close();
	g_cur = NULL;
	g_list = NULL;
	g_inited = 0;
	LOG_INFO("font exit OK");
}

/* 严格 UTF-8：拒绝过长编码、surrogate 和 U+10FFFF 以外的数。 */
static int utf8_next(const unsigned char *s, size_t n, uint32_t *cp, size_t *used)
{
	uint32_t v;
	size_t need, i;

	if (n == 0 || cp == NULL || used == NULL)
		return ERR_PARAM;
	if (s[0] < 0x80) {
		*cp = s[0];
		*used = 1;
		return ERR_OK;
	}
	if (s[0] >= 0xc2 && s[0] <= 0xdf) {
		need = 2;
		v = s[0] & 0x1f;
	} else if (s[0] >= 0xe0 && s[0] <= 0xef) {
		need = 3;
		v = s[0] & 0x0f;
	} else if (s[0] >= 0xf0 && s[0] <= 0xf4) {
		need = 4;
		v = s[0] & 0x07;
	} else {
		return ERR_PARAM;
	}
	if (n < need)
		return ERR_PARAM;
	for (i = 1; i < need; i++) {
		if ((s[i] & 0xc0) != 0x80)
			return ERR_PARAM;
		v = (v << 6) | (s[i] & 0x3f);
	}
	if ((need == 3 && v < 0x800) || (need == 4 && v < 0x10000) ||
	    (v >= 0xd800 && v <= 0xdfff) || v > 0x10ffff)
		return ERR_PARAM;
	*cp = v;
	*used = need;
	return ERR_OK;
}

static unsigned char bitmap_alpha(const struct font_bitmap *b, int x, int y)
{
	const unsigned char *row;
	int stride = b->pitch < 0 ? -b->pitch : b->pitch;

	row = b->pitch >= 0 ? b->buffer + y * stride
	                    : b->buffer + (b->rows - 1 - y) * stride;
	if (b->pixel_mode == FONT_PIXEL_MONO)
		return (row[x / 8] & (0x80u >> (x % 8))) ? 255 : 0;
	if (b->num_grays <= 1)
		return row[x] ? 255 : 0;
	return (unsigned char)((row[x] * 255u + (b->num_grays - 1) / 2) /
			       (unsigned int)(b->num_grays - 1));
}

static void metrics_add_box(struct font_text_metrics *m, int *has_ink,
			    int left, int top, int width, int rows)
{
	int right = left + width;
	int bottom = top + rows;

	if (width <= 0 || rows <= 0)
		return;
	if (!*has_ink) {
		m->ink_x = left;
		m->ink_y = top;
		m->ink_w = right;
		m->ink_h = bottom;
		*has_ink = 1;
		return;
	}
	if (left < m->ink_x)
		m->ink_x = left;
	if (top < m->ink_y)
		m->ink_y = top;
	if (right > m->ink_w)
		m->ink_w = right;
	if (bottom > m->ink_h)
		m->ink_h = bottom;
}

static int text_run(const char *text, size_t len, int draw, int origin_x,
		    int baseline_y, unsigned int rgb,
		    struct font_text_metrics *out, size_t *bad_offset)
{
	const unsigned char *s = (const unsigned char *)text;
	struct font_text_metrics m;
	struct font_bitmap b;
	const struct disp_buf *display = NULL;
	uint32_t cp, rendered_cp;
	size_t off = 0, used;
	int pen_x = 0, pen_y = 0, has_ink = 0;
	int gx, gy, x, y, ret;

	if (text == NULL || out == NULL || bad_offset == NULL || g_cur == NULL)
		return ERR_PARAM;
	memset(&m, 0, sizeof(m));
	*bad_offset = (size_t)-1;
	if (draw) {
		display = disp_get_buf();
		if (display == NULL)
			return ERR_PARAM;
	}

	while (off < len) {
		ret = utf8_next(s + off, len - off, &cp, &used);
		if (ret != ERR_OK) {
			*bad_offset = off;
			return ret;
		}
		m.codepoints++;
		rendered_cp = cp;
		if (!g_cur->has_codepoint(cp)) {
			m.missing++;
			rendered_cp = '?';
		}
		memset(&b, 0, sizeof(b));
		ret = g_cur->render(rendered_cp, &b);
		if (ret != ERR_OK)
			return ret;

		gx = (pen_x >> 6) + b.left;
		gy = (pen_y >> 6) - b.top;
		metrics_add_box(&m, &has_ink, gx, gy, b.width, b.rows);

		if (draw) {
			for (y = 0; y < b.rows; y++) {
				for (x = 0; x < b.width; x++) {
					unsigned char alpha = bitmap_alpha(&b, x, y);
					int dx, dy;

					if (alpha == 0)
						continue;
					m.covered_pixels++;
					dx = origin_x + gx + x;
					dy = baseline_y + gy + y;
					if (dx < 0 || dy < 0 || dx >= display->xres || dy >= display->yres) {
						m.clipped_pixels++;
						continue;
					}
					ret = disp_blend_pixel(dx, dy, rgb, alpha);
					if (ret != ERR_OK)
						return ret;
					m.drawn_pixels++;
				}
			}
		}
		pen_x += b.advance_x_26_6;
		pen_y += b.advance_y_26_6;
		off += used;
	}

	if (has_ink) {
		m.ink_w -= m.ink_x;
		m.ink_h -= m.ink_y;
	}
	m.advance_x_26_6 = pen_x;
	m.advance_y_26_6 = pen_y;
	*out = m;
	return ERR_OK;
}

int font_measure_utf8(const char *text, size_t len,
		      struct font_text_metrics *out, size_t *bad_offset)
{
	return text_run(text, len, 0, 0, 0, 0, out, bad_offset);
}

int font_draw_utf8(const char *text, size_t len, int x, int baseline_y,
		   unsigned int rgb, struct font_text_metrics *out,
		   size_t *bad_offset)
{
	return text_run(text, len, 1, x, baseline_y, rgb, out, bad_offset);
}
