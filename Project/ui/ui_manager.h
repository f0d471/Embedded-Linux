#ifndef __UI_MANAGER_H
#define __UI_MANAGER_H

/*
 * ui 层对外接口。
 * 这里只放函数声明, 不放内部结构体定义 -- 别的层看不见本层的内部状态,
 * 才谈得上以后能整层换掉。
 *
 * 一个按钮的生命周期: create(挂进链表) -> draw_all(画整批) ->
 * press/release(命中则变 pressed 态并重绘; release 且命中同一颗才触发回调)
 * -> destroy(从链表摘除并释放)。
 */

struct ui_button;

/* 点击回调: 按下并在同一颗按钮内抬起才触发 */
typedef void (*ui_on_click)(struct ui_button *btn, void *ctx);

int  ui_init(void);
void ui_exit(void);

/* 坐标是按钮外框, 与显示像素同单位; 失败返回 NULL */
struct ui_button *ui_button_create(const char *label, int x, int y,
				   int w, int h,
				   ui_on_click on_click, void *ctx);
void ui_button_destroy(struct ui_button *btn);
int  ui_button_count(void);

/* 把当前所有按钮重画一遍并 flush */
void ui_button_draw_all(void);

/* 指针按下/抬起事件喂给按钮层; 命中返回 1 */
int  ui_button_press(int x, int y);
int  ui_button_release(int x, int y);

/* 单测用: 指定按钮的按下态与命中测试, 不走回调 */
int  ui_button_is_pressed(const struct ui_button *btn);
int  ui_button_hit(const struct ui_button *btn, int x, int y);

#endif /* __UI_MANAGER_H */
