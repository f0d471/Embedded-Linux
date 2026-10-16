/* 不运行，只编译：让编译器把结构体大小和字段偏移变成数组长度，再用 nm -S 读出来 */
#include <linux/fb.h>
#include <stddef.h>

char var_size[sizeof(struct fb_var_screeninfo)];
char fix_size[sizeof(struct fb_fix_screeninfo)];
char fix_smem_len_off[offsetof(struct fb_fix_screeninfo, smem_len)];
char fix_line_length_off[offsetof(struct fb_fix_screeninfo, line_length)];
char var_bpp_off[offsetof(struct fb_var_screeninfo, bits_per_pixel)];
