#ifndef __PAGE_MANAGER_H
#define __PAGE_MANAGER_H

#include "input/input_manager.h"

/*
 * page 层对外接口。
 * 这里只放函数声明, 不放内部结构体定义 -- 别的层看不见本层的内部状态,
 * 才谈得上以后能整层换掉。
 *
 * 一个页面 = 一份 ops: create(建控件画整页) / destroy(释放全部资源) /
 * on_event(收当前页该处理的输入事件)。切换页面时旧页 destroy 新页 create,
 * 没有第三种状态。
 */

struct page_ops {
	const char *name;
	int  (*create)(void);
	void (*destroy)(void);
	void (*on_event)(const struct input_event_data *ev);
	struct page_ops *next;   /* 注册链表指针, page_register 维护 */
};

int  page_init(void);
void page_exit(void);

int  page_register(struct page_ops *ops);
int  page_switch(const char *name);
void page_dispatch(const struct input_event_data *ev);
const char *page_current_name(void);

#endif /* __PAGE_MANAGER_H */
