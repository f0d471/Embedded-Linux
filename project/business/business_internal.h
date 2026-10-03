#ifndef __BUSINESS_INTERNAL_H
#define __BUSINESS_INTERNAL_H

/* business 层内部: 具体页面与命令执行之间的约定, 外面的层看不见。 */

#include "input/input_manager.h"
#include "page/page_manager.h"
#include "ui/ui_manager.h"

/*
 * 页面布局常量。320x240 的假屏和板上真屏都按同一套公式排:
 * 测试项按钮两列一排, "设置"按钮永远在最后一行的最后一格。
 * 判据脚本里点击坐标就按这套公式算, 改布局必须同步改判据。
 */
#define UI_MARGIN   8
#define UI_BTN_H    40
#define UI_GAP      8
#define UI_COLS     2

/* item i 在网格里的外框 */
void business_item_rect(int index, int item_count, struct disp_region *out);

/* "设置"/"返回" 按钮共用的位置: 最后一行最后一格 */
void business_prefs_rect(int item_count, struct disp_region *out);

/* 两个具体页面, 在各自的 .c 里调 page_register */
void business_main_page_register(void);
void business_settings_page_register(void);

/* 点了测试项按钮: fork+exec 跑配置里给的命令, 退出码进日志 */
void business_run_command(const char *name, const char *command);

#endif /* __BUSINESS_INTERNAL_H */
