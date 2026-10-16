/* 05 章 1.3 节：fbinfo——把 framebuffer 驱动知道的全问出来。
 * 编译：gcc -Wall -Wextra -O2 fbinfo.c -o fbinfo            （WSL,对 /dev/null 跑报错分支）
 *       arm-linux-gnueabihf-gcc -static -O2 -Wall -Wextra fbinfo.c -o fbinfo_arm
 * 用法：./fbinfo [设备路径]        默认 /dev/fb0
 * 判据:三笔对账(行宽/大小/帧率)见教程;注错版 -DBUG_VTOTAL / -DBUG_HVTOTAL。
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/fb.h>

int main(int argc, char **argv)
{
    const char *dev = argc > 1 ? argv[1] : "/dev/fb0";
    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
    int fd = open(dev, O_RDWR);

    if (fd < 0) {
        printf("open %s 失败: %s\n", dev, strerror(errno));
        return 1;
    }
    if (ioctl(fd, FBIOGET_FSCREENINFO, &fix) < 0) {
        printf("ioctl 失败: %s\n", strerror(errno));
        return 1;                          /* /dev/null 在这里 ENOTTY */
    }
    if (ioctl(fd, FBIOGET_VSCREENINFO, &var) < 0) {
        printf("ioctl 失败: %s\n", strerror(errno));
        return 1;
    }

    printf("[fix] id=%s smem_start=0x%lx smem_len=%u line_length=%u type=%u visual=%u ypanstep=%u\n",
           fix.id, (unsigned long)fix.smem_start, fix.smem_len,
           fix.line_length, fix.type, fix.visual, fix.ypanstep);
    printf("[var] xres=%u yres=%u xres_virtual=%u yres_virtual=%u xoffset=%u yoffset=%u bpp=%u\n",
           var.xres, var.yres, var.xres_virtual, var.yres_virtual,
           var.xoffset, var.yoffset, var.bits_per_pixel);
    printf("[var] red=%u/%u green=%u/%u blue=%u/%u transp=%u/%u (offset/length)\n",
           var.red.offset, var.red.length, var.green.offset, var.green.length,
           var.blue.offset, var.blue.length, var.transp.offset, var.transp.length);
    printf("[var] pixclock=%u ps  left=%u right=%u hsync=%u  upper=%u lower=%u vsync=%u  size=%ux%u mm\n",
           var.pixclock, var.left_margin, var.right_margin, var.hsync_len,
           var.upper_margin, var.lower_margin, var.vsync_len, var.width, var.height);

    /* 三笔对账 */
    unsigned line_calc = var.xres * var.bits_per_pixel / 8;
    unsigned visible   = var.xres * var.yres * var.bits_per_pixel / 8;
    unsigned htotal = var.xres + var.left_margin + var.right_margin + var.hsync_len;
    unsigned vtotal = var.yres + var.upper_margin + var.lower_margin + var.vsync_len;
#ifdef BUG_VTOTAL
    vtotal = var.yres;                     /* 注错:忘了纵向空白和同步 */
#endif
#ifdef BUG_HVTOTAL
    htotal = var.xres;
    vtotal = var.yres;                     /* 注错:两个都忘 */
#endif
    unsigned long long pclk_hz = 1000000000000ULL / var.pixclock;
    unsigned row_hz = pclk_hz / htotal;
    printf("对账1 行宽: xres*bpp/8=%u  line_length=%u  %s\n",
           line_calc, fix.line_length,
           line_calc == fix.line_length ? "相等" : "不等!");
    printf("对账2 大小: 可见区=%u  虚拟区=%u  smem_len=%u  smem_len/可见区=%.2f\n",
           visible, var.xres_virtual * var.yres_virtual * var.bits_per_pixel / 8,
           fix.smem_len, (double)fix.smem_len / visible);
    printf("对账3 刷新: 像素时钟=%.3f MHz  一行=%u 像素  一帧=%u 行  行频=%u.%03u kHz  帧率=%.3f Hz\n",
           pclk_hz / 1e6, htotal, vtotal, row_hz / 1000, row_hz % 1000,
           (double)row_hz * vtotal / 1e6 * 1000);
    close(fd);
    return 0;
}
