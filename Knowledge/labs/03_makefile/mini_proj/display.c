#include <stdio.h>
#include "config.h"       /* 关键的一条边:display.o 依赖 config.h。
                             教程 03 篇第 5 节"改了 .h 却不重编"的坑就埋在这里 */
#include "display.h"

void print_banner(void)
{
    printf("%s\n", BANNER_TEXT);
}
