---
title: "PostgreSQL 更新组合类型的 domain 类型数组导致崩溃"
date: 2021-10-22 22:14:55 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

最近发现 PostgreSQL 在更新组合类型构成的 domain 数组将导致数据库崩溃。在写这篇文章的时候这个 bug 已经被修复了。

{% asset_img commit.png %}

<!--more-->

## 现象

为了复现这个问题，我们使用 [998d060f3d][pgcommit] 的代码来进行复现。首先，我们通过下面的 SQL 准备一个基本的测试环境。

```sql
CREATE TYPE comptype AS (cf1 int, cf2 int);
CREATE DOMAIN dcomptype AS comptype CHECK ((value).cf1 > 0);
CREATE TABLE dcomptable (f1 dcomptype[]);
```

接着，我们向表中插入数据，此时将导致 coredump。

```sql
postgres=# INSERT INTO dcomptable (f1[0].cf1) VALUES (4);
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
The connection to the server was lost. Attempting reset: Failed.
!?>
```

日志如下所示：

```
2021-10-20 11:14:22.313 CST [649100] LOG:  server process (PID 649976) was terminated by signal 11: Segmentation fault
2021-10-20 11:14:22.313 CST [649100] DETAIL:  Failed process was running: insert into dcomptable (f1[0].cf1) values (4);
2021-10-20 11:14:22.313 CST [649100] LOG:  terminating any other active server processes
2021-10-20 11:14:22.319 CST [649100] LOG:  all server processes terminated; reinitializing
2021-10-20 11:14:22.340 CST [649984] LOG:  database system was interrupted; last known up at 2021-10-20 11:11:20 CST
2021-10-20 11:14:22.361 CST [649984] LOG:  database system was not properly shut down; automatic recovery in progress
2021-10-20 11:14:22.369 CST [649984] LOG:  redo starts at 0/149E670
2021-10-20 11:14:22.370 CST [649984] LOG:  invalid record length at 0/149E6A8: wanted 24, got 0
2021-10-20 11:14:22.370 CST [649984] LOG:  redo done at 0/149E670 system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-10-20 11:14:22.409 CST [649100] LOG:  database system is ready to accept connections
```

## 分析

当程序崩溃后，堆栈信息如下：

```
(gdb) bt
#0  0x000055c22ce2d24d in pg_detoast_datum (datum=0x0)
    at /home/px/Codes/postgres/Debug/../src/backend/utils/fmgr/fmgr.c:1724
#1  0x000055c22c9f238c in ExecEvalFieldStoreDeForm (state=0x55c22dc94688, op=0x55c22dc94968, econtext=0x55c22dc94388)
    at /home/px/Codes/postgres/Debug/../src/backend/executor/execExprInterp.c:3153
#2  0x000055c22c9ee477 in ExecInterpExpr (state=0x55c22dc94688, econtext=0x55c22dc94388, isnull=0x7ffe292151ef)
    at /home/px/Codes/postgres/Debug/../src/backend/executor/execExprInterp.c:1437
#3  0x000055c22c9ef382 in ExecInterpExprStillValid (state=0x55c22dc94688, econtext=0x55c22dc94388,
    isNull=0x7ffe292151ef) at /home/px/Codes/postgres/Debug/../src/backend/executor/execExprInterp.c:1824
#4  0x000055c22ca4808b in ExecEvalExprSwitchContext (state=0x55c22dc94688, econtext=0x55c22dc94388,
    isNull=0x7ffe292151ef) at /home/px/Codes/postgres/Debug/../src/include/executor/executor.h:339
#5  0x000055c22ca48103 in ExecProject (projInfo=0x55c22dc94680)
    at /home/px/Codes/postgres/Debug/../src/include/executor/executor.h:373
#6  0x000055c22ca48338 in ExecResult (pstate=0x55c22dc94270)
    at /home/px/Codes/postgres/Debug/../src/backend/executor/nodeResult.c:136
#7  0x000055c22ca0505e in ExecProcNodeFirst (node=0x55c22dc94270)
    at /home/px/Codes/postgres/Debug/../src/backend/executor/execProcnode.c:463
#8  0x000055c22ca4030f in ExecProcNode (node=0x55c22dc94270)
    at /home/px/Codes/postgres/Debug/../src/include/executor/executor.h:257
#9  0x000055c22ca4429d in ExecModifyTable (pstate=0x55c22dc93d98)
    at /home/px/Codes/postgres/Debug/../src/backend/executor/nodeModifyTable.c:2425
#10 0x000055c22ca0505e in ExecProcNodeFirst (node=0x55c22dc93d98)
    at /home/px/Codes/postgres/Debug/../src/backend/executor/execProcnode.c:463
#11 0x000055c22c9f903a in ExecProcNode (node=0x55c22dc93d98)
    at /home/px/Codes/postgres/Debug/../src/include/executor/executor.h:257
#12 0x000055c22c9fba73 in ExecutePlan (estate=0x55c22dc93b20, planstate=0x55c22dc93d98, use_parallel_mode=false,
    operation=CMD_INSERT, sendTuples=false, numberTuples=0, direction=ForwardScanDirection, dest=0x55c22dbf5968,
    execute_once=true) at /home/px/Codes/postgres/Debug/../src/backend/executor/execMain.c:1551
#13 0x000055c22c9f9714 in standard_ExecutorRun (queryDesc=0x55c22dbf6a80, direction=ForwardScanDirection, count=0,
    execute_once=true) at /home/px/Codes/postgres/Debug/../src/backend/executor/execMain.c:361
#14 0x000055c22c9f9523 in ExecutorRun (queryDesc=0x55c22dbf6a80, direction=ForwardScanDirection, count=0,
    execute_once=true) at /home/px/Codes/postgres/Debug/../src/backend/executor/execMain.c:305
#15 0x000055c22cc69a81 in ProcessQuery (plan=0x55c22dbf5878,
    sourceText=0x55c22dbce2f0 "insert into dcomptable (f1[0].cf1) values (4);", params=0x0, queryEnv=0x0,
    dest=0x55c22dbf5968, qc=0x7ffe29215780) at /home/px/Codes/postgres/Debug/../src/backend/tcop/pquery.c:160
#16 0x000055c22cc6b5ba in PortalRunMulti (portal=0x55c22dc358e0, isTopLevel=true, setHoldSnapshot=false,
    dest=0x55c22dbf5968, altdest=0x55c22dbf5968, qc=0x7ffe29215780)
    at /home/px/Codes/postgres/Debug/../src/backend/tcop/pquery.c:1274
#17 0x000055c22cc6aad2 in PortalRun (portal=0x55c22dc358e0, count=9223372036854775807, isTopLevel=true,
    run_once=true, dest=0x55c22dbf5968, altdest=0x55c22dbf5968, qc=0x7ffe29215780)
    at /home/px/Codes/postgres/Debug/../src/backend/tcop/pquery.c:788
#18 0x000055c22cc63cbf in exec_simple_query (
    query_string=0x55c22dbce2f0 "insert into dcomptable (f1[0].cf1) values (4);")
    at /home/px/Codes/postgres/Debug/../src/backend/tcop/postgres.c:1214
#19 0x000055c22cc688e0 in PostgresMain (dbname=0x55c22dbf9798 "postgres", username=0x55c22dbc9d98 "px")
    at /home/px/Codes/postgres/Debug/../src/backend/tcop/postgres.c:4497
#20 0x000055c22cb92c91 in BackendRun (port=0x55c22dbf7560)
    at /home/px/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:4573
#21 0x000055c22cb92576 in BackendStartup (port=0x55c22dbf7560)
    at /home/px/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:4301
#22 0x000055c22cb8e5cb in ServerLoop () at /home/px/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:1801
#23 0x000055c22cb8dd64 in PostmasterMain (argc=1, argv=0x55c22dbc7d40)
    at /home/px/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:1473
#24 0x000055c22ca82599 in main (argc=1, argv=0x55c22dbc7d40)
    at /home/px/Codes/postgres/Debug/../src/backend/main/main.c:198
```

这里 `pg_detoast_datum()` 函数的值为空导致了崩溃，函数 `pg_detoast_datum()` 由 `DatumGetHeapTupleHeader()` 调用，如下所示。

```c
        /*
         * heap_deform_tuple needs a HeapTuple not a bare HeapTupleHeader. We
         * set all the fields in the struct just in case.
         */
        Datum       tupDatum = *op->resvalue;
        HeapTupleHeader tuphdr;
        HeapTupleData tmptup;

        tuphdr = DatumGetHeapTupleHeader(tupDatum);
        tmptup.t_len = HeapTupleHeaderGetDatumLength(tuphdr);
        ItemPointerSetInvalid(&(tmptup.t_self));
        tmptup.t_tableOid = InvalidOid;
        tmptup.t_data = tuphdr;

        heap_deform_tuple(&tmptup, tupDesc,
                          op->d.fieldstore.values,
                          op->d.fieldstore.nulls);
```

然而这里 `tupDatum` 是空的，因此，为了避免出现崩溃，我们可以在这里加上一个判断，如下所示：

```diff
diff --git a/src/backend/executor/execExprInterp.c b/src/backend/executor/execExprInterp.c
index eb49817cee..1ce14097d8 100644
--- a/src/backend/executor/execExprInterp.c
+++ b/src/backend/executor/execExprInterp.c
@@ -3150,6 +3150,10 @@ ExecEvalFieldStoreDeForm(ExprState *state, ExprEvalStep *op, ExprContext *econte
                HeapTupleHeader tuphdr;
                HeapTupleData tmptup;

+               if (DatumGetPointer(tupDatum) == NULL)
+                       return;
+
                tuphdr = DatumGetHeapTupleHeader(tupDatum);
                tmptup.t_len = HeapTupleHeaderGetDatumLength(tuphdr);
                ItemPointerSetInvalid(&(tmptup.t_self));
```

重新编译执行测试 SQL 语句。

```sql
postgres=# INSERT INTO dcomptable (f1[0].cf1) VALUES (4);
INSERT 0 1
postgres=# SELECT * FROM dcomptable;
       f1
----------------
 [0:0]={"(4,)"}
(1 row)
```

似乎一切都正常了，然而真的是这样么？我们来尝试一下更新语句。

```sql
postgres=# UPDATE dcomptable SET f1[0].cf2 = 10;
UPDATE 1
postgres=# SELECT * FROM dcomptable;
       f1
-----------------
 [0:0]={"(,10)"}
(1 row)
```

WTF? 为什么 `f1[0].cf1` 的值丢失了呢？我们尝试同时更新 `cf1` 和 `cf2`，看看会发生什么。

```sql
postgres=# UPDATE dcomptable SET f1[0].cf2 = 1, f1[0].cf1 = 2;
UPDATE 1
postgres=# SELECT * FROM dcomptable;
       f1
----------------
 [0:0]={"(2,)"}
(1 row)
```

这里仅仅保留了最后一个值（`f1[0].cf1`）。

因此，这就迫使我们重新思考上面的 patch 的正确性了（当时并没有那么仔细的想过这个问题）。为什么当初这里并没有判断 `tupDatum` 是否为空呢？是否存在某种前提，从而可以断定这里不会存在空的情况呢？

到这里，Tom Lane 大神站出来了。

> This patch seems quite misguided to me.  The proximate cause of
> the crash is that we're arriving at ExecEvalFieldStoreDeForm with
> *op->resnull and *op->resvalue both zero, which is a completely
> invalid situation for a pass-by-reference datatype; so something
> upstream of this messed up.  Even if there were an argument for
> acting as though that were a valid NULL value, this patch fails to
> do so; that'd require setting all the output fieldstore.nulls[]
> entries to true, which you didn't.

大意就是在 `ExecEvalFieldStoreDeForm()` 函数中不应该出现 `*op->resnull` 和 `*op->resvalue` 同时为空的情况，换言之，若出现这种情况，那么肯定是上层某个地方出错了。随后，大神也给出了解释。

> After some digging around, I see where the issue actually is:
> the expression tree we're dealing with looks like
>
>                  {SUBSCRIPTINGREF
>                  :refexpr
>                     {VAR
>                     }
>                  :refassgnexpr
>                     {COERCETODOMAIN
>                     :arg
>                        {FIELDSTORE
>                        :arg
>                           {CASETESTEXPR
>                           }
>                        }
>                     }
>                  }
>
> The array element we intend to replace has to be passed down to
> the CaseTestExpr, but that isn't happening.  That's because
> isAssignmentIndirectionExpr fails to recognize a tree like
> this, so ExecInitSubscriptingRef doesn't realize it needs to
> arrange for that.

这是由于 `isAssignmentIndirectionExpr()` 在处理间接表达式是遗忘了 `domain` 数组类型导致的。最终的解决方案如下：

```diff
diff --git a/src/backend/executor/execExpr.c b/src/backend/executor/execExpr.c
index 81b9d87bad..33ef39e2d4 100644
--- a/src/backend/executor/execExpr.c
+++ b/src/backend/executor/execExpr.c
@@ -3092,11 +3092,14 @@ ExecInitSubscriptingRef(ExprEvalStep *scratch, SubscriptingRef *sbsref,
  * (We could use this in FieldStore too, but in that case passing the old
  * value is so cheap there's no need.)
  *
- * Note: it might seem that this needs to recurse, but it does not; the
- * CaseTestExpr, if any, will be directly the arg or refexpr of the top-level
- * node.  Nested-assignment situations give rise to expression trees in which
- * each level of assignment has its own CaseTestExpr, and the recursive
- * structure appears within the newvals or refassgnexpr field.
+ * Note: it might seem that this needs to recurse, but in most cases it does
+ * not; the CaseTestExpr, if any, will be directly the arg or refexpr of the
+ * top-level node.  Nested-assignment situations give rise to expression
+ * trees in which each level of assignment has its own CaseTestExpr, and the
+ * recursive structure appears within the newvals or refassgnexpr field.
+ * There is an exception, though: if the array is an array-of-domain, we will
+ * have a CoerceToDomain as the refassgnexpr, and we need to be able to look
+ * through that.
  */
 static bool
 isAssignmentIndirectionExpr(Expr *expr)
@@ -3117,6 +3120,12 @@ isAssignmentIndirectionExpr(Expr *expr)
                if (sbsRef->refexpr && IsA(sbsRef->refexpr, CaseTestExpr))
                        return true;
        }
+       else if (IsA(expr, CoerceToDomain))
+       {
+               CoerceToDomain *cd = (CoerceToDomain *) expr;
+
+               return isAssignmentIndirectionExpr(cd->arg);
+       }
        return false;
 }
```

再次测试，一切正常。

```sql
postgres=# UPDATE dcomptable SET f1[0].cf2 = 1, f1[0].cf1 = 2;
UPDATE 1
postgres=# SELECT * FROM dcomptable;
       f1
-----------------
 [0:0]={"(2,1)"}
(1 row)

postgres=# UPDATE dcomptable SET f1[0].cf2 = 10;
UPDATE 1
postgres=# SELECT * FROM dcomptable;
        f1
------------------
 [0:0]={"(2,10)"}
(1 row)
```

<div class="just-for-fun">
笑林广记 - 家属

官坐堂，众后中有撒一响屁者。
官即叫：“拿来！”
隶禀曰：“老爷，屁是一阵风，吹散没影踪，叫小的如何拿得？”
官怒云：“为何徇情卖放，定要拿到。”
皂无奈，只得取干屎回销：“禀老爷，正犯是走了，拿得家属在此。”
</div>

[pgcommit]: https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=998d060f3db79c6918cb4a547695be150833f9a4
