/* fundamentals 14 的配套探针：用交叉构建出的真 FreeType 库链接一次，
 * 动态版看 NEEDED 记的是什么，静态版看动态段是否消失。
 * 交叉链接（在 11_cross_library/check.sh 里）：
 *   arm-linux-gnueabihf-gcc -I$STAGE/usr/include/freetype2 \
 *       -o ft-dyn ftmini.c -L$STAGE/usr/lib -lfreetype
 *   arm-linux-gnueabihf-gcc -static -I$STAGE/usr/include/freetype2 \
 *       -o ft-sta ftmini.c $STAGE/usr/lib/libfreetype.a -lm
 */
#include <stdio.h>
#include <ft2build.h>
#include FT_FREETYPE_H

int main(void)
{
	FT_Library lib;
	FT_Int major, minor, patch;

	if (FT_Init_FreeType(&lib))
		return 1;
	FT_Library_Version(lib, &major, &minor, &patch);
	printf("freetype=%d.%d.%d\n", major, minor, patch);
	FT_Done_FreeType(lib);
	return 0;
}
