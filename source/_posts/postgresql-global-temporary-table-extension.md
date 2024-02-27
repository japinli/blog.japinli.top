---
title: "PostgreSQL 全局临时表 - pgtt 问题"
date: 2023-12-22 15:29:16
categories: 数据库
tags:
  - PostgreSQL
  - pgtt
---

{% asset_img pgtt.jpg %}

PostgresQL 数据库目前不支持全局临时表，当在迁移 Oracle 数据库时，经常会遇到全局临时表的问题，因此，基本上都会借助 [pgtt](https://github.com/darold/pgtt) 来解决这个问题。最近在折腾这个插件时发现了一些问题，本文对这些问题进行了整理。

<!--more-->

## 参数重定义

这个问题确实是由于我使用不当遇到的。当我在使用 `LOAD 'pgtt';` 加载插件时，由于没有在数据库上执行 `CREATE EXTENSION pgtt;`，当第二次及其之后执行就会遇到这个问题，如下所示：

```psql
postgres=# -- Session 1
postgres=# \dx
                 List of installed extensions
  Name   | Version |   Schema   |         Description
---------+---------+------------+------------------------------
 plpgsql | 1.0     | pg_catalog | PL/pgSQL procedural language
(1 row)

postgres=# LOAD 'pgtt';
ERROR:  extension "pgtt" does not exist
postgres=# LOAD 'pgtt';
ERROR:  attempt to redefine parameter "pgtt.enabled"
```

我们尝试在 `Session 2` 中创建 `pgtt` 插件。

```psql
postgres=# -- Session 2
postgres=# CREATE EXTENSION pgtt;
CREATE EXTENSION
```

随后，回到 `Session 1` 中再次加载 `pgtt`，仍然会遇到参数重定义的问题。

```psql
postgres=# -- Session 1
postgres=# \dx
                                   List of installed extensions
  Name   | Version |   Schema    |                          Description
---------+---------+-------------+----------------------------------------------------------------
 pgtt    | 3.0.0   | pgtt_schema | Extension to add Global Temporary Tables feature to PostgreSQL
 plpgsql | 1.0     | pg_catalog  | PL/pgSQL procedural language
(2 rows)

postgres=# LOAD 'pgtt';
ERROR:  attempt to redefine parameter "pgtt.enabled"
```

经分析，这是由于 `pgtt` 在定义参数之后，创建内部的哈希表时发现没有安装 `pgtt` 插件而终止导致的。当 `LOAD` 失败的时候，由于 `pgtt.enabled` 参数已经定义，并且没有删除，从而导致该问题。

可以使用下面的命令对其进行验证。

```psql
postgres=# -- Session 3
postgres=# DROP EXTENSION pgtt;
DROP EXTENSION
postgres=# \dx
                 List of installed extensions
  Name   | Version |   Schema   |         Description
---------+---------+------------+------------------------------
 plpgsql | 1.0     | pg_catalog | PL/pgSQL procedural language
(1 row)

postgres=# SHOW pgtt.enabled;
ERROR:  unrecognized configuration parameter "pgtt.enabled"
postgres=# LOAD 'pgtt';
ERROR:  extension "pgtt" does not exist
postgres=# SHOW pgtt.enabled;
 pgtt.enabled
--------------
 on
(1 row)

postgres=# LOAD 'pgtt';
ERROR:  attempt to redefine parameter "pgtt.enabled"
```

接着我们来看看源码实现。

```c
void
_PG_init(void)
{
    [...]

    /*
     * Define (or redefine) custom GUC variables.
     * No custom GUC variable at this time
     */
    DefineCustomBoolVariable("pgtt.enabled",
                             "Enable use of Global Temporary Table",
                             "By default the extension is automatically enabled after load, "
                             "it can be temporary disable by setting the GUC value to false "
                             "then enable again later wnen necessary.",
                             &pgtt_is_enabled,
                             true,
                             PGC_USERSET,
                             0,
                             NULL,
                             NULL,
                             NULL);

    if (GttHashTable == NULL)
    {
        /* Initialize list of Global Temporary Table */
        EnableGttManager();

        /*
         * Load temporary table definition from pg_global_temp_tables table
         * into our Hash table and pre-create the temporary tables.
         */
        gtt_load_global_temporary_tables();
    }

    [...]
}
```

其中 `EnableGttManager()` 函数会调用 `get_extension_oid()` 来获取扩展的 `Oid`，由于 `pgtt` 插件没有安装，因此这里会抛出错误（`extension "pgtt" does not exist`），但是由于 `DefineCustomBoolVariable()` 先于 `EnableGttManager()` 调用，因此当再次执行 `LOAD 'pgtt'` 时就会遇到参数重定义问题。

一般的写法是将插件的参数定义放置在最后（注册钩子之前），下面的 patch 可用于解决上述问题。

```diff
From fa975e7651c1fb41ada7bf74a0765c5e59079104 Mon Sep 17 00:00:00 2001
From: Japin Li <jianping.li@ww-it.cn>
Date: Wed, 20 Dec 2023 15:52:46 +0800
Subject: [PATCH] Avoid redefining parameter

---
 pgtt.c | 34 +++++++++++++++++-----------------
 1 file changed, 17 insertions(+), 17 deletions(-)

diff --git a/pgtt.c b/pgtt.c
index dfa580a..9beb604 100755
--- a/pgtt.c
+++ b/pgtt.c
@@ -257,23 +257,6 @@ _PG_init(void)
 				 errhint("Use \"LOAD 'pgtt';\" in the running session instead.")));
 	}

-	/*
- 	 * Define (or redefine) custom GUC variables.
-	 * No custom GUC variable at this time
-	 */
-	DefineCustomBoolVariable("pgtt.enabled",
-							"Enable use of Global Temporary Table",
-							"By default the extension is automatically enabled after load, "
-							"it can be temporary disable by setting the GUC value to false "
-							"then enable again later wnen necessary.",
-							&pgtt_is_enabled,
-							true,
-							PGC_USERSET,
-							0,
-							NULL,
-							NULL,
-							NULL);
-
 	if (GttHashTable == NULL)
 	{
 		/* Initialize list of Global Temporary Table */
@@ -292,6 +275,23 @@ _PG_init(void)
 	 */
 	force_pgtt_namespace();

+	/*
+	 * Define (or redefine) custom GUC variables.
+	 * No custom GUC variable at this time
+	 */
+	DefineCustomBoolVariable("pgtt.enabled",
+							"Enable use of Global Temporary Table",
+							"By default the extension is automatically enabled after load, "
+							"it can be temporary disable by setting the GUC value to false "
+							"then enable again later wnen necessary.",
+							&pgtt_is_enabled,
+							true,
+							PGC_USERSET,
+							0,
+							NULL,
+							NULL,
+							NULL);
+
 	/*
 	 * Install hooks.
 	 */
```

## 回归测试失败

这个问题其实是比较严重的，但是我不知道为什么其他人没有遇到这个问题，不知道是否是我没使用对:(。

```bash
$ make installcheck
/home/japin/Codes/postgres/build/pg/lib/pgxs/src/makefiles/../../src/test/regress/pg_regress --inputdir=./ --bindir='/home/japin/Codes/postgres/build/pg/bin'    --inputdir=test --dbname=contrib_regression 00_init 01_oncommitdelete 02_oncommitpreserve 03_createontruncate 04_rename 05_useindex 06_createas 07_createlike 08_plplgsql 09_transaction 10_foreignkey 11_after_error 12_droptable
(using postmaster on Unix socket, default port)
============== dropping database "contrib_regression" ==============
DROP DATABASE
============== creating database "contrib_regression" ==============
CREATE DATABASE
ALTER DATABASE
============== running regression test queries        ==============
test 00_init                      ... ok           77 ms
test 01_oncommitdelete            ... FAILED (test process exited with exit code 2)      208 ms
test 02_oncommitpreserve          ... FAILED (test process exited with exit code 2)       24 ms
test 03_createontruncate          ... FAILED (test process exited with exit code 2)        6 ms
test 04_rename                    ... FAILED (test process exited with exit code 2)        5 ms
test 05_useindex                  ... FAILED (test process exited with exit code 2)        4 ms
test 06_createas                  ... FAILED (test process exited with exit code 2)        4 ms
test 07_createlike                ... FAILED (test process exited with exit code 2)        4 ms
test 08_plplgsql                  ... FAILED (test process exited with exit code 2)        4 ms
test 09_transaction               ... FAILED (test process exited with exit code 2)        8 ms
test 10_foreignkey                ... FAILED (test process exited with exit code 2)        8 ms
test 11_after_error               ... FAILED (test process exited with exit code 2)        5 ms
test 12_droptable                 ... FAILED (test process exited with exit code 2)        5 ms

========================
 12 of 13 tests failed.
========================

The differences that caused some tests to fail can be viewed in the
file "/home/japin/Codes/pg-extensions/pgtt/regression.diffs".  A copy of the test summary that you see
above is saved in the file "/home/japin/Codes/pg-extensions/pgtt/regression.out".
```

下面是一个复现的示例（基于 [90f6de7d98](https://github.com/darold/pgtt/tree/90f6de7d98931d4418190644eb8d15a4754b0930)，PostgreSQL 12-15 版本）。

```psql
postgres=# CREATE EXTENSION pgtt;
CREATE EXTENSION
postgres=# LOAD 'pgtt';
LOAD
postgres=# CREATE /* GLOBAL */ TEMPORARY TABLE t01 (id int, info text) ON COMMIT DELETE ROWS;
CREATE TABLE
postgres=# SELECT oid, relname FROM pg_class WHERE relname = 't01';
  oid  | relname
-------+---------
 16405 | t01
(1 row)
postgres=# BEGIN;
BEGIN
postgres=# INSERT INTO t01 VALUES (1, 'hello');
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
The connection to the server was lost. Attempting reset: Failed.
The connection to the server was lost. Attempting reset: Failed.
: !?>
```

通过 GDB 调试，我们可以发现这个是由于在临时表上没有获取到相应的锁导致的问题。

```gdb
Program received signal SIGABRT, Aborted.
__pthread_kill_implementation (no_tid=0, signo=6, threadid=139753404450048) at ./nptl/pthread_kill.c:44
44      ./nptl/pthread_kill.c: No such file or directory.
(gdb) bt
#0  __pthread_kill_implementation (no_tid=0, signo=6, threadid=139753404450048)
    at ./nptl/pthread_kill.c:44
#1  __pthread_kill_internal (signo=6, threadid=139753404450048)
    at ./nptl/pthread_kill.c:78
#2  __GI___pthread_kill (threadid=139753404450048, signo=signo@entry=6)
    at ./nptl/pthread_kill.c:89
#3  0x00007f1adf242476 in __GI_raise (sig=sig@entry=6) at ../sysdeps/posix/raise.c:26
#4  0x00007f1adf2287f3 in __GI_abort () at ./stdlib/abort.c:79
#5  0x000056514cb804a4 in ExceptionalCondition (
    conditionName=0x56514cd1bd78 "rte->rellockmode == AccessShareLock || CheckRelationLockedByMe(rel, rte->rellockmode, false)", errorType=0x56514cd1baee "FailedAssertion",
    fileName=0x56514cd1bc58 "/home/japin/Codes/postgres/build/../src/backend/executor/execUtils.c", lineNumber=812)
    at /home/japin/Codes/postgres/build/../src/backend/utils/error/assert.c:69
#6  0x000056514c74a6dc in ExecGetRangeTableRelation (estate=0x56514df2f0b0, rti=1)
    at /home/japin/Codes/postgres/build/../src/backend/executor/execUtils.c:812
#7  0x000056514c74a743 in ExecInitResultRelation (estate=0x56514df2f0b0,
    resultRelInfo=0x56514df2f540, rti=1)
    at /home/japin/Codes/postgres/build/../src/backend/executor/execUtils.c:845
#8  0x000056514c783e92 in ExecInitModifyTable (node=0x56514dee4168,
    estate=0x56514df2f0b0, eflags=0)
    at /home/japin/Codes/postgres/build/../src/backend/executor/nodeModifyTable.c:3986
#9  0x000056514c73f87f in ExecInitNode (node=0x56514dee4168, estate=0x56514df2f0b0,
    eflags=0)
    at /home/japin/Codes/postgres/build/../src/backend/executor/execProcnode.c:177
#10 0x000056514c73469a in InitPlan (queryDesc=0x56514defb670, eflags=0)
    at /home/japin/Codes/postgres/build/../src/backend/executor/execMain.c:938
#11 0x000056514c73351b in standard_ExecutorStart (queryDesc=0x56514defb670, eflags=0)
    at /home/japin/Codes/postgres/build/../src/backend/executor/execMain.c:265
#12 0x00007f1adfb35832 in gtt_ExecutorStart (queryDesc=0x56514defb670, eflags=0)
    at pgtt.c:1010
#13 0x000056514c73322e in ExecutorStart (queryDesc=0x56514defb670, eflags=0)
    at /home/japin/Codes/postgres/build/../src/backend/executor/execMain.c:142
#14 0x000056514c9b0eed in ProcessQuery (plan=0x56514dee60e8,
    sourceText=0x56514de07470 "INSERT INTO t01 VALUES (1, 'hello');", params=0x0,
    queryEnv=0x0, dest=0x56514dee61d8, qc=0x7fff3eed4610)
    at /home/japin/Codes/postgres/build/../src/backend/tcop/pquery.c:155
#15 0x000056514c9b2afe in PortalRunMulti (portal=0x56514de78760, isTopLevel=true,
    setHoldSnapshot=false, dest=0x56514dee61d8, altdest=0x56514dee61d8,
    qc=0x7fff3eed4610)
    at /home/japin/Codes/postgres/build/../src/backend/tcop/pquery.c:1277
#16 0x000056514c9b1fdf in PortalRun (portal=0x56514de78760, count=9223372036854775807,
    isTopLevel=true, run_once=true, dest=0x56514dee61d8, altdest=0x56514dee61d8,
(gdb) f 6
#6  0x000056514c74a6dc in ExecGetRangeTableRelation (estate=0x56514df2f0b0, rti=1)
    at /home/japin/Codes/postgres/build/../src/backend/executor/execUtils.c:812
812                             Assert(rte->rellockmode == AccessShareLock ||
(gdb) list
807                              * Assert inside table_open that insists on holding some lock, it
808                              * seems sufficient to check this only when rellockmode is higher
809                              * than the minimum.
810                              */
811                             rel = table_open(rte->relid, NoLock);
812                             Assert(rte->rellockmode == AccessShareLock ||
813                                        CheckRelationLockedByMe(rel, rte->rellockmode, false));
814                     }
815                     else
816                     {
(gdb) p rte->rellockmode
$1 = 3       <-- RowExclusiveLock
(gdb) p rel->rd_node
$4 = {spcNode = 1663, dbNode = 5, relNode = 24578}
```

这里 `rte->rellockmode == RowExclusiveLock` 并且当前没有获取到相应的锁，因此导致上述错误。`rte->rellockmode` 的 `RowExclusiveLock` 来自于 `INSERT INTO t01 VALUES (1, 'hello');` 但它是在全局临时表 `t01`（`16405`）上获取的，并没有在局部临时表（`24578`）上获取。这说明 `pgtt` 在路由表的时候没有将表对象上的锁路由到对应的局部临时表上。临时表的路由逻辑在函数 [`gtt_post_parse_analyze()`](https://github.com/darold/pgtt/blob/90f6de7d98931d4418190644eb8d15a4754b0930/pgtt.c#L1715) 中，下面摘取关键部分：

```c
static void
#if PG_VERSION_NUM >= 140000
gtt_post_parse_analyze(ParseState *pstate, Query *query, struct JumbleState * jstate)
#else
gtt_post_parse_analyze(ParseState *pstate, Query *query)
#endif
{
    [...]

				if (rte->relid != gtt.temp_relid)
				{
#if PG_VERSION_NUM >= 160000
					RTEPermissionInfo *rteperm = list_nth(query->rteperminfos,
											rte->perminfoindex - 1);

					rte->relid = gtt.temp_relid;
					rteperm->relid = gtt.temp_relid;
					if (rte->rellockmode != AccessShareLock)
						LockRelationOid(rte->relid, rte->rellockmode);
#endif
					elog(DEBUG1, "rerouting relid %d access to %d for GTT table \"%s\"", rte->relid, gtt.temp_relid, name);
					rte->relid = gtt.temp_relid;
				}

    [...]
}
```

可以看到当为 PostgreSQL 16 时，如果 `rte->rellockmode != AccessShareLock` 时，它会将锁路由到会话访问的局部临时表上，对其他版本则不会进行此操作。而通过查看提交记录，我发现 PostgreSQL 在 [29ef2b310da](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=29ef2b310da9892fda075ff9ee12da7f92d5da6e) 中便引入了该检测，也就意味着 12 及其之后的版本都需要进行锁的路由。

```bash
$ git blame -L 810,814 src/backend/executor/execUtils.c
29ef2b310da (Tom Lane      2018-10-06 15:49:37 -0400 810)                        */
e0c4ec07284 (Andres Freund 2019-01-21 10:32:19 -0800 811)                       rel = table_open(rte->relid, NoLock);
29ef2b310da (Tom Lane      2018-10-06 15:49:37 -0400 812)                       Assert(rte->rellockmode == AccessShareLock ||
29ef2b310da (Tom Lane      2018-10-06 15:49:37 -0400 813)                                  CheckRelationLockedByMe(rel, rte->rellockmode, false));
29ef2b310da (Tom Lane      2018-10-06 15:49:37 -0400 814)               }
$ git show 29ef2b310da:configure.in | grep 'AC_INIT'
AC_INIT([PostgreSQL], [12devel], [pgsql-bugs@postgresql.org])
```

从上面可以看到这个是在 PostgreSQL 12 中引入的，我尝试了 12 到 15 都有相同的问题。我们可以使用下面的 patch 对其进行修复，即将相应的锁路由到会话的局部临时表上。

```diff
From 7c6d9a4205dff2c02ac013b76d17cd29f6d80c0c Mon Sep 17 00:00:00 2001
From: Japin Li <jianping.li@ww-it.cn>
Date: Thu, 21 Dec 2023 11:07:21 +0800
Subject: [PATCH] Forget acquiring lock for temporary table

---
 pgtt.c | 6 ++----
 1 file changed, 2 insertions(+), 4 deletions(-)

diff --git a/pgtt.c b/pgtt.c
index dfa580a..24fb19f 100755
--- a/pgtt.c
+++ b/pgtt.c
@@ -1797,14 +1797,12 @@ gtt_post_parse_analyze(ParseState *pstate, Query *query)
 #if PG_VERSION_NUM >= 160000
 					RTEPermissionInfo *rteperm = list_nth(query->rteperminfos,
 											rte->perminfoindex - 1);
-
-					rte->relid = gtt.temp_relid;
 					rteperm->relid = gtt.temp_relid;
+#endif
+					rte->relid = gtt.temp_relid;
 					if (rte->rellockmode != AccessShareLock)
 						LockRelationOid(rte->relid, rte->rellockmode);
-#endif
 					elog(DEBUG1, "rerouting relid %d access to %d for GTT table \"%s\"", rte->relid, gtt.temp_relid, name);
-					rte->relid = gtt.temp_relid;
 				}
 			}
 			else
```

打上补丁之后，所有回归测试都可以通过了。

## 锁问题

紧接上面，由于全局临时表的锁路由到了局部临时表上，那么全局临时表上面的锁是否还有必要呢？我们来观察一下当前的锁状态，确保 `pgtt` 插件已经安装，并且全局临时表 `t01` 已经创建。首先在 `Session 1` 中执行下述操作。

```psql
[local]:2723770 postgres=# -- Session 1
[local]:2723770 postgres=# LOAD 'pgtt';
LOAD
[local]:2723770 postgres=# SELECT locktype, relation, pid, mode, granted, fastpath, waitstart FROM pg_locks WHERE relation = 'pgtt_schema.t01'::regclass;
 locktype | relation | pid | mode | granted | fastpath | waitstart
----------+----------+-----+------+---------+----------+-----------
(0 rows)

[local]:2723770 postgres=# BEGIN;
BEGIN
[local]:2723770 postgres=*# INSERT INTO t01 VALUES (1, 'hello');
INSERT 0 1
[local]:2723770 postgres=*# SELECT locktype, relation, pid, mode, granted, fastpath, waitstart FROM pg_locks WHERE relation = 'pgtt_schema.t01'::regclass;
 locktype | relation |   pid   |       mode       | granted | fastpath | waitstart
----------+----------+---------+------------------+---------+----------+-----------
 relation |    16393 | 2764185 | AccessShareLock  | t       | t        |
 relation |    16393 | 2764185 | RowExclusiveLock | t       | t        |
(2 rows)
```

接着我们在 `Session 2` 中进行相同的操作，并观察锁信息。

```psql
[local]:2770866 postgres=# LOAD 'pgtt';
LOAD
[local]:2770866 postgres=# SELECT locktype, relation, pid, mode, granted, fastpath, waitstart FROM pg_locks WHERE relation = 'pgtt_schema.t01'::regclass;
 locktype | relation |   pid   |       mode       | granted | fastpath | waitstart
----------+----------+---------+------------------+---------+----------+-----------
 relation |    16393 | 2764185 | AccessShareLock  | t       | t        |
 relation |    16393 | 2764185 | RowExclusiveLock | t       | t        |
(2 rows)

[local]:2770866 postgres=# BEGIN;
BEGIN
[local]:2770866 postgres=*# INSERT INTO t01 VALUES (1, 'hello');
INSERT 0 1
[local]:2770866 postgres=*# SELECT locktype, relation, pid, mode, granted, fastpath, waitstart FROM pg_locks WHERE relation = 'pgtt_schema.t01'::regclass;
 locktype | relation |   pid   |       mode       | granted | fastpath | waitstart
----------+----------+---------+------------------+---------+----------+-----------
 relation |    16393 | 2764185 | AccessShareLock  | t       | t        |
 relation |    16393 | 2764185 | RowExclusiveLock | t       | t        |
 relation |    16393 | 2770866 | AccessShareLock  | t       | t        |
 relation |    16393 | 2770866 | RowExclusiveLock | t       | t        |
```

可以看到，每个会话都会在全局临时表上获取锁，但是由于后续操作不会在全局表上进行，那么是否可以释放全局临时表上的锁呢？

```diff
diff --git a/pgtt.c b/pgtt.c
index 24fb19f..fcf8e21 100755
--- a/pgtt.c
+++ b/pgtt.c
@@ -1799,9 +1799,12 @@ gtt_post_parse_analyze(ParseState *pstate, Query *query)
 											rte->perminfoindex - 1);
 					rteperm->relid = gtt.temp_relid;
 #endif
-					rte->relid = gtt.temp_relid;
 					if (rte->rellockmode != AccessShareLock)
-						LockRelationOid(rte->relid, rte->rellockmode);
+					{
+						LockRelationOid(gtt.temp_relid, rte->rellockmode);
+						UnlockRelationOid(rte->relid, rte->rellockmode);
+					}
+					rte->relid = gtt.temp_relid;
 					elog(DEBUG1, "rerouting relid %d access to %d for GTT table \"%s\"", rte->relid, gtt.temp_relid, name);
 				}
 			}
```

同样使用上面的方法进行测试，首先在 `Session 1` 中进行操作。

```
[local]:2723770 postgres=# -- Session 1
[local]:2800564 postgres=# LOAD 'pgtt';
LOAD
[local]:2800564 postgres=# SELECT locktype, relation, pid, mode, granted, fastpath, waitstart FROM pg_locks WHERE relation = 'pgtt_schema.t01'::regclass;
 locktype | relation | pid | mode | granted | fastpath | waitstart
----------+----------+-----+------+---------+----------+-----------
(0 rows)

[local]:2800564 postgres=# BEGIN;
BEGIN
[local]:2800564 postgres=*# INSERT INTO t01 VALUES (1, 'hello');
INSERT 0 1
[local]:2800564 postgres=*# SELECT locktype, relation, pid, mode, granted, fastpath, waitstart FROM pg_locks WHERE relation = 'pgtt_schema.t01'::regclass;
 locktype | relation |   pid   |      mode       | granted | fastpath | waitstart
----------+----------+---------+-----------------+---------+----------+-----------
 relation |    16393 | 2800564 | AccessShareLock | t       | t        |
(1 row)
```

接着在 `Session 2` 中进行操作。

```psql
[local]:2804681 postgres=# LOAD 'pgtt';
LOAD
[local]:2804681 postgres=# SELECT locktype, relation, pid, mode, granted, fastpath, waitstart FROM pg_locks WHERE relation = 'pgtt_schema.t01'::regclass;
 locktype | relation |   pid   |      mode       | granted | fastpath | waitstart
----------+----------+---------+-----------------+---------+----------+-----------
 relation |    16393 | 2800564 | AccessShareLock | t       | t        |
(1 row)

[local]:2804681 postgres=# BEGIN;
BEGIN
[local]:2804681 postgres=*# INSERT INTO t01 VALUES (1, 'hello');
INSERT 0 1
[local]:2804681 postgres=*# SELECT locktype, relation, pid, mode, granted, fastpath, waitstart FROM pg_locks WHERE relation = 'pgtt_schema.t01'::regclass;
 locktype | relation |   pid   |      mode       | granted | fastpath | waitstart
----------+----------+---------+-----------------+---------+----------+-----------
 relation |    16393 | 2804681 | AccessShareLock | t       | t        |
 relation |    16393 | 2800564 | AccessShareLock | t       | t        |
(2 rows)
```

可以看到，在全局临时表上的 `RowExclusiveLock` 锁被释放了，所有的回归测试同样能通过。当然由于我们不会真的对全局临时表插入数据，因此似乎这些锁影响也不大。不过数据库内核中还是需要维护锁信息，这会带来一定的开销。

<!--
这就要提到 `pgtt` 的基本实现原理了。


在创建 `pgtt` 插件时，它将创建 `pg_global_temp_tables` 表用于记录模版临时表。`pgtt` 在创建全局临时表时，将会创建一个无日志表作为所有临时表的模版。但会话中需要使用到临时表时，它就创建一个对应的会话临时表，内部则根据临时表的名称来进行路由。

#begin_src psql
postgres=# SELECT * FROM pg_global_temp_tables;
 relid |   nspname   | relname | preserved |       code
-------+-------------+---------+-----------+-------------------
 16405 | pgtt_schema | t01     | f         | id int, info text
(1 row)

postgres=# SELECT relname, relnamespace::regnamespace, relpersistence FROM pg_class WHERE relname = 't01';
 relname | relnamespace | relpersistence
---------+--------------+----------------
 t01     | pgtt_schema  | u
(1 row)
#end_src
-->

## 链接

[1] https://github.com/darold/pgtt/pull/36
[2] https://github.com/darold/pgtt/issues/35

<div class="just-for-fun">
笑林广记 - 吃屁

酒席间有撒屁者，众人互相推卸。
内一人曰：“列位请各饮一杯，待小弟说了罢。”
众饮讫，其人曰：“此屁实系小弟撒的。”
众人不服曰：“为何你撒了屁，倒要我们众人吃？”
</div>
