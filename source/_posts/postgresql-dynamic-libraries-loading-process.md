---
title: "PostgreSQL 动态库加载过程"
date: 2022-07-23 11:36:29 +0800
categories: 数据库
tags:
  - PostgreSQL
---

> 在使用 pg_backtrace 插件时，必须执行 `SELECT pg_backtrace_init();`，不执行该函数插件就不生效，官方文档也特别说明了，而实际上该函数是一个空函数，为什么必须要执行该函数才生效呢？

这是一个朋友问我关于 pg_backtrace 的问题，这主要涉及到 PostgreSQL 中动态库的加载过程。本文在分析问题的基础之上，简要梳理一下 PostgreSQL 中动态库的加载过程。

<!--more-->

## 重现

首先编译安装 PostgreSQL 数据库（16devel），随后下载 [pg_backtrace](https://github.com/TsinghuaLucky912/pg_backtrace) 编译安装。接着初始化数据库并启动，最后添加 pg_backtrace 插件。

```bash
$ initdb -D testdb
$ pg_ctl -l log -D testdb start
$ psql postgres -c 'CREATE EXTENSION pg_backtrace'
```

一切准备就绪，我们来重现一下问题，使用 psql 登录数据库，并执行下面的 SQL。

```sql
postgres=# SELECT 1 / 0;
ERROR:  division by zero

postgres=# SELECT pg_backtrace_init();
 pg_backtrace_init
-------------------

(1 row)

postgres=# SELECT 1 / 0;
ERROR:  division by zero
CONTEXT:        postgres: japin postgres [local] SELECT(int4div+0x6e) [0x564f9872a279]
        postgres: japin postgres [local] SELECT(+0x386543) [0x564f983e3543]
        postgres: japin postgres [local] SELECT(ExecInterpExprStillValid+0x53) [0x564f983e56be]
        postgres: japin postgres [local] SELECT(+0x51553a) [0x564f9857253a]
        postgres: japin postgres [local] SELECT(evaluate_expr+0xa1) [0x564f9857a364]
        postgres: japin postgres [local] SELECT(+0x51c4ca) [0x564f985794ca]
        postgres: japin postgres [local] SELECT(+0x51b627) [0x564f98578627]
        postgres: japin postgres [local] SELECT(+0x518b5d) [0x564f98575b5d]
        postgres: japin postgres [local] SELECT(expression_tree_mutator+0x1500) [0x564f984ad27f]
        postgres: japin postgres [local] SELECT(+0x51af88) [0x564f98577f88]
        postgres: japin postgres [local] SELECT(expression_tree_mutator+0x197b) [0x564f984ad6fa]
        postgres: japin postgres [local] SELECT(+0x51af88) [0x564f98577f88]
        postgres: japin postgres [local] SELECT(eval_const_expressions+0x6f) [0x564f98575168]
        postgres: japin postgres [local] SELECT(+0x4ee403) [0x564f9854b403]
        postgres: japin postgres [local] SELECT(subquery_planner+0x56a) [0x564f9854a8b8]
        postgres: japin postgres [local] SELECT(standard_planner+0x2b8) [0x564f98549a86]
        postgres: japin postgres [local] SELECT(planner+0x58) [0x564f985497c4]
        postgres: japin postgres [local] SELECT(pg_plan_query+0x7f) [0x564f9868e277]
        postgres: japin postgres [local] SELECT(pg_plan_queries+0xfa) [0x564f9868e3c1]
        postgres: japin postgres [local] SELECT(+0x63179f) [0x564f9868e79f]
        postgres: japin postgres [local] SELECT(PostgresMain+0x7b5) [0x564f986933ef]
        postgres: japin postgres [local] SELECT(+0x55e0c2) [0x564f985bb0c2]
        postgres: japin postgres [local] SELECT(+0x55d9b0) [0x564f985ba9b0]
        postgres: japin postgres [local] SELECT(+0x559c28) [0x564f985b6c28]
        postgres: japin postgres [local] SELECT(PostmasterMain+0x1367) [0x564f985b63d9]
        postgres: japin postgres [local] SELECT(+0x41d5f5) [0x564f9847a5f5]
        /lib/x86_64-linux-gnu/libc.so.6(__libc_start_main+0xe7) [0x7f3feebc2c87]
        postgres: japin postgres [local] SELECT(_start+0x2a) [0x564f981282ba]
```

从上面的结果可以看到我们需要执行 `pg_backtrace()` 函数，才能在错误消息中打印出详细的堆栈信息。那么它做了什么呢？我前面已经提到了，它什么都没有做，其实现如下所示：

```c
Datum pg_backtrace_init(PG_FUNCTION_ARGS)
{
        PG_RETURN_VOID();
}
```

既然它什么都没有做，为什么前后两次的执行效果不一致呢？它必然在后面做了一些操作。

## 分析

既然是 `pg_backtrace_init()` 函数引起的不同，那么我们就针对这个函数来看看它都干了什么，我们可以通过 gdb 附加进程并在该函数打断点从而确定其调用栈。

```
(gdb) b pg_backtrace_init
Function "pg_backtrace_init" not defined.
Make breakpoint pending on future shared library load? (y or [n]) y
Breakpoint 1 (pg_backtrace_init) pending.
```

从上面的提示，您是否已经猜到答案了？如果没有请继续看下面的分析。

设置好断点之后，我们来执行 `SELECT pg_backtrace_init();`，可以看到程序在 `pg_backtrace_init()` 处停止下来，查看堆栈发现并没有什么特别的，我们在继续执行也没有什么有关 pg_backtrace 的特殊处理。这是怎么回事呢？我们在回头来看看 gdb 下断点时给出的提示信息，在当前的代码中没有找到 `pg_backtrace_init()` 函数，使断点在将来的共享库加载时挂起。我们实际上也在 `pg_backtrace_init()` 处停止下来了，那么这个动态库肯定是加载了。它又是何时加载的呢？

既然会加载动态库，我们知道 PostgreSQL 在加载动态库时会执行 `_PG_init()` 函数，我们看看 pg_backtrace 中该函数的实现。

```c
void _PG_init(void)
{
	signal_handlers[SIGSEGV] = pqsignal(SIGSEGV, backtrace_handler);
	signal_handlers[SIGBUS] = pqsignal(SIGBUS, backtrace_handler);
	signal_handlers[SIGFPE] = pqsignal(SIGFPE, backtrace_handler);
	signal_handlers[SIGINT] = pqsignal(SIGINT, backtrace_handler);
	prev_executor_run_hook = ExecutorRun_hook;
	ExecutorRun_hook = backtrace_executor_run_hook;

	prev_utility_hook = ProcessUtility_hook;
	ProcessUtility_hook = backtrace_utility_hook;

	prev_post_parse_analyze_hook = post_parse_analyze_hook;
	post_parse_analyze_hook = backtrace_post_parse_analyze_hook;

	DefineCustomEnumVariable("pg_backtrace.level",
							 "Set error level for dumping backtrace",
							 NULL,
							 &backtrace_level,
							 ERROR,
							 backtrace_level_options,
							 PGC_USERSET, 0, NULL, NULL, NULL);
}
```

它添加了三个 hook，拦截了 4 个信号，同时定义了一个配置参数。看到这里我们就能猜到为什么执行 `pg_backtrace_init()` 之后结果不一样了。空函数 `pg_backtrace_init()` 主要的作用是加载 `pg_backtracs.so` 动态库，一旦该动态库加载之后，pg_backtrace 就可以执行自定义 hook 来进行处理。这里就不在对 hook 的具体实现做分析。

```
(gdb) b _PG_init
Function "_PG_init" not defined.
Make breakpoint pending on future shared library load? (y or [n]) y
Breakpoint 1 (_PG_init) pending.
(gdb) b pg_backtrace_init
Function "pg_backtrace_init" not defined.
Make breakpoint pending on future shared library load? (y or [n]) y
Breakpoint 2 (pg_backtrace_init) pending.
```

当我们再次执行 `SELECT pg_backtrace_init()` 时，您可以看到如下的堆栈信息：

```
#0  _PG_init () at pg_backtrace.c:142
#1  0x0000564f98857ec5 in internal_load_library (
    libname=0x564f9924a198 "/mnt/workspace/postgresql/build/pg/lib/pg_backtrace.so")
    at /mnt/workspace/postgresql/build/../src/backend/utils/fmgr/dfmgr.c:289
#2  0x0000564f98857873 in load_external_function (
    filename=0x564f9924a0c8 "$libdir/pg_backtrace",
    funcname=0x564f9924a090 "pg_backtrace_init", signalNotFound=true,
    filehandle=0x7fff9a88fde8)
    at /mnt/workspace/postgresql/build/../src/backend/utils/fmgr/dfmgr.c:116
#3  0x0000564f9885963d in fmgr_info_C_lang (functionId=16385, finfo=0x564f9924a000,
    procedureTuple=0x7f3fe59defd8)
    at /mnt/workspace/postgresql/build/../src/backend/utils/fmgr/fmgr.c:400
#4  0x0000564f9885912d in fmgr_info_cxt_security (functionId=16385,
    finfo=0x564f9924a000, mcxt=0x564f99249800, ignore_security=false)
    at /mnt/workspace/postgresql/build/../src/backend/utils/fmgr/fmgr.c:248
#5  0x0000564f98858dcf in fmgr_info (functionId=16385, finfo=0x564f9924a000)
    at /mnt/workspace/postgresql/build/../src/backend/utils/fmgr/fmgr.c:128
#6  0x0000564f983dde2a in ExecInitFunc (scratch=0x7fff9a890400, node=0x564f991835f0,
    args=0x0, funcid=16385, inputcollid=0, state=0x564f99249f70)
    at /mnt/workspace/postgresql/build/../src/backend/executor/execExpr.c:2748
#7  0x0000564f983d9fda in ExecInitExprRec (node=0x564f991835f0, state=0x564f99249f70,
```

即 pg_backtrace 插件是通过 `internal_load_library()` 函数加载的，我们在 gdb 中执行
`continue`，它会执行 `pg_backtrace_init()` 函数。

```
(gdb) continue
Continuing.

Breakpoint 2, pg_backtrace_init (fcinfo=0x564f9924a058) at pg_backtrace.c:182
182             PG_RETURN_VOID();
```

分析到这里，我们已经清楚了为什么 `pg_backtrace_init()` 函数为空，而 pg_backtrace 却能在执行该函数之后输出堆栈信息了。

## 探索

根据上面的分析，要想使用使用 pg_backtrace 提供的功能，我们仅需要加载动态库即可。我们知道 PostgreSQL 提供了 `shared_preload_libraries` 和 `session_preload_libraries` 来个参数指定需要添加的动态库。其中 `shared_preload_libraries` 是所有后端进程（backend）共享的，而 `session_preload_libraries` 则是单个会话的。那我们将其添加到这个两个参数中的其中一个是否不需要执行 `pg_backtrace_init()` 函数即可使用 pg_backtrace 提供的功能呢？答案当然是不需要了。

但是，当我将其配置在 `shared_preload_libraries` 参数中时，我通过 `pg_ctl stop [-m fast]` 却不能将数据库停下，这又是为什么呢？如果使用 `pg_ctl stop -m { smart | immediate }` 则可以将数据库停下。

通过查看源码，我们知道 `pg_ctl stop [-m fast]` 实际上是发送的 `SIGINT` 信号给主进程，我们注意到 pg_backtrace 在加载时拦截了 `SIGINT` 信息，其信号处理函数如下所示：

```c
static void
backtrace_handler(SIGNAL_ARGS)
{
	inside_signal_handler = true;
	elog(LOG, "Caught signal %d", postgres_signal_arg);
	inside_signal_handler = false;
	if (postgres_signal_arg != SIGINT && signal_handlers[postgres_signal_arg])
		signal_handlers[postgres_signal_arg](postgres_signal_arg);
}
```

当遇到 `SIGINT` 信号时，pg_backtrace 直接将其忽略了，这就是为什么主进程在执行 `pg_ctl stop [-m fast]` 不能停机的原因。

那么为什么设置在 `session_preload_libraries` 中又可以呢？这就涉及到两个参数加载的时机问题以及 PostgreSQL 父子进程对于 `SIGINT` 信号的处理了。下图简要给出了这两个参数的处理流程：

{% asset_img postgres-dynamic-libraries-loading-process.png %}

PostgreSQL 在主进程中使用 `SIGINT` 作为停机的一种方式，它会其子进程发送 `SIGTERM` 信号，而子进程（不一定是所有的子进程）则使用 `SIGINT` 作为取消查询的一种方式。因此，即便我们将 pg_backtrace 设置在 `session_preload_libraries` 中，依然会导致问题。当然，只要您使用了该插件，都会遇到这个问题，要么是无法使用 `pg_ctl stop [-m fast]` 正常停机（配置在 `shared_preload_libraries` 中），要么是无法取消正在执行的查询（配置在 `session_preload_libraries` 或 `local_preload_libraries` 或者执行 `pg_backtrace_init()`）。

## 总结

从这个过程中，我们对 PostgreSQL 的动态库加载有了一个基本的认识，它提供了三种加载方式。

1. 通过 `process_shared_preload_libraries()` 全局加载。
2. 通过 `process_session_preload_libraries()` 仅在后端进程中加载。
3. 通过 `load_external_function()` 按需动态加载。

<div class="just-for-fun">
笑林广记 - 借牛

有走柬借牛于富翁者，翁方对客，讳不识字，伪启缄视之，对来使曰：“知道了，少刻我自来也。”
</div>
