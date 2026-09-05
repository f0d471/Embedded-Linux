#ifndef __INPUT_MANAGER_H
#define __INPUT_MANAGER_H

/*
 * input 层对外接口。
 * 这里只放函数声明, 不放内部结构体定义 -- 别的层看不见本层的内部状态,
 * 才谈得上以后能整层换掉。
 */

int  input_init(void);
void input_exit(void);

#endif /* __INPUT_MANAGER_H */
