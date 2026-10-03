#include <string.h>

#include "common.h"
#include "page/page_manager.h"

/*
 * 页面管理器只做三件事: 收注册、切页、把事件递给当前页。
 * 页面上有什么按钮、按钮点了干什么, 全是具体页面(在 business 层)自己的事。
 */

static struct page_ops *g_list;
static struct page_ops *g_cur;
static int g_inited;

int page_init(void)
{
	if (g_inited)
		return ERR_OK;
	g_list = NULL;
	g_cur = NULL;
	g_inited = 1;
	LOG_INFO("page init OK");
	return ERR_OK;
}

void page_exit(void)
{
	if (!g_inited)
		return;
	if (g_cur != NULL && g_cur->destroy != NULL)
		g_cur->destroy();
	g_cur = NULL;
	g_list = NULL;
	g_inited = 0;
	LOG_INFO("page exit OK");
}

int page_register(struct page_ops *ops)
{
	if (ops == NULL || ops->name == NULL)
		return ERR_PARAM;
	ops->next = g_list;
	g_list = ops;
	return ERR_OK;
}static struct page_ops *page_find(const char *name)
{
	struct page_ops *p;

	for (p = g_list; p != NULL; p = p->next)
		if (strcmp(p->name, name) == 0)
			return p;
	return NULL;
}

int page_switch(const char *name)
{
	struct page_ops *p;
	int ret;

	if (!g_inited)
		return ERR_NOTSUP;
	p = page_find(name);
	if (p == NULL)
		return ERR_NOTFOUND;
	if (p == g_cur)
		return ERR_OK;

	if (g_cur != NULL && g_cur->destroy != NULL)
		g_cur->destroy();
	g_cur = p;
	ret = p->create != NULL ? p->create() : ERR_OK;
	if (ret != ERR_OK)
		LOG_ERR("page %s create failed: %s", p->name, err_str(ret));
	else
		LOG_INFO("page %s created", p->name);
	return ret;
}

void page_dispatch(const struct input_event_data *ev)
{
	if (g_cur != NULL && g_cur->on_event != NULL)
		g_cur->on_event(ev);
}

const char *page_current_name(void)
{
	return g_cur != NULL ? g_cur->name : NULL;
}
