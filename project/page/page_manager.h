#ifndef __PAGE_MANAGER_H
#define __PAGE_MANAGER_H

/*
 * page 层对外接口。
 * 这里只放函数声明, 不放内部结构体定义 -- 别的层看不见本层的内部状态,
 * 才谈得上以后能整层换掉。
 */

int  page_init(void);
void page_exit(void);

#endif /* __PAGE_MANAGER_H */
