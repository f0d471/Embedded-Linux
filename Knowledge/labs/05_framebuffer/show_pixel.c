/* 05 章 4.1 节：show_pixel——在真 /dev/fb0 上清屏并画 100 个红点。
 * 编译：arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra show_pixel.c -o show_pixel_arm
 *       gcc -Wall -Wextra -O2 show_pixel.c -o show_pixel      （电脑上只能跑出错分支）
 * 用法：./show_pixel [设备路径]        默认 /dev/fb0
 * 和 fakefb.c 的差别只有一件事：参数不从命令行给，是 ioctl 问驱动要来的。
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/fb.h>

static int fd_fb;
static struct fb_var_screeninfo var;   /* 可变参数:分辨率、bpp、位段 */
static struct fb_fix_screeninfo fix;   /* 固定参数:行宽、显存地址与大小 */
static unsigned char *fb_base;
static unsigned long screen_size;
static unsigned pixel_width;

/* 在 (x, y) 处描一个点。颜色传进来一律是 0x00RRGGBB */
static void lcd_put_pixel(unsigned x, unsigned y, unsigned color)
{
    unsigned char  *pen_8  = fb_base + y * fix.line_length + x * pixel_width;
    unsigned short *pen_16 = (unsigned short *)pen_8;
    unsigned int   *pen_32 = (unsigned int *)pen_8;
    unsigned r, g, b, v;

    switch (var.bits_per_pixel) {
    case 8:
        *pen_8 = color;                  /* 8bpp 是调色板编号,本章不展开 */
        break;
    case 16:                             /* 本板插显示器后是 RGB565 */
    case 32:                             /* 本板未插屏时是 xRGB8888 */
        r = (color >> 16) & 0xff;
        g = (color >> 8)  & 0xff;
        b =  color        & 0xff;
        v = ((r >> (8 - var.red.length))   << var.red.offset)
          | ((g >> (8 - var.green.length)) << var.green.offset)
          | ((b >> (8 - var.blue.length))  << var.blue.offset);
        if (var.bits_per_pixel == 16)
            *pen_16 = v;
        else
            *pen_32 = v;
        break;
    default:
        printf("can't support %ubpp\n", var.bits_per_pixel);
        break;
    }
}

int main(int argc, char **argv)
{
    const char *dev = argc > 1 ? argv[1] : "/dev/fb0";
    int i;

    fd_fb = open(dev, O_RDWR);
    if (fd_fb < 0) {
        printf("open %s 失败: %s\n", dev, strerror(errno));
        return 1;
    }
    if (ioctl(fd_fb, FBIOGET_VSCREENINFO, &var) < 0) {
        printf("can't get var: %s\n", strerror(errno));
        return 1;
    }
    if (ioctl(fd_fb, FBIOGET_FSCREENINFO, &fix) < 0) {
        printf("can't get fix: %s\n", strerror(errno));
        return 1;
    }

    pixel_width = var.bits_per_pixel / 8;
    screen_size = (unsigned long)fix.line_length * var.yres;

    fb_base = mmap(NULL, screen_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd_fb, 0);
    if (fb_base == MAP_FAILED) {
        printf("can't mmap: %s\n", strerror(errno));
        return 1;
    }

    memset(fb_base, 0xff, screen_size);       /* 清屏:全 1 在任何布局下都是白 */

    for (i = 0; i < 100; i++)                 /* 屏幕正中横着画 100 个红点 */
        lcd_put_pixel(var.xres / 2 + i, var.yres / 2, 0xFF0000);

    munmap(fb_base, screen_size);
    close(fd_fb);
    return 0;
}
