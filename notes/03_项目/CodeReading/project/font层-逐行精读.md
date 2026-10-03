# font 层逐行精读

对应代码：`project/font/font_manager.h`（34 行）、`font_internal.h`（42 行）、
`font_manager.c`（296 行）、`font_builtin.c`（113 行）、`font_freetype.c`（98 行）。

## 1. 文件定位

对上提供 UTF-8 文字的测量与绘制，对下挂 builtin/FreeType 两个字形来源。
`font_internal.h` 是唯一的内部契约（provider 结构与字形借用规则），FreeType 的
类型被封在 `font_freetype.c` 一个文件里。上游消费者目前是 `unittest/font_test.c`
与 `main.c` 的层表，未来的 OSD 与 ui 文字布局走同一组公开函数。

前置知识：[从零开始读写 project 代码](../00-从零开始读写项目代码.md)第 7 节
（UTF-8）、第 5 节（函数指针链表）；第 04 章笔记（文字显示）；
开发经过见 [TechReports/project/04](../../TechReports/project/04-font层-从UTF-8到帧缓冲灰度合成.md)。

```
ui / OSD(未接入)  font_test  main.c 层表
        │ font_measure_utf8 / font_draw_utf8
        ▼
┌────────────── font_manager.c ──────────────┐
│ utf8_next 严格解码 → text_run 排版/统计/裁剪 │
└───────┬────────────────────────────────────┘
        │ has_codepoint / render(cp, &b)
 ┌──────┴───────┐
 │  font_builtin.c   │  font_freetype.c
 │  6x14 GRAY 静态表  │  FT_Face slot(借用)
 └──────────────┘
        │ 逐像素 alpha
        ▼
 disp_blend_pixel()   (display 层, 见 display 篇)
```

## 2. font_manager.h

### 第 1—19 行：guard 与测量结果

```c
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
```

一个结构体装齐"这次调用发生了什么"。字段分三组，单位不同：
外框四项是像素（相对调用者传入的 pen/baseline，`ink_y` 常为负——字形在基线上方）；
advance 两项是 1/64 像素定点数；五个计数是 `size_t`。测量调用里
`covered/drawn/clipped` 恒为 0（测量不逐像素走），读数时要按这个口径解释。
`codepoints` 数码点、`len` 数字节，"A中g" 是 3 与 5。

### 第 21—34 行：公开函数

```c
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
```

两个入口都显式收 `len`，不依赖 NUL 结尾——上层可能从配置或网络流里拿到
非终止的缓冲。`bad_offset` 的成功值是 `(size_t)-1`：`size_t` 无符号，
-1 转入后是全 1，任何合法下标都不会撞上。draw 比 measure 多起点、基线、颜色
三个参数，其余语义相同。

## 3. font_internal.h

### 第 1—26 行：像素模式与字形

```c
#ifndef __FONT_INTERNAL_H
#define __FONT_INTERNAL_H

#include <stdint.h>

enum font_pixel_mode {
	FONT_PIXEL_MONO = 1,
	FONT_PIXEL_GRAY = 2,
};

/*
 * buffer 是 provider 借给 manager 的只读视图，只保证到下一次 render/close 前有效。
 * pitch 是相邻两行行首的跨度，允许为负；width 只是有效像素数。
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
```

借用契约写在结构体正上方：`buffer` 只借到下一次 `render/close`。manager 因此
不得把指针存进自己的长命对象；注释同时钉住 `pitch` 与 `width` 是两个量，
FreeType 的位图允许负 `pitch`（行序自底向上）与行尾填充。`num_grays` 在
GRAY 模式下通常是 256，MONO 模式下无意义。`top` 向上为正，与屏幕 Y 相反，
第 4 节 `gy` 的减号就是它。

### 第 28—42 行：provider 与注册

```c
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
```

provider 五个动作：打开、关闭、设字号、查码点、渲染。`open` 的 `path` 与
`face_index` 对 builtin 无意义（它返回 `ERR_OK` 忽略之），对 FreeType 是文件
与 face 序号——两种来源的差异被接口消化。注册函数在内部头而不在公开头：
上层只选名字，不接触 provider 结构。

## 4. font_manager.c

### 第 1—30 行：全局、注册、查找

```c
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
```

头插注册与 display 层同形，这里多了判空：`font_test.c` 会注册自己的 probe
provider，空指针来自测试代码的手误，挡在入口。`g_inited` 与 `g_cur` 分开：
init 阶段就置 `g_inited`（链表就绪），`g_cur` 在 select 成功前是 NULL。

### 第 32—59 行：select 与 set_pixel_size

```c
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
```

切换字体时先关旧 provider 再开新的：FreeType 换文件必须释放旧 face/library，
把这条顺序放进 select，调用方不需要知道 provider 内部有什么资源。新 open 失败
时 `g_cur` 保持 NULL——半开状态不外泄。`set_pixel_size` 只透传，字号语义由
provider 定（builtin 忽略，FreeType 是像素高度）。

### 第 61—121 行：init 与 exit

```c
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
```

与 display 层同一套骨架：链表每轮重建、环境变量选后端、失败全回滚。
`FONT_SIZE` 的检查有四项：空串（`strtol` 没动 `end` 就指向开头，`*end=='\0'`
会把空串放行，所以单独判 `*size_text=='\0'`）、尾随垃圾（`*end != '\0'`）、
下界、上界。`long` 收 `strtol` 再转 `int`，上界 1024 保证不溢出。

`goto fail` 把三条失败路径收进一个回滚块：select 成功后任何一步失败，
都要把已经打开的 provider 关掉、`g_inited` 清零，否则下一轮 init 会因
`g_inited==1` 直接"成功"而实际没有可用字体。

### 第 123—161 行：utf8_next

```c
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
```

检查顺序固定，每一步都在保护下一步：先按首字节定长度并取首段位
（`0x1f`/`0x0f`/`0x07` 分别是 5/4/3 位），然后**先**确认 `n >= need` **再**读
`s[1..need-1]`——顺序反了会在缓冲区末尾越界读。续字节 `(s[i] & 0xc0) != 0x80`
只放行 `10xxxxxx`。最后一段拒绝四类：三字节编码出不足 0x800 的值（过长编码，
如 `C0 AF`）、四字节出不足 0x10000 的值、UTF-16 代理区 `D800..DFFF`（UTF-8 里
非法）、超过 U+10FFFF（`F5..FF` 开头或越界值）。手算例："中"的
`E4 B8 AD`：`v=0x04` → `(0x04<<6)|0x38=0x138` → `(0x138<<6)|0x2d=0x4e2d`。

`used` 出参让调用方推进字节偏移而不必复述解码逻辑；失败时 `cp/used` 不写，
调用方的 `off` 保持原值，正好用来报 `bad_offset`。

### 第 163—202 行：bitmap_alpha 与外框

```c
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
```

`bitmap_alpha` 三种取值路径。行定位：`stride = |pitch|`，负 `pitch` 时逻辑第
y 行在内存的倒数第 y 行——判据 [11] 的探针 `pitch=-6` 专考这一支，注错把它改回
`y * stride` 后 8 个 alpha 探针整体反序见红。MONO 按位取（最高位在前），
`0x80u >> (x%8)` 从左往右扫。GRAY 归一化到 0..255：`num_grays` 为 256 时
`(v*255+255)/256`，级数不足 2 的退化成阈值。

`metrics_add_box` 的 `ink_w/ink_h` 在循环中途存的是**右/下边界**，最后一次
`text_run` 收尾时才减成宽高——只看字段名会读错中途含义。首字形建立外框，
后续向四边扩展（并集，中间的空隙也算在内）；空字形（`width/rows<=0`，
如空格）不参与外框但 advance 照常推进。

### 第 204—296 行：text_run 与两个入口

```c
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
```

时间轴（一次 `font_draw_utf8("A中g", 5, 10, 20, ...)`，builtin 缺"中"）：

| 步 | off | cp | 动作 | pen_x 之后 |
|---:|---:|---|---|---:|
| 1 | 0 | 0x41 'A' | render → gx=0, gy=-14, 外框建立, 逐像素 blend | 384 |
| 2 | 1 | 0x4e2d | has_codepoint 否 → missing=1, rendered='?' | 768 |
| 3 | 4 | 0x67 'g' | render, 外框扩展, blend | 1152 |
| 收尾 | 5 | — | ink_w/h 由边界减成宽高, metrics 一次写出 | — |

定点推进：`pen` 全程按 26.6 累加，落点才 `>> 6`。两个字形各前进 33/64 像素时，
逐字先取整得 0、0；先累加得 66/64 取整 1——取整必须在累加之后。`gy` 用减号
因为 `top` 向上为正而屏幕 Y 向下。四个像素计数分工：非零 alpha 计 `covered`，
屏外计 `clipped`，blend 成功计 `drawn`，恒等式 `covered = clipped + drawn`。
RGB565 上混色成功不等于回读非黑（低 alpha 量化成 0），见 TechReport 04 第 4.4 节。

`font_measure_utf8` 传 `draw=0`：同一循环、同一外框与 advance，只是不拿
display、不落像素。布局预测与实际墨迹由同一段代码保证一致。`render` 失败
（如 FreeType 打不开字形）直接返回错误，半成品 metrics 不写 `*out`。

## 5. font_builtin.c

### 第 1—36 行：字形表

```c
#include <stdint.h>
#include <string.h>

#include "common.h"
#include "font/font_internal.h"

struct builtin_glyph {
	char ch;
	unsigned char rows[7];
};

/* 5x7 点阵是无外部字体时的英文/数字兜底；小写字母复用大写字形。 */
static const struct builtin_glyph g_glyphs[] = {
	{ ' ', {0,0,0,0,0,0,0} }, { '!', {4,4,4,4,4,0,4} },
	{ '-', {0,0,0,31,0,0,0} }, { '.', {0,0,0,0,0,6,6} },
	{ '/', {1,2,4,8,16,0,0} }, { ':', {0,6,6,0,6,6,0} },
	{ '?', {14,17,1,2,4,0,4} },
	{ '0', {14,17,19,21,25,17,14} }, { '1', {4,12,4,4,4,4,14} },
	{ '2', {14,17,1,2,4,8,31} }, { '3', {30,1,1,14,1,1,30} },
	{ '4', {2,6,10,18,31,2,2} }, { '5', {31,16,16,30,1,1,30} },
	{ '6', {14,16,16,30,17,17,14} }, { '7', {31,1,2,4,8,8,8} },
	{ '8', {14,17,17,14,17,17,14} }, { '9', {14,17,17,15,1,1,14} },
	{ 'A', {14,17,17,31,17,17,17} }, { 'B', {30,17,17,30,17,17,30} },
	{ 'C', {14,17,16,16,16,17,14} }, { 'D', {30,17,17,17,17,17,30} },
	{ 'E', {31,16,16,30,16,16,31} }, { 'F', {31,16,16,30,16,16,16} },
	{ 'G', {14,17,16,23,17,17,15} }, { 'H', {17,17,17,31,17,17,17} },
	{ 'I', {14,4,4,4,4,4,14} }, { 'J', {7,2,2,2,18,18,12} },
	{ 'K', {17,18,20,24,20,18,17} }, { 'L', {16,16,16,16,16,16,31} },
	{ 'M', {17,27,21,21,17,17,17} }, { 'N', {17,25,21,19,17,17,17} },
	{ 'O', {14,17,17,17,17,17,14} }, { 'P', {30,17,17,30,16,16,16} },
	{ 'Q', {14,17,17,17,21,18,13} }, { 'R', {30,17,17,30,20,18,17} },
	{ 'S', {15,16,16,14,1,1,30} }, { 'T', {31,4,4,4,4,4,4} },
	{ 'U', {17,17,17,17,17,17,14} }, { 'V', {17,17,17,17,17,10,4} },
	{ 'W', {17,17,17,21,21,21,10} }, { 'X', {17,17,10,4,10,17,17} },
	{ 'Y', {17,17,10,4,4,4,4} }, { 'Z', {31,1,2,4,8,16,31} },
};
```

每行一个字形的 7 个字节，每字节 5 位有效（低位在右）。'A' 首行 `14 = 01110`
即顶部一横两端收窄。表只收大写与常用标点，小写在 `find_glyph` 里折叠成大写。

### 第 38—99 行：查找与渲染

```c
static unsigned char g_bitmap[6 * 14];

static const struct builtin_glyph *find_glyph(uint32_t cp)
{
	size_t i;
	char ch;

	if (cp >= 'a' && cp <= 'z')
		cp -= 'a' - 'A';
	if (cp > 0x7f)
		return NULL;
	ch = (char)cp;
	for (i = 0; i < ARRAY_SIZE(g_glyphs); i++)
		if (g_glyphs[i].ch == ch)
			return &g_glyphs[i];
	return NULL;
}

static int builtin_open(const char *path, int face_index)
{
	(void)path;
	return face_index == 0 ? ERR_OK : ERR_PARAM;
}

static void builtin_close(void)
{
}

static int builtin_set_pixel_size(int px)
{
	return px > 0 ? ERR_OK : ERR_PARAM;
}

static int builtin_has_codepoint(uint32_t cp)
{
	return find_glyph(cp) != NULL;
}

static int builtin_render(uint32_t cp, struct font_bitmap *out)
{
	const struct builtin_glyph *g = find_glyph(cp);
	int x, y;

	if (g == NULL || out == NULL)
		return ERR_NOTFOUND;
	memset(g_bitmap, 0, sizeof(g_bitmap));
	for (y = 0; y < 7; y++)
		for (x = 0; x < 5; x++)
			if (g->rows[y] & (1u << (4 - x))) {
				g_bitmap[(y * 2) * 6 + x] = 255;
				g_bitmap[(y * 2 + 1) * 6 + x] = 255;
			}

	*out = (struct font_bitmap) {
		.width = 6, .rows = 14, .pitch = 6,
		.pixel_mode = FONT_PIXEL_GRAY, .num_grays = 256,
		.left = 0, .top = 14,
		.advance_x_26_6 = 6 * 64, .advance_y_26_6 = 0,
		.buffer = g_bitmap,
	};
	return ERR_OK;
}
```

渲染把 5x7 纵向放大一倍成 6x14：源位 `rows[y] & (1<<(4-x))`（最高位在左），
写到 `(2y, x)` 与 `(2y+1, x)` 两行；第 6 列与两行填充恒 0，`pitch=6` 因此带
行尾填充——它本身就是判据 [11] 之外又一个"行宽≠有效宽"的实例。
`g_bitmap` 是单份静态缓冲：借用契约（下次 render 失效）在这里兑现，
provider 无堆内存，close 为空。`top=14`（全高字形立在基线上）、
`advance=6*64`（6 像素）。
`(void)path`/`(void)face_index` 抵消 `-Werror`；`face_index != 0` 拒绝，
保持与 FreeType 相同的参数校验面。

### 第 101—113 行：注册

```c
static struct font_provider g_builtin = {
	.name = "builtin",
	.open = builtin_open,
	.close = builtin_close,
	.set_pixel_size = builtin_set_pixel_size,
	.has_codepoint = builtin_has_codepoint,
	.render = builtin_render,
};

void font_builtin_register(void)
{
	font_register(&g_builtin);
}
```

指定初始化器按字段名对号入座，字段顺序变动不破坏初始化。`font_internal.h`
声明了两个 `xxx_register`，本文件与 `font_freetype.c` 各实现一个。

## 6. font_freetype.c

### 第 1—22 行：句柄与幂等关闭

```c
#include <stdint.h>

#include <ft2build.h>
#include FT_FREETYPE_H

#include "common.h"
#include "font/font_internal.h"

static FT_Library g_library;
static FT_Face g_face;

static void freetype_close(void)
{
	if (g_face != NULL) {
		FT_Done_Face(g_face);
		g_face = NULL;
	}
	if (g_library != NULL) {
		FT_Done_FreeType(g_library);
		g_library = NULL;
	}
}
```

`ft2build.h` + `FT_FREETYPE_H` 是 FreeType 2 的标准引入方式。释放反序于创建
（face 依赖 library），句柄清 NULL 使函数可重复调用。`FT_Done_*` 返回的错误
被有意忽略：关闭阶段没有可恢复的动作，报出去也无路可走。

### 第 24—52 行：open、size、has

```c
static int freetype_open(const char *path, int face_index)
{
	FT_Error error;

	if (path == NULL || path[0] == '\0' || face_index < 0)
		return ERR_PARAM;
	freetype_close();
	error = FT_Init_FreeType(&g_library);
	if (error)
		return ERR_IO;
	error = FT_New_Face(g_library, path, face_index, &g_face);
	if (error) {
		freetype_close();
		return ERR_IO;
	}
	return ERR_OK;
}

static int freetype_set_pixel_size(int px)
{
	if (g_face == NULL || px <= 0)
		return ERR_PARAM;
	return FT_Set_Pixel_Sizes(g_face, 0, (FT_UInt)px) ? ERR_IO : ERR_OK;
}

static int freetype_has_codepoint(uint32_t cp)
{
	return g_face != NULL && FT_Get_Char_Index(g_face, cp) != 0;
}
```

open 开头先 `freetype_close()`：换字体时旧资源由 provider 自己收，
select 不用区分"新旧是否同 provider"。`FT_New_Face` 失败时 library 已创建，
`freetype_close()` 负责归还——三个失败路径共用一个清理函数。
`FT_Get_Char_Index` 返回字形索引，0 是"没有"，正好当布尔用；`.notdef`
字形存在但 `has_codepoint` 仍算没有，由 manager 计 `missing` 并画问号。

### 第 54—98 行：render 与注册

```c
static int freetype_render(uint32_t cp, struct font_bitmap *out)
{
	FT_GlyphSlot slot;
	enum font_pixel_mode mode;

	if (g_face == NULL || out == NULL)
		return ERR_PARAM;
	if (FT_Load_Char(g_face, cp, FT_LOAD_RENDER))
		return ERR_NOTFOUND;
	slot = g_face->glyph;
	if (slot->bitmap.pixel_mode == FT_PIXEL_MODE_GRAY)
		mode = FONT_PIXEL_GRAY;
	else if (slot->bitmap.pixel_mode == FT_PIXEL_MODE_MONO)
		mode = FONT_PIXEL_MONO;
	else
		return ERR_NOTSUP;

	*out = (struct font_bitmap) {
		.width = (int)slot->bitmap.width,
		.rows = (int)slot->bitmap.rows,
		.pitch = slot->bitmap.pitch,
		.pixel_mode = mode,
		.num_grays = slot->bitmap.num_grays,
		.left = slot->bitmap_left,
		.top = slot->bitmap_top,
		.advance_x_26_6 = (int)slot->advance.x,
		.advance_y_26_6 = (int)slot->advance.y,
		.buffer = slot->bitmap.buffer,
	};
	return ERR_OK;
}

static struct font_provider g_freetype = {
	.name = "freetype",
	.open = freetype_open,
	.close = freetype_close,
	.set_pixel_size = freetype_set_pixel_size,
	.has_codepoint = freetype_has_codepoint,
	.render = freetype_render,
};

void font_freetype_register(void)
{
	font_register(&g_freetype);
}
```

`FT_LOAD_RENDER` 让加载即出位图。render 是纯映射：FreeType 的八个字段抄进
`font_bitmap`，`FT_Face` 类型不出本文件；`pitch` 原样带符号传出，负值交给
manager 的 `bitmap_alpha` 处理。`buffer` 指向 FreeType 槽位内部，下次
`FT_Load_Char` 就被覆盖——借用契约的来源在这里。除 GRAY/MONO 外的位图模式
（如 LCD 子像素）显式拒绝，`ERR_NOTSUP` 优于静默画错。

## 7. 执行顺序

```
成功:  font_init → 重建链表 → 注册两个 provider → FONT_DEV 选 builtin/freetype
       → FONT_FILE 打开(face/library) → FONT_SIZE 设字号
       → measure/draw 任意次(每次: 解码→查缺→render→排版→[blend]) → font_exit

失败1: FONT_FILE 打不开        → freetype_open 内部 close, select 失败
失败2: FONT_SIZE 非法          → goto fail: 关 provider, g_inited=0
失败3: draw 时 display 未 init → ERR_PARAM(draw 前置条件不成立)
draw 前置: display_init 已成功(main.c 层表保证 display 在 font 之前)
```

## 8. 容易读错的地方

- `ink_y` 相对 baseline 常为负；`ink_w/ink_h` 在 `text_run` 收尾前是右/下边界值。
- `advance` 是 26.6，320 表示 5 像素；先累加后取整，顺序换了长串会漂移。
- `len` 与 `codepoints` 一个数字节一个数码点，"A中g" 是 5 和 3。
- 负 `pitch` 的逻辑首行在内存后半；把 width 当 pitch 在无填充正 pitch 位图上
  碰巧正确，探针位图专考这个。
- 测量调用的 covered/drawn/clipped 恒为 0，不代表字形没有墨迹。
- `freetype_close` 允许重复调用（句柄清 NULL）；`builtin_close` 为空不是漏写，
  它确实没有资源。

## 9. 消费者清单

- `main.c` 层表：`font_init/font_exit`。
- `unittest/font_test.c`：全部公开接口，外加注册第三个 probe provider。
- display 层：`disp_blend_pixel` 被 `text_run` 逐像素调用（draw 模式）。
- 判据：`check_font_input.sh` [11][12] 共 13 条。
- 未来的 OSD（路线图刀 4）与 ui 文字：只依赖 `font_manager.h` 的六个入口。
