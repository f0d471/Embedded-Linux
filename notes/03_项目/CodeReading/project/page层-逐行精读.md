# page 层逐行精读

代码路径与总行数（`grep -n ''` 于 2026-10-04 核对）：
`page/page_manager.c`（88 行）+ `page/page_manager.h`（32 行）。

前置知识：注册链表形状已在 display/input 篇反复出现，本篇不再重复。
文件定位：层表第五层，依赖 ui（页面画控件）与 input（事件结构体）。
消费者：business 层两个具体页面（注册与切换）、`unittest/page_test`。

## page_manager.h：对外接口

```c
// page/page_manager.h  [7-30] 正文
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
```

页面的全部职责压缩成三份函数指针：create 建控件画整页、destroy 释放
全部资源、on_event 收当前页该处理的事件。`next` 是侵入式链表指针，
与 `disp_ops`/`input_provider` 同型——第 05 章立的形状，这里是它的
第四个实例。

## page_manager.c

### [11-36] 状态与启停

```c
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
```

exit 销毁当前页再清注册表——页面在 business 层，业务退出顺序
（business_exit 先于 page_exit）不负责控件，控件归 page 层收尾。
`create` 可以是 NULL 吗？`page_switch` 里补了同样判断，本仓的两个
页面都实现了 create；留着判断是给未来的"无界面过渡页"。

### [38-53] 注册与查找

```c
int page_register(struct page_ops *ops)
{
	if (ops == NULL || ops->name == NULL)
		return ERR_PARAM;
	ops->next = g_list;
	g_list = ops;
	return ERR_OK;
}

static struct page_ops *page_find(const char *name)
{
	struct page_ops *p;

	for (p = g_list; p != NULL; p = p->next)
		if (strcmp(p->name, name) == 0)
			return p;
	return NULL;
}
```

与 display/input 的注册函数逐行同型，区别只有返回值：page_register
带错误码，因为 business 在 init 里调用它时可以失败回滚。

### [55-88] 切换与分发

```c
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
```

切换的三条早退：未初始化、名字不存在、已经是当前页（幂等）。真正的
切换只有两步：destroy 旧的、create 新的——没有"暂停"状态，没有
双页并存。create 失败时 `g_cur` 已指向新页，返回错误码给调用方决策；
页面栈、动画过渡、创建重试都不在本层的职责里。

## 执行顺序

| 步 | 成功路径（main→settings→main） | 失败路径 |
|---|---|---|
| switch("settings") | main.destroy() → g_cur=settings → settings.create() | 名字拼错 → ERR_NOTFOUND，当前页不动 |
| dispatch(pointer) | settings.on_event(ev) | 无当前页 → 静默（init 阶段） |
| switch("main") | settings.destroy() → main.create() | create 失败 → g_cur 已切，错误上报 |
| exit | 当前页 destroy → 链表清空 | 未 init → 早退 |

## 容易读错的地方

1. **switch 到当前页是成功而不是错误**：重复点击"设置"按钮不会反复
   销毁重建，幂等返回 `ERR_OK`。判据 [21] 里"settings created 只出现
   1 次"依赖这条。
2. **create 失败后 g_cur 指向新页**：页面创建到一半失败，当前页已切，
   旧页已销毁——调用方拿到错误码时屏幕可能停在半成品上，这是已知的
   简化，页面的 create 自己保证"要么全成要么没动过"（主页的实现里
   有 fail 标签兜底）。
3. **dispatch 不排队**：事件来了直接进当前页，page 层没有自己的队列；
   排队发生在 input 层的环形队列，两层各管一段。

## 消费者清单

| 消费者 | 用到的接口 |
|---|---|
| business/business_main_page.c | `page_register`、`page_switch("settings")` |
| business/business_settings_page.c | `page_register`、`page_switch("main")` |
| business/business_manager.c | `page_switch("main")`（起手页）、`page_dispatch`（主循环） |
| unittest/page_test.c | 全部接口 |
