---
title: "PostgreSQL auto_explain 插件内存泄露"
date: 2021-02-03 19:48:39 +0800
category: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

最近看到 PostgreSQL 邮件列表中有人说 auto_explain 插件在特定情况下会导致 OOM 问题，经过一番分析发现原来是由于内存上下文的问题导致的。目前该泄露已经修复，并合并到代码库中。

{% asset_img fix_memory_leak_in_auto_explain.png %}

<!-- more -->

## 重现

首先我们来看看如何重现这个问题。首先，我们需要一个已运行的 PostgreSQL 数据库服务器。

```
$ psql postgres -c 'ALTER SYSTEM SET shared_preload_libraries TO auto_explain;'
$ pg_ctl restart
$ psql postgres -c 'ALTER SYSTEM SET auto_explain.log_min_duration TO 0;'
$ psql postgres -c 'ALTER SYSTEM SET auto_explain.log_nested_statements TO on;'
$ pg_ctl restart
```

接着，我们通过 psql 连接数据库，并创建如下函数。

``` sql
CREATE OR REPLACE FUNCTION gibberish(int) RETURNS text
LANGUAGE SQL AS $_$
SELECT left(string_agg(md5(random()::text),$$$$),$1) FROM generate_series(0,$1/32)
$_$;
```

接着我们执行下面的查询命令。

``` sql
SELECT
    x, md5(random()::text) as t11,
    gibberish(1500) as t12
FROM
    generate_series(1,20e6) f(x);
```

这个为了简化我省略了 `CREATE TABLE j1 AS`，因为这个不是内存泄露的关键。在执行上述命令的时候，我们可以通过 `top -p <pid>` 去观察，发现确实是内存一直在增长。

## 分析

为了缩写范围，我尝试将 auto_explain 插件移除，并执行上面的查询，发现内存并不会增长。那么内存泄露的问题就被缩小到了 auto_explain 代码中了，通过查看 auto_explain 源码，我发现这里面有两个地方会显示的调用内存分配 `explain_ExecutorStart()` 函数和 `explain_ExecutorEnd()`。该 bug 的发现者指出该内存泄露是发生在 SQL function 内存上下文中，经过调试我发现确实在执行 `explain_ExecutorEnd()` 函数时该内存上下文为 SQL function。

那么 SQL function 的内存上下文是什么时候创建的呢？通过查找，我发现它是在 `src/backend/executor/functions.c` 文件中的 `init_sql_fcache()` 函数中创建的。然而，在调用函数时 `fmgr_sql()` 函数中有如下注释。

``` c
Datum
fmgr_sql(PG_FUNCTION_ARGS)
{
    ...

    if (fcache == NULL)
    {
        init_sql_fcache(fcinfo, PG_GET_COLLATION(), lazyEvalOK);
        fcache = (SQLFunctionCachePtr) fcinfo->flinfo->fn_extra;
    }

    /*
     * Switch to context in which the fcache lives.  This ensures that our
     * tuplestore etc will have sufficient lifetime.  The sub-executor is
     * responsible for deleting per-tuple information.  (XXX in the case of a
     * long-lived FmgrInfo, this policy represents more memory leakage, but
     * it's not entirely clear where to keep stuff instead.)
     */
    oldcontext = MemoryContextSwitchTo(fcache->fcontext);

    ...
}
```

这里可以看到，SQL function 的内存上下文可能会存在较长的生命周期，那么我们频繁的在该内存上下文上分配内存，就有可能导致内存泄露，而 `explain_ExecutorEnd()` 函数执行时的内存上下文就是在 SQL function 内存上下文中，对于相对简单的查询，可能这并不会有什么问题，这也是这个内存泄露没有被即使发现的原因，当我们执行上面的查询时这个问题就暴露出来了。

__备注：__ 这里的内存泄露主要是 `explain_ExecutorEnd()` 函数中 `ExplainState` 结构的分配导致的。

## 解决

那么这个问题这么解决呢？在分析了之后，我发现这个内存的分配其实在执行完 `ExecutorEnd()` 之后就不再需要了，因此我们可以将其放在每个查询的内存上下文中（即 `queryDesc->estate->es_query_cxt` 中），那么每次执行完之后该内存就被回收了，从而避免了内存泄露。

```
diff --git a/contrib/auto_explain/auto_explain.c b/contrib/auto_explain/auto_explain.c
index faa6231d87..445bb37191 100644
--- a/contrib/auto_explain/auto_explain.c
+++ b/contrib/auto_explain/auto_explain.c
@@ -371,8 +371,15 @@ explain_ExecutorEnd(QueryDesc *queryDesc)
 {
 	if (queryDesc->totaltime && auto_explain_enabled())
 	{
+		MemoryContext oldcxt;
 		double		msec;

+		/*
+		 * Make sure we operate in the per-query context, so any cruft will be
+		 * discarded later during ExecutorEnd.
+		 */
+		oldcxt = MemoryContextSwitchTo(queryDesc->estate->es_query_cxt);
+
 		/*
 		 * Make sure stats accumulation is done.  (Note: it's okay if several
 		 * levels of hook all do this.)
@@ -424,9 +431,9 @@ explain_ExecutorEnd(QueryDesc *queryDesc)
 					(errmsg("duration: %.3f ms  plan:\n%s",
 							msec, es->str->data),
 					 errhidestmt(true)));
-
-			pfree(es->str->data);
 		}
+
+		MemoryContextSwitchTo(oldcxt);
 	}

 	if (prev_ExecutorEnd)
```

## 链接

[1] [memory leak in auto_explain](https://www.postgresql.org/message-id/CAMkU%3D1wCVtbeRn0s9gt12KwQ7PLXovbpM8eg25SYocKW3BT4hg%40mail.gmail.com)
