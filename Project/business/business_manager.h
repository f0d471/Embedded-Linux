#ifndef __BUSINESS_MANAGER_H
#define __BUSINESS_MANAGER_H

/*
 * business 层对外接口。
 * 这里只放函数声明, 不放内部结构体定义 -- 别的层看不见本层的内部状态,
 * 才谈得上以后能整层换掉。
 *
 * business 是整个程序真正干活的地方: 读配置、选字体、注册具体页面,
 * 以及 main() 调进来的那条"取事件 -> 喂页面"的主循环。
 */

int  business_init(void);
void business_exit(void);

/* main_loop 调它; 返回时整个程序就准备退出了 */
int  business_run(void);

#endif /* __BUSINESS_MANAGER_H */
