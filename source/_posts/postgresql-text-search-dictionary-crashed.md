---
title: "PostgreSQL 文本搜索字典导致奔溃"
date: 2022-08-18 21:25:20 +0800
categories: 数据库
tags:
  - PostgreSQL
  - BUG
---

今天朋友在群里发了一个关于文本搜索字典导致崩溃的问题，如下所示：

```sql
CREATE TEXT SEARCH TEMPLATE public.my_ts_template(
  init = varchar_support,
  lexize = dispell_lexize
);

CREATE TEXT SEARCH DICTIONARY public.my_ts_dict(
  template = public.my_ts_template
);
```

在执行第二条语句时将出现如下错误信息：

```
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
The connection to the server was lost. Attempting reset: Failed.
The connection to the server was lost. Attempting reset: Failed.
```

从上面的信息可以得知后端进程奔溃了（这个问题就目前的状况来看是不会修正的）。

<!--more-->

## 分析

通过 GDB 我们可以看到崩溃时的堆栈信息如下：

```
#0  0x00005605671bce72 in varchar_support (fcinfo=0x7ffd0c87a070)
    at /home/japin/Codes/postgresql/build/../src/backend/utils/adt/varchar.c:565
#1  0x0000560567205842 in FunctionCall1Coll (flinfo=0x7ffd0c87a0d0, collation=0, arg1=0)
    at /home/japin/Codes/postgresql/build/../src/backend/utils/fmgr/fmgr.c:1124
#2  0x000056056720675d in OidFunctionCall1Coll (functionId=3097, collation=0, arg1=0)
    at /home/japin/Codes/postgresql/build/../src/backend/utils/fmgr/fmgr.c:1402
#3  0x0000560566d650ad in verify_dictoptions (tmplId=24576, dictoptions=0x0)
    at /home/japin/Codes/postgresql/build/../src/backend/commands/tsearchcmds.c:381
#4  0x0000560566d652d1 in DefineTSDictionary (names=0x5605678ad4d8, parameters=0x5605678ad720)
    at /home/japin/Codes/postgresql/build/../src/backend/commands/tsearchcmds.c:442
#5  0x0000560567042a96 in ProcessUtilitySlow (pstate=0x5605678cd940, pstmt=0x5605678adae8,
    queryString=0x5605678aca10 "CREATE TEXT SEARCH DICTIONARY public.my_ts_dict (\n  template = public.my_ts_template\n);", context=PROCESS_UTILITY_TOPLEVEL, params=0x0, queryEnv=0x0, dest=0x5605678adbd8, qc=0x7ffd0c87aa40)
    at /home/japin/Codes/postgresql/build/../src/backend/tcop/utility.c:1430
#6  0x0000560567041e84 in standard_ProcessUtility (pstmt=0x5605678adae8,
    queryString=0x5605678aca10 "CREATE TEXT SEARCH DICTIONARY public.my_ts_dict (\n  template = public.my_ts_template\n);", readOnlyTree=false, context=PROCESS_UTILITY_TOPLEVEL, params=0x0, queryEnv=0x0, dest=0x5605678adbd8,
    qc=0x7ffd0c87aa40) at /home/japin/Codes/postgresql/build/../src/backend/tcop/utility.c:1074
#7  0x0000560567040dfe in ProcessUtility (pstmt=0x5605678adae8,
    queryString=0x5605678aca10 "CREATE TEXT SEARCH DICTIONARY public.my_ts_dict (\n  template = public.my_ts_template\n);", readOnlyTree=false, context=PROCESS_UTILITY_TOPLEVEL, params=0x0, queryEnv=0x0, dest=0x5605678adbd8,
    qc=0x7ffd0c87aa40) at /home/japin/Codes/postgresql/build/../src/backend/tcop/utility.c:530
#8  0x000056056703f905 in PortalRunUtility (portal=0x56056791eed0, pstmt=0x5605678adae8, isTopLevel=true,
    setHoldSnapshot=false, dest=0x5605678adbd8, qc=0x7ffd0c87aa40)
    at /home/japin/Codes/postgresql/build/../src/backend/tcop/pquery.c:1158
#9  0x000056056703fb77 in PortalRunMulti (portal=0x56056791eed0, isTopLevel=true, setHoldSnapshot=false,
    dest=0x5605678adbd8, altdest=0x5605678adbd8, qc=0x7ffd0c87aa40)
    at /home/japin/Codes/postgresql/build/../src/backend/tcop/pquery.c:1315
#10 0x000056056703eff5 in PortalRun (portal=0x56056791eed0, count=9223372036854775807, isTopLevel=true,
    run_once=true, dest=0x5605678adbd8, altdest=0x5605678adbd8, qc=0x7ffd0c87aa40)
    at /home/japin/Codes/postgresql/build/../src/backend/tcop/pquery.c:791
#11 0x0000560567038332 in exec_simple_query (
    query_string=0x5605678aca10 "CREATE TEXT SEARCH DICTIONARY public.my_ts_dict (\n  template = public.my_ts_template\n);") at /home/japin/Codes/postgresql/build/../src/backend/tcop/postgres.c:1243
#12 0x000056056703ce29 in PostgresMain (dbname=0x5605678a7168 "postgres", username=0x5605678d8d18 "japin")
    at /home/japin/Codes/postgresql/build/../src/backend/tcop/postgres.c:4505
#13 0x0000560566f64bd0 in BackendRun (port=0x5605678d4c60)
    at /home/japin/Codes/postgresql/build/../src/backend/postmaster/postmaster.c:4491
#14 0x0000560566f644be in BackendStartup (port=0x5605678d4c60)
    at /home/japin/Codes/postgresql/build/../src/backend/postmaster/postmaster.c:4219
#15 0x0000560566f60730 in ServerLoop ()
    at /home/japin/Codes/postgresql/build/../src/backend/postmaster/postmaster.c:1809
#16 0x0000560566f5fee1 in PostmasterMain (argc=1, argv=0x5605678a5120)
    at /home/japin/Codes/postgresql/build/../src/backend/postmaster/postmaster.c:1481
#17 0x0000560566e234d2 in main (argc=1, argv=0x5605678a5120)
    at /home/japin/Codes/postgresql/build/../src/backend/main/main.c:197
```

从上面的堆栈中，我们可以得知在 `DefineTSDictionary()` 函数中 `dictoptions` 变量为 `NIL`（即空链表），在传入到 `varchar_support()` 函数中时并没有检查空值，从而导致崩溃。

问题是找到了，但是这个问题并没有得到认同，Tom Lane 指出 `varchar_support()` 并不是有效的 `init` 参数。随后，我又重新查看了[文档](https://www.postgresql.org/docs/devel/sql-createtstemplate.html)，发现这个点在文档里面有说明。

> You must be a superuser to use CREATE TEXT SEARCH TEMPLATE. This restriction is made because an erroneous text search template definition could confuse or even crash the server.

我尝试在 `verify_dictoptions()` 函数中判断 `dictoptions` 是否为 `NIL` 来规避这个问题，这种做法并没有得到认同，诚然，通过检查 `dictoptions` 是否为 `NIL` 可以避免崩溃，但是这也就意味者我们必须为 `CREATE TEXT SEARCH DICTIONARY` 指定选项（这并不是预期的行为）。

目前更倾向的做法是超级用户来确保 `CREATE TEXT SEARCH TEMPLATE` 语句中 `init` 参数的合法性。然而在我看来这种解决方案并不十分优雅。这就相当于是给 DBA 埋了一个定时炸弹，您不知道他何时会由何人引爆。

## 参考

[1] https://www.postgresql.org/docs/devel/sql-createtstemplate.html
[2] https://www.postgresql.org/docs/devel/sql-createtsdictionary.html
[3] [Coredump with text search dictionary](https://www.postgresql.org/message-id/MEYP282MB16690107AAF04EBB3B9AADD8B6629@MEYP282MB1669.AUSP282.PROD.OUTLOOK.COM)

<div class="just-for-fun">
笑林广记 - 不愿富

一鬼托生时，冥王判作富人。
鬼曰：“不愿富也，但求一生衣食不缺，无是无非，烧清香，吃苦茶，安闲过日足矣。”
冥王曰：“要银子便再与你几万，这样安闲清福，却不许你享。”
</div>
