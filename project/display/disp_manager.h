#ifndef __DISP_MANAGER_H
#define __DISP_MANAGER_H

/*
 * display 层对外接口。
 * 这里只放函数声明, 不放内部结构体定义 -- 别的层看不见本层的内部状态,
 * 才谈得上以后能整层换掉。
 */

int  display_init(void);
void display_exit(void);

#endif /* __DISP_MANAGER_H */
