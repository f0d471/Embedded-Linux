/* 05 章 2.2~2.3、3.3 节：假显存——WSL 里练描点、行宽和拼色。
 * 用一个普通文件冒充显存(mmap MAP_SHARED),参数全部从命令行来,
 * 这样板上任何一种模式都能在电脑上复现。
 *
 * 用法: ./fakefb <文件> <xres> <yres> <bpp> <line_length> [fix|xres] [hline|vline] [RRGGBB]
 *   例:  ./fakefb fb.raw 1024 600 32 4096                 居中 100 个红点(板上同参数)
 *        ./fakefb fb16.raw 1024 600 16 2048 fix hline FF0000   行尾有填充时画横线
 * 判据与注错(-DBUG_ROW_NO_PW / -DBUG_565_SWAP)见教程 2.3、3.5、4.5 节。
 * 编译: gcc -Wall -O2 fakefb.c -o fakefb
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

static unsigned g_bpp, g_ll, g_used_ll;
static unsigned g_roff, g_rlen, g_goff, g_glen, g_boff, g_blen;

/* 888 的一个分量:砍到 length 位,挪到 offset 位(教程 3.3) */
static unsigned pack_one(unsigned v8, unsigned off, unsigned len)
{
    return (v8 >> (8 - len)) << off;
}

static void put_pixel(unsigned char *base, unsigned x, unsigned y, unsigned color888)
{
    unsigned r = (color888 >> 16) & 0xff;
    unsigned g = (color888 >> 8) & 0xff;
    unsigned b = color888 & 0xff;
#ifdef BUG_565_SWAP
    if (g_blen == 5 && g_glen == 6) {       /* 注错:红绿的位数写反 */
        r = (r >> (8 - 6)) << g_roff;
        g = (g >> (8 - 5)) << g_goff;
        b = pack_one(b, g_boff, g_blen);    /* 蓝照旧 */
    } else
#endif
    {
        r = pack_one(r, g_roff, g_rlen);
        g = pack_one(g, g_goff, g_glen);
        b = pack_one(b, g_boff, g_blen);
    }

    unsigned long off = (unsigned long)y * g_used_ll + x * (g_bpp / 8);
#ifdef BUG_ROW_NO_PW
    off = (unsigned long)y * (g_used_ll / (g_bpp / 8)) + x * (g_bpp / 8);
#endif
    switch (g_bpp) {
    case 32: *(unsigned int *)(base + off) = r | g | b; break;
    case 16: *(unsigned short *)(base + off) = r | g | b; break;
    default: *(unsigned char *)(base + off) = r | g | b; break;
    }
}

int main(int argc, char **argv)
{
    if (argc < 6) {
        printf("Usage: %s <file> <xres> <yres> <bpp> <line_length> [fix|xres] [hline|vline] [RRGGBB]\n",
               argv[0]);
        return 1;
    }
    const char *path = argv[1];
    unsigned xres = strtoul(argv[2], NULL, 0);
    unsigned yres = strtoul(argv[3], NULL, 0);
    g_bpp = strtoul(argv[4], NULL, 0);
    g_ll = strtoul(argv[5], NULL, 0);
    const char *rowsrc = argc > 6 ? argv[6] : "fix";
    const char *pat = argc > 7 ? argv[7] : "dots";
    unsigned color888 = argc > 8 ? strtoul(argv[8], NULL, 16) : 0xFF0000;

    /* 位段:32bpp 按 xRGB8888(板上未插屏布局),16bpp 按 RGB565,8bpp 调色板不管 */
    if (g_bpp == 16) {
        g_roff = 11; g_rlen = 5; g_goff = 5; g_glen = 6; g_boff = 0; g_blen = 5;
    } else {
        g_roff = 16; g_rlen = 8; g_goff = 8; g_glen = 8; g_boff = 0; g_blen = 8;
    }
    unsigned used_ll = (strcmp(rowsrc, "xres") == 0) ? xres * g_bpp / 8 : g_ll;
    g_used_ll = used_ll;      /* put_pixel 按这个行宽定位;"xres" 模式演示行尾有填充时算错的后果 */
    unsigned long size = (unsigned long)g_ll * yres;

    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { perror("open"); return 1; }
    if (ftruncate(fd, size) != 0) {          /* 先把文件撑到显存大小,mmap 才安全 */
        perror("ftruncate");
        return 1;
    }
    unsigned char *fb = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (fb == MAP_FAILED) { perror("mmap"); return 1; }
    memset(fb, 0xff, size);                  /* 全 1 = 白,任何布局都成立 */

    if (strcmp(pat, "hline") == 0) {
        for (unsigned x = 0; x < xres; x++)
            put_pixel(fb, x, yres / 2, color888);
    } else if (strcmp(pat, "vline") == 0) {
        for (unsigned y = 0; y < yres; y++)
            put_pixel(fb, xres / 2, y, color888);
    } else {                                 /* dots:居中 100 个红点(show_pixel 同款) */
        for (unsigned i = 0; i < 100; i++)
            put_pixel(fb, xres / 2 + i, yres / 2, color888);
    }

    munmap(fb, size);
    close(fd);                               /* MAP_SHARED,close 后改动落回文件 */
    printf("xres=%u yres=%u bpp=%u line_length=%u 实际用的行宽=%u 显存=%lu 字节\n",
           xres, yres, g_bpp, g_ll, used_ll, size);
    return 0;
}
