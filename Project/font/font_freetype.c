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
