/* ui 层单测: 两颗按钮, 走一遍 按下/移出回弹/点击/销毁,
 * 显存转储交给 count.sh 数像素。--hold 让程序带着按下态退出,
 * 转储里就能数到按下底色。 */

#include <stdio.h>
#include <string.h>

#include "common.h"
#include "display/disp_manager.h"
#include "font/font_manager.h"
#include "ui/ui_manager.h"

static int g_ok_clicks;
static int g_no_clicks;

static void on_ok(struct ui_button *b, void *ctx)
{
	(void)b;
	(void)ctx;
	g_ok_clicks++;
	printf("clicked ok\n");
}

static void on_no(struct ui_button *b, void *ctx)
{
	(void)b;
	(void)ctx;
	g_no_clicks++;
	printf("clicked no\n");
}

int main(int argc, char **argv)
{
	struct ui_button *ok, *no;

	if (display_init() != ERR_OK || font_init() != ERR_OK ||
	    ui_init() != ERR_OK)
		return 1;

	ok = ui_button_create("OK", 8, 8, 40, 20, on_ok, NULL);
	no = ui_button_create("NO", 56, 8, 40, 20, on_no, NULL);
	if (ok == NULL || no == NULL)
		return 1;
	ui_button_draw_all();
	printf("ui count=%d\n", ui_button_count());

	if (argc > 1 && strcmp(argv[1], "--hold") == 0) {
		/* 带着按下态退出, count.sh 数按下底色的像素 */
		ui_button_press(28, 18);
		printf("hold pressed=%d\n", ui_button_is_pressed(ok));
		ui_exit();
		font_exit();
		display_exit();
		return 0;
	}

	/* 命中 OK: 按下 -> 抬起在同一颗 -> 回调一次 */
	printf("press=%d\n", ui_button_press(28, 18));
	printf("release_inside=%d\n", ui_button_release(28, 18));
	/* 按下后挪出区域抬起: 回弹, 不回调 */
	ui_button_press(28, 18);
	printf("release_outside=%d\n", ui_button_release(90, 90));
	/* 按下 NO -> 抬起 */
	ui_button_press(76, 18);
	printf("release_no=%d\n", ui_button_release(76, 18));
	/* 空地按下: 无人命中 */
	printf("press_void=%d\n", ui_button_press(30, 30));

	ui_button_destroy(no);
	printf("ui after_destroy=%d clicks=%d/%d\n", ui_button_count(),
	       g_ok_clicks, g_no_clicks);

	ui_exit();
	font_exit();
	display_exit();
	return 0;
}
