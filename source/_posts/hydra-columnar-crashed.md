---
title: "Hydra 列存崩溃问题"
date: 2024-03-07 22:16:22 +0800
categories: 数据库
tags:
  - Hydra
  - 列存
---

{% asset_img hydra-columnar-crashed.png %}

最近，同事在测试 [Hydra][] 的列存时遇到了崩溃的问题。当 `chunk_group_row_limit` 的值超过 `100000` 时，就会导致进程崩溃，其本质是由于 `stripeReadState->chunkGroupReadState` 被释放后，出现了空指针和悬空指针 ([Dangling Pointer](https://en.wikipedia.org/wiki/Dangling_pointer))，从而引发了进程崩溃。

<!--more-->


## 空指针导致崩溃

如 Test-Case-01 所示，我将 `t2` 表的 `chunk_group_row_limit` 修改为 `11000`，当在其上执行 `SELECT count(*) FROM t2;` 时服务器出现了崩溃。

{% code Test-Case-01 lang:sql line_number:false %}
CREATE TABLE t2 (id int, info text) USING columnar;
SELECT columnar.alter_columnar_table_set('t2', chunk_group_row_limit => '11000');
INSERT INTO t2 SELECT id, md5(id::text) FROM generate_series(1, 10000000) id;
SELECT count(*) FROM t2;
{% endcode %}

{% code Test-Case-01-Output line_number:false %}
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
The connection to the server was lost. Attempting reset: Failed.
The connection to the server was lost. Attempting reset: Failed.
{% endcode %}

通过 GDB 调试其崩溃时的堆栈如下所示。

{% code GDB-Backtrace line_number:false %}
#0  ReadStripeNextVector (stripeReadState=0x5575fc19e768, columnValues=0x5575fc1540a0, columnNulls=0x5575fc1540b0,
    newVectorSize=0x7ffdf9495ea0, stripeId=1, snapshot=0x5575fc0283b8, rowNumber=0x5575fc140820,
    stripeFirstRowNumber=1) at columnar_reader.c:2166
#1  0x00007fb8037bc42c in ColumnarReadNextVector (readState=0x5575fc19c7e8, columnValues=0x5575fc1540a0,
    columnNulls=0x5575fc1540b0, rowNumber=0x5575fc140820, newVectorSize=0x7ffdf9495ea0) at columnar_reader.c:2057
#2  0x00007fb8037befb8 in columnar_getnextslot (sscan=0x5575fc19c758, direction=ForwardScanDirection,
    slot=0x5575fc13e0c8) at columnar_tableam.c:385
#3  0x00007fb8037aafe0 in table_scan_getnextslot (sscan=0x5575fc19c758, direction=ForwardScanDirection,
    slot=0x5575fc13e0c8) at /data/japin/codes/postgres/build/pg/include/server/access/tableam.h:1066
#4  0x00007fb8037aeeeb in ColumnarScanNext (columnarScanState=0x5575fc0d02f0) at columnar_customscan.c:2544
#5  0x00007fb8037ae7e9 in ExecScanFetch (node=0x5575fc0d02f0, accessMtd=0x7fb8037aed2f <ColumnarScanNext>,
    recheckMtd=0x7fb8037aef21 <ColumnarScanRecheck>) at columnar_customscan.c:2257
#6  0x00007fb8037ae9e6 in CustomExecScan (columnarScanState=0x5575fc0d02f0,
    accessMtd=0x7fb8037aed2f <ColumnarScanNext>, recheckMtd=0x7fb8037aef21 <ColumnarScanRecheck>)
    at columnar_customscan.c:2353
#7  0x00007fb8037aef65 in ColumnarScan_ExecCustomScan (node=0x5575fc0d02f0) at columnar_customscan.c:2576
#8  0x00005575f990c1d3 in ExecCustomScan (pstate=0x5575fc0d02f0)
    at /data/japin/codes/postgres/build/../src/backend/executor/nodeCustom.c:124
#9  0x00007fb8037e1df6 in ExecProcNode (node=0x5575fc0d02f0)
    at /data/japin/codes/postgres/build/pg/include/server/executor/executor.h:273
#10 0x00007fb8037e2355 in fetch_input_tuple (aggstate=0x5575fc0cfc88)
    at vectorization/nodes/columnar_aggregator_node.c:639
#11 0x00007fb8037e5a66 in agg_retrieve_direct (vectoraggstate=0x5575fc0cf658)
    at vectorization/nodes/columnar_aggregator_node.c:2619
#12 0x00007fb8037e53c4 in ExecAgg (pstate=0x5575fc0cf658) at vectorization/nodes/columnar_aggregator_node.c:2311
#13 0x00007fb8037eac1f in ExecVectorAgg (node=0x5575fc0cf658) at vectorization/nodes/columnar_aggregator_node.c:5316
#14 0x00005575f990c1d3 in ExecCustomScan (pstate=0x5575fc0cf658)
    at /data/japin/codes/postgres/build/../src/backend/executor/nodeCustom.c:124
#15 0x00005575f98eda69 in ExecProcNodeFirst (node=0x5575fc0cf658)
    at /data/japin/codes/postgres/build/../src/backend/executor/execProcnode.c:464
#16 0x00005575f990e406 in ExecProcNode (node=0x5575fc0cf658)
    at /data/japin/codes/postgres/build/../src/include/executor/executor.h:273
#17 0x00005575f990eaf0 in gather_getnext (gatherstate=0x5575fc0cf4b8)
    at /data/japin/codes/postgres/build/../src/backend/executor/nodeGather.c:295
#18 0x00005575f990e953 in ExecGather (pstate=0x5575fc0cf4b8)
    at /data/japin/codes/postgres/build/../src/backend/executor/nodeGather.c:227
#19 0x00005575f98eda69 in ExecProcNodeFirst (node=0x5575fc0cf4b8)
    at /data/japin/codes/postgres/build/../src/backend/executor/execProcnode.c:464
#20 0x00005575f98fd84a in ExecProcNode (node=0x5575fc0cf4b8)
    at /data/japin/codes/postgres/build/../src/include/executor/executor.h:273
#21 0x00005575f98fdda3 in fetch_input_tuple (aggstate=0x5575fc0cee90)
    at /data/japin/codes/postgres/build/../src/backend/executor/nodeAgg.c:562
#22 0x00005575f9901358 in agg_retrieve_direct (aggstate=0x5575fc0cee90)
    at /data/japin/codes/postgres/build/../src/backend/executor/nodeAgg.c:2365
#23 0x00005575f9900f2e in ExecAgg (pstate=0x5575fc0cee90)
    at /data/japin/codes/postgres/build/../src/backend/executor/nodeAgg.c:2180
#24 0x00005575f98eda69 in ExecProcNodeFirst (node=0x5575fc0cee90)
    at /data/japin/codes/postgres/build/../src/backend/executor/execProcnode.c:464
#25 0x00005575f98e0b10 in ExecProcNode (node=0x5575fc0cee90)
    at /data/japin/codes/postgres/build/../src/include/executor/executor.h:273
#26 0x00005575f98e3ac8 in ExecutePlan (estate=0x5575fc0cec18, planstate=0x5575fc0cee90, use_parallel_mode=true,
    operation=CMD_SELECT, sendTuples=true, numberTuples=0, direction=ForwardScanDirection, dest=0x5575fc115d18,
    execute_once=true) at /data/japin/codes/postgres/build/../src/backend/executor/execMain.c:1670
#27 0x00005575f98e11f8 in standard_ExecutorRun (queryDesc=0x5575fc103a28, direction=ForwardScanDirection, count=0,
    execute_once=true) at /data/japin/codes/postgres/build/../src/backend/executor/execMain.c:365
#28 0x00005575f98e1001 in ExecutorRun (queryDesc=0x5575fc103a28, direction=ForwardScanDirection, count=0,
    execute_once=true) at /data/japin/codes/postgres/build/../src/backend/executor/execMain.c:309
#29 0x00005575f9ba356d in PortalRunSelect (portal=0x5575fc072cc8, forward=true, count=0, dest=0x5575fc115d18)
    at /data/japin/codes/postgres/build/../src/backend/tcop/pquery.c:924
#30 0x00005575f9ba3194 in PortalRun (portal=0x5575fc072cc8, count=9223372036854775807, isTopLevel=true,
    run_once=true, dest=0x5575fc115d18, altdest=0x5575fc115d18, qc=0x7ffdf94967e0)
    at /data/japin/codes/postgres/build/../src/backend/tcop/pquery.c:768
#31 0x00005575f9b9bf52 in exec_simple_query (query_string=0x5575fbff60d8 "SELECT count(*) FROM t2;")
    at /data/japin/codes/postgres/build/../src/backend/tcop/postgres.c:1274
#32 0x00005575f9ba0fc1 in PostgresMain (dbname=0x5575fbf60058 "postgres", username=0x5575fc02cb58 "japin")
    at /data/japin/codes/postgres/build/../src/backend/tcop/postgres.c:4637
#33 0x00005575f9ac195a in BackendRun (port=0x5575fc01fd90)
    at /data/japin/codes/postgres/build/../src/backend/postmaster/postmaster.c:4464
#34 0x00005575f9ac11e6 in BackendStartup (port=0x5575fc01fd90)
    at /data/japin/codes/postgres/build/../src/backend/postmaster/postmaster.c:4192
#35 0x00005575f9abd471 in ServerLoop ()
    at /data/japin/codes/postgres/build/../src/backend/postmaster/postmaster.c:1782
#36 0x00005575f9abcd1b in PostmasterMain (argc=1, argv=0x5575fbf5e010)
    at /data/japin/codes/postgres/build/../src/backend/postmaster/postmaster.c:1466
#37 0x00005575f9970914 in main (argc=1, argv=0x5575fbf5e010)
    at /data/japin/codes/postgres/build/../src/backend/main/main.c:198
{% endcode %}

可以看到这里在 `ReadStripeNextVector()` 函数里的 2166 行出现了问题，通过查看 `stripeReadState->chunkGroupReadState` 可以看到其为空。

{% code GDB line_number:false %}
(gdb) p stripeReadState->chunkGroupReadState
$1 = (ChunkGroupReadState *) 0x0
{% endcode %}

其代码如下所示：

```c
static bool
ReadStripeNextVector(StripeReadState *stripeReadState, Datum *columnValues,
                     bool *columnNulls, int *newVectorSize,
                     uint64 stripeId,
                     Snapshot snapshot,
                     uint64 *rowNumber,
                     uint64 stripeFirstRowNumber)
{
    [...]

    while (true)
    {
        [...]

        if (!ReadChunkGroupNextVector(stripeReadState->chunkGroupReadState,
                                      columnValues, columnNulls,
                                      stripeReadState->tupleDescriptor,
                                      columnValueOffset,
                                      newVectorSize,
                                      rowNumber,
                                      chunkFirstRowNumber))
        {
             /* if this chunk group is exhausted, fetch the next one and loop */
             EndChunkGroupRead(stripeReadState->chunkGroupReadState);
             stripeReadState->chunkGroupReadState = NULL;
             stripeReadState->chunkGroupIndex++;

             if (*newVectorSize == 0)
                continue;
        }

        stripeReadState->currentRow += stripeReadState->chunkGroupReadState->rowCount;

        return true;
    }

    return false;
}
```

当 `ReadChunkGroupNextVector()` 返回为 `false` 时，如果 `*newVectorSize` 不为 0 时，那么 `stripeReadState->chunkGroupReadState` 将会被释放并置为 `NULL`，而在后续的执行到继续使用到了该值，从而出现访问空指针导致进程崩溃。

这里由于 `stripeReadState->chunkGroupReadState` 已经被释放，我们无法知道其信息以及 `ReadChunkGroupNextVector()` 是如何退出的。我们可以通过加入条件断点来观察。

{% code GDB line_number:false %}
(gdb) b columnar_reader.c:2158 if (*newVectorSize) > 0
{% endcode %}

再次运行，可以观察到如下信息。

{% code GDB line_number:false %}
Breakpoint 1, ReadStripeNextVector (stripeReadState=0x5575fc1850d8, columnValues=0x5575fc13aa10, columnNulls=0x5575fc13aa20, newVectorSize=0x7ffdf9495ea0, stripeId=1, snapshot=0x5575fc0283b8, rowNumber=0x5575fc127190, stripeFirstRowNumber=1) at columnar_reader.c:2158
(gdb) p stripeReadState ->chunkGroupReadState
$4 = (ChunkGroupReadState *) 0x5575fc188e38
(gdb) p *stripeReadState ->chunkGroupReadState
$5 = {currentRow = 11000, rowCount = 11000, columnCount = 2, projectedColumnList = 0x0,
  chunkGroupData = 0x5575fc191ab8, rowMask = 0x0, rowMaskCached = false, chunkStripeRowOffset = 0,
  chunkGroupDeletedRows = 0}
(gdb) p *newVectorSize
$6 = 1000
{% endcode %}

`ReadChunkGroupNextVector()` 仅在读取到 `COLUMNAR_VECTOR_COLUMN_SIZE` 行记录时才返回 `true`。当 `currentRow == rowCount` 时返回 `false`。

根据 `currentRow = 11000, rowCount = 11000` 我们可以知道，该 chunk 被读取完毕，`ReadChunkGroupNextVector()` 返回 `false`，但此时 `*newVectorSize = 1000`，意味着还有数据，因此不会执行 `continue`，而是执行下面的累计操作。但是由于 `ReadChunkGroupNextVector()` 返回 `false` 时，`stripeReadState->chunkGroupReadState` 被释放且置空，因此后续的累计操作出现了空指针访问异常。

因此，我们需要避免在返回 `false` 时使用 `stripeReadState->chunkGroupReadState`，修复方法如下所示：

```diff
diff --git a/columnar/src/backend/columnar/columnar_reader.c b/columnar/src/backend/columnar/columnar_reader.c
index b24e4d1..b23829f 100644
--- a/columnar/src/backend/columnar/columnar_reader.c
+++ b/columnar/src/backend/columnar/columnar_reader.c
@@ -2162,8 +2162,8 @@ ReadStripeNextVector(StripeReadState *stripeReadState, Datum *columnValues,
 			if (*newVectorSize == 0)
 				continue;
 		}
-
-		stripeReadState->currentRow += stripeReadState->chunkGroupReadState->rowCount;
+		else
+			stripeReadState->currentRow += stripeReadState->chunkGroupReadState->rowCount;

 		return true;
 	}
```

## 悬空指针导致崩溃

这个问题与上面的类似，测试用例如 Test-Case-02 所示：

{% code Test-Case-02 lang:sql line_number:false %}
CREATE TABLE t(a INT, b TEXT) USING columnar;
SELECT columnar.alter_columnar_table_set('t', chunk_group_row_limit => '11000');
INSERT INTO t SELECT a, md5(b::text) FROM generate_series(0,50000) AS t1(a)
JOIN LATERAL generate_series(1, 10) AS t2(b) ON (true);
SELECT b, count(*) FROM t WHERE a > 50 AND b <> '' GROUP BY b;
{% endcode %}

{% code Test-Case-02-Output line_number:false %}
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
The connection to the server was lost. Attempting reset: Failed.
The connection to the server was lost. Attempting reset: Failed.
{% endcode %}

其堆栈信息如下所示：

{% code GDB-Backtrace line_number:false %}
#0  0x00005588c2b833ff in toast_raw_datum_size (value=22503863415320) at /home/japin/codes/postgres/build/../src/backend/access/common/detoast.c:550
#1  0x00005588c32c69b4 in textne (fcinfo=0x5588c521b718) at /home/japin/codes/postgres/build/../src/backend/utils/adt/varlena.c:1697
#2  0x00005588c2e50dd5 in ExecInterpExpr (state=0x5588c521b688, econtext=0x5588c51f7890, isnull=0x7fffda8cb39f)
    at /home/japin/codes/postgres/build/../src/backend/executor/execExprInterp.c:758
#3  0x00001477a335cceb in ExecEvalExprSwitchContext (state=0x5588c521b688, econtext=0x5588c51f7890, isNull=0x7fffda8cb39f)
    at /data/japin/codes/postgres/build/pg/include/server/executor/executor.h:355
#4  0x00001477a335ce1a in ExecQual (state=0x5588c521b688, econtext=0x5588c51f7890) at /data/japin/codes/postgres/build/pg/include/server/executor/executor.h:424
#5  0x00001477a3360c51 in CustomExecScan (columnarScanState=0x5588c51f7680, accessMtd=0x1477a3360d1c <ColumnarScanNext>, recheckMtd=0x1477a3360f0e <ColumnarScanRecheck>)
    at columnar_customscan.c:2448
#6  0x00001477a3360f52 in ColumnarScan_ExecCustomScan (node=0x5588c51f7680) at columnar_customscan.c:2576
#7  0x00005588c2e88fda in ExecCustomScan (pstate=0x5588c51f7680) at /home/japin/codes/postgres/build/../src/backend/executor/nodeCustom.c:124
#8  0x00005588c2e7a651 in ExecProcNode (node=0x5588c51f7680) at /home/japin/codes/postgres/build/../src/include/executor/executor.h:273
#9  0x00005588c2e7abaa in fetch_input_tuple (aggstate=0x5588c51f7018) at /home/japin/codes/postgres/build/../src/backend/executor/nodeAgg.c:562
#10 0x00005588c2e7e4e3 in agg_fill_hash_table (aggstate=0x5588c51f7018) at /home/japin/codes/postgres/build/../src/backend/executor/nodeAgg.c:2552
#11 0x00005588c2e7dd17 in ExecAgg (pstate=0x5588c51f7018) at /home/japin/codes/postgres/build/../src/backend/executor/nodeAgg.c:2173
#12 0x00005588c2e6a870 in ExecProcNodeFirst (node=0x5588c51f7018) at /home/japin/codes/postgres/build/../src/backend/executor/execProcnode.c:464
#13 0x00005588c2e8b20d in ExecProcNode (node=0x5588c51f7018) at /home/japin/codes/postgres/build/../src/include/executor/executor.h:273
#14 0x00005588c2e8b8f7 in gather_getnext (gatherstate=0x5588c51f6de8) at /home/japin/codes/postgres/build/../src/backend/executor/nodeGather.c:295
#15 0x00005588c2e8b75a in ExecGather (pstate=0x5588c51f6de8) at /home/japin/codes/postgres/build/../src/backend/executor/nodeGather.c:227
#16 0x00005588c2e6a870 in ExecProcNodeFirst (node=0x5588c51f6de8) at /home/japin/codes/postgres/build/../src/backend/executor/execProcnode.c:464
#17 0x00005588c2e7a651 in ExecProcNode (node=0x5588c51f6de8) at /home/japin/codes/postgres/build/../src/include/executor/executor.h:273
#18 0x00005588c2e7abaa in fetch_input_tuple (aggstate=0x5588c51f6780) at /home/japin/codes/postgres/build/../src/backend/executor/nodeAgg.c:562
#19 0x00005588c2e7e4e3 in agg_fill_hash_table (aggstate=0x5588c51f6780) at /home/japin/codes/postgres/build/../src/backend/executor/nodeAgg.c:2552
#20 0x00005588c2e7dd17 in ExecAgg (pstate=0x5588c51f6780) at /home/japin/codes/postgres/build/../src/backend/executor/nodeAgg.c:2173
#21 0x00005588c2e6a870 in ExecProcNodeFirst (node=0x5588c51f6780) at /home/japin/codes/postgres/build/../src/backend/executor/execProcnode.c:464
#22 0x00005588c2eb3951 in ExecProcNode (node=0x5588c51f6780) at /home/japin/codes/postgres/build/../src/include/executor/executor.h:273
#23 0x00005588c2eb3ba1 in ExecSort (pstate=0x5588c51f6570) at /home/japin/codes/postgres/build/../src/backend/executor/nodeSort.c:149
#24 0x00005588c2e6a870 in ExecProcNodeFirst (node=0x5588c51f6570) at /home/japin/codes/postgres/build/../src/backend/executor/execProcnode.c:464
#25 0x00005588c2e9de67 in ExecProcNode (node=0x5588c51f6570) at /home/japin/codes/postgres/build/../src/include/executor/executor.h:273
#26 0x00005588c2e9e0be in ExecLimit (pstate=0x5588c51f6280) at /home/japin/codes/postgres/build/../src/backend/executor/nodeLimit.c:96
#27 0x00005588c2e6a870 in ExecProcNodeFirst (node=0x5588c51f6280) at /home/japin/codes/postgres/build/../src/backend/executor/execProcnode.c:464
#28 0x00005588c2e5d917 in ExecProcNode (node=0x5588c51f6280) at /home/japin/codes/postgres/build/../src/include/executor/executor.h:273
#29 0x00005588c2e608cf in ExecutePlan (estate=0x5588c51f6008, planstate=0x5588c51f6280, use_parallel_mode=true, operation=CMD_SELECT, sendTuples=true, numberTuples=0,
    direction=ForwardScanDirection, dest=0x5588c520a538, execute_once=true) at /home/japin/codes/postgres/build/../src/backend/executor/execMain.c:1670
#30 0x00005588c2e5dfff in standard_ExecutorRun (queryDesc=0x5588c51d6268, direction=ForwardScanDirection, count=0, execute_once=true)
    at /home/japin/codes/postgres/build/../src/backend/executor/execMain.c:365
#31 0x00005588c2e5de08 in ExecutorRun (queryDesc=0x5588c51d6268, direction=ForwardScanDirection, count=0, execute_once=true)
    at /home/japin/codes/postgres/build/../src/backend/executor/execMain.c:309
#32 0x00005588c3120364 in PortalRunSelect (portal=0x5588c51655c8, forward=true, count=0, dest=0x5588c520a538) at /home/japin/codes/postgres/build/../src/backend/tcop/pquery.c:924
#33 0x00005588c311ff8b in PortalRun (portal=0x5588c51655c8, count=9223372036854775807, isTopLevel=true, run_once=true, dest=0x5588c520a538, altdest=0x5588c520a538,
    qc=0x7fffda8cbbd0) at /home/japin/codes/postgres/build/../src/backend/tcop/pquery.c:768
#34 0x00005588c3118d49 in exec_simple_query (
    query_string=0x5588c50e6178 "SELECT\n  URL, COUNT(*) AS PageViews FROM hits\nWHERE\n  CounterID = 62\n  AND EventDate >= '2013-07-01'\n  AND EventDate <= '2013-07-31'\n  AND DontCountHits = 0\n  AND IsRefresh = 0\n  AND URL <> ''\nGROUP B"...) at /home/japin/codes/postgres/build/../src/backend/tcop/postgres.c:1274
#35 0x00005588c311ddb8 in PostgresMain (dbname=0x5588c5123370 "postgres", username=0x5588c5123358 "japin") at /home/japin/codes/postgres/build/../src/backend/tcop/postgres.c:4637
#36 0x00005588c303e751 in BackendRun (port=0x5588c510fe90) at /home/japin/codes/postgres/build/../src/backend/postmaster/postmaster.c:4464
#37 0x00005588c303dfdd in BackendStartup (port=0x5588c510fe90) at /home/japin/codes/postgres/build/../src/backend/postmaster/postmaster.c:4192
#38 0x00005588c303a268 in ServerLoop () at /home/japin/codes/postgres/build/../src/backend/postmaster/postmaster.c:1782
#39 0x00005588c3039b12 in PostmasterMain (argc=3, argv=0x5588c504e050) at /home/japin/codes/postgres/build/../src/backend/postmaster/postmaster.c:1466
#40 0x00005588c2eed71b in main (argc=3, argv=0x5588c504e050) at /home/japin/codes/postgres/build/../src/backend/main/main.c:198
{% endcode %}

通过上面的堆栈信息，可以知道 `toast_raw_datum_size()` 访问第一个参数时出现了内存访问异常。

{% code GDB line_number:false %}
(gdb) f 1
#1  0x0000557ddff3eef1 in textne (fcinfo=0x557de0cbd748)
    at /data/japin/codes/postgres/build/../src/backend/utils/adt/varlena.c:1697
(gdb) p arg1
$1 = 140355960598152
(gdb) p *(Datum *)arg1
Cannot access memory at address 0x7fa72b2c6e88
{% endcode %}

可以看到此时的 `arg1` 的内存地址是无法访问的，那么这个值来自哪儿呢？再向上追溯可以看到 `CustomExecScan()` 函数调用了 `ExecQual()`，随后触发了上述错误，那么问题大概是由于此时的 `econtext->ecxt_scantuple` 中的包含了无效的内存地址。

{% code GDB line_number:false %}
(gdb) p rowNumber
$3 = 10001
{% endcode %}

在从 `VectorTupleTableSlot` 解析数据时，读取到 10001 行时出现了错误，这个值比较的特殊（在真实的场景中这个触发的条件比较难判断，因为存在其他一些条件过滤了部分数据，这里是我在后面分析之后给出的简化版本，参考 [#245](https://github.com/hydradatabase/hydra/pull/245)），因为 `COLUMNAR_VECTOR_COLUMN_SIZE = 10000`，我们可以在读取数据时下断点来查看数据内容。

{% code GDB line_number:false %}
(gdb) b ReadChunkGroupNextVector
Function "ReadChunkGroupNextVector" not defined.
Make breakpoint pending on future shared library load? (y or [n]) y
Breakpoint 1 (ReadChunkGroupNextVector) pending.
(gdb) b columnar_reader.c:2184
No source file named columnar_reader.c.
Make breakpoint pending on future shared library load? (y or [n]) y
Breakpoint 2 (columnar_reader.c:2184) pending.
(gdb) b columnar_reader.c:2199
No source file named columnar_reader.c.
Make breakpoint pending on future shared library load? (y or [n]) y
Breakpoint 3 (columnar_reader.c:2199) pending.
{% endcode %}

其代码如下所示：

{% code lang:c first_line:2175 mark:2184,2199 %}
static bool
ReadChunkGroupNextVector(ChunkGroupReadState *chunkGroupReadState, Datum *columnValues,
                         bool *columnNulls, TupleDesc tupleDesc,
                         int32 *columnValueOffset, int *chunkReadRows,
                         uint64 *rowNumber,
                         uint64 stripeFirstRowNumber)
{
    if (chunkGroupReadState->currentRow >= chunkGroupReadState->rowCount)
    {
        Assert(chunkGroupReadState->currentRow == chunkGroupReadState->rowCount);
        return false;
    }

    /*
     * Initialize to all-NULL. Only non-NULL projected attributes will be set.
     */
    memset(columnNulls, true, sizeof(bool) * chunkGroupReadState->columnCount);

    int i;
    int rowNumberIndex = 0;

    for (i = 0; i < chunkGroupReadState->rowCount; i ++)
    {
        if (chunkGroupReadState->currentRow >= chunkGroupReadState->rowCount)
            return false;

        [...]
    }

    return true;
}
{% endcode %}

接着，我们再次调试，当触发断点时，我们刚进入 `ReadChunkGroupNextVector()` 函数准备读取，我们使用 `finish` 命令执行该函数。

{% code GDB line_number:false %}
Breakpoint 1, ReadChunkGroupNextVector (chunkGroupReadState=0x557de0db6858, columnValues=0x557de0cd48e0, columnNulls=0x557de0cd48f0, tupleDesc=0x557de0cbae28, columnValueOffset=0x557de0d06bc8, chunkReadRows=0x7fffbc56a620, rowNumber=0x557de0cc1060, stripeFirstRowNumber=1) at columnar_reader.c:2182
2182            if (chunkGroupReadState->currentRow >= chunkGroupReadState->rowCount)
(gdb) finish
Run till exit from #0  ReadChunkGroupNextVector (chunkGroupReadState=0x557de0db6858,
    columnValues=0x557de0cd48e0, columnNulls=0x557de0cd48f0, tupleDesc=0x557de0cbae28,
    columnValueOffset=0x557de0d06bc8, chunkReadRows=0x7fffbc56a620,
    rowNumber=0x557de0cc1060, stripeFirstRowNumber=1) at columnar_reader.c:2182
0x00007fa72b3bc65e in ReadStripeNextVector (stripeReadState=0x557de0d2d038, columnValues=0x557de0cd48e0, columnNulls=0x557de0cd48f0, newVectorSize=0x7fffbc56a620, stripeId=1, snapshot=0x557de0bdd3b8, rowNumber=0x557de0cc1060, stripeFirstRowNumber=1) at columnar_reader.c:2149
Value returned is $1 = true
(gdb) p *stripeReadState->chunkGroupReadState
$3 = {currentRow = 10000, rowCount = 11000, columnCount = 2,
  projectedColumnList = 0x557de0d2b0d8, chunkGroupData = 0x557de0db68c0, rowMask = 0x0,
  rowMaskCached = false, chunkStripeRowOffset = 0, chunkGroupDeletedRows = 0}
(gdb) p *newVectorSize
$4 = 10000
{% endcode %}

从上面可以看到，第一次读取的时候仅读取了第一个 chunk 的 10000 行记录，此时 `ReadChunkGroupNextVector()` 函数返回 `true`，我们使用 `c` 继续执行，程序将第二次进入 `ReadChunkGroupNextVector()`，如下所示：

{% code GDB line_number:false %}
(gdb) c
Continuing.

Breakpoint 1, ReadChunkGroupNextVector (chunkGroupReadState=0x557de0db6858, columnValues=0x557de0cd48e0, columnNulls=0x557de0cd48f0, tupleDesc=0x557de0cbae28, columnValueOffset=0x557de0d06c90, chunkReadRows=0x7fffbc56a640, rowNumber=0x557de0cc1060, stripeFirstRowNumber=1) at columnar_reader.c:2182
(gdb) finish
Run till exit from #0  ReadChunkGroupNextVector (chunkGroupReadState=0x557de0db6858,
    columnValues=0x557de0cd48e0, columnNulls=0x557de0cd48f0, tupleDesc=0x557de0cbae28,
    columnValueOffset=0x557de0d06c90, chunkReadRows=0x7fffbc56a640,
    rowNumber=0x557de0cc1060, stripeFirstRowNumber=1) at columnar_reader.c:2182

Breakpoint 3, ReadChunkGroupNextVector (chunkGroupReadState=0x557de0db6858, columnValues=0x557de0cd48e0, columnNulls=0x557de0cd48f0, tupleDesc=0x557de0cbae28, columnValueOffset=0x557de0d06c90, chunkReadRows=0x7fffbc56a640, rowNumber=0x557de0cc1060, stripeFirstRowNumber=1) at columnar_reader.c:2199
{% endcode %}

可以看到此时触发了第三个断点，执行 `n` 返回到上层调用函数，我们可以看到如下信息。

{% code GDB line_number:false %}
(gdb) p *stripeReadState->chunkGroupReadState
$7 = {currentRow = 11000, rowCount = 11000, columnCount = 2,
  projectedColumnList = 0x557de0d2b0d8, chunkGroupData = 0x557de0db68c0, rowMask = 0x0,
  rowMaskCached = false, chunkStripeRowOffset = 0, chunkGroupDeletedRows = 0}
(gdb) p *newVectorSize
$8 = 1000
{% endcode %}

由于该 chunk 中仅剩下 1000 行记录没有读取，因此，在该 chunk 中最多能读取 1000 行，即 `*newVectorSize = 1000`。但是，函数 `ReadChunkGroupNextVector()` 仅在读取了 `COLUMNAR_VECTOR_COLUMN_SIZE` 行记录时返回 `true`，所以该函数此时返回值为 `false`，从而导致 `ReadStripeNextVector()` 释放了 `stripeReadState->chunkGroupReadState` 相关的内存。这便是引发悬空指针问题的根源。

此外，这里需要注意的时，对于基础数据类型（如 int, double 等固定长度的字段）不会出现问题，因为它们采用的是值传递 (pass-by-value)；而对于变长数据类型（如 text）则会导致崩溃，因为它们采用的是引用传递 (pass-by-reference)，参看 [`CreateVectorTupleTableSlot()`](https://github.com/hydradatabase/hydra/blob/dd0ef07209dd23b9fca213a152ee3ee13249bb34/columnar/src/backend/columnar/vectorization/columnar_vector_types.c#L70-L75) 函数。

因此，我们需要在 `ReadChunkGroupNextVector()` 返回 `false` 时，判断 `VectorTupleTableSlot` 中是否有数据，如果有则要延迟 `stripeReadState->chunkGroupReadState` 内存的释放。

```diff
diff --git a/columnar/src/backend/columnar/columnar_reader.c b/columnar/src/backend/columnar/columnar_reader.c
index b23829f..30448d5 100644
--- a/columnar/src/backend/columnar/columnar_reader.c
+++ b/columnar/src/backend/columnar/columnar_reader.c
@@ -2154,13 +2154,19 @@ ReadStripeNextVector(StripeReadState *stripeReadState, Datum *columnValues,
 									  rowNumber,
 									  chunkFirstRowNumber))
 		{
-			/* if this chunk group is exhausted, fetch the next one and loop */
-			EndChunkGroupRead(stripeReadState->chunkGroupReadState);
-			stripeReadState->chunkGroupReadState = NULL;
-			stripeReadState->chunkGroupIndex++;
-
+			/*
+			 * if *newVectorSize is non-zero, it means there might be some data in
+			 * chunkGroupReadState->chunkGroupData referenced by VectorColumn.  In
+			 * this case, do NOT release ChunkGroupReadState.
+			 */
 			if (*newVectorSize == 0)
+			{
+				/* if this chunk group is exhausted, fetch the next one and loop */
+				EndChunkGroupRead(stripeReadState->chunkGroupReadState);
+				stripeReadState->chunkGroupReadState = NULL;
+				stripeReadState->chunkGroupIndex++;
 				continue;
+			}
 		}
 		else
 			stripeReadState->currentRow += stripeReadState->chunkGroupReadState->rowCount;
```

## 备注

上面的查询可能会并行执行，为了减少调试时并行执行带来的困扰，可以在执行 SQL 查询时禁止并行执行，如 `SET max_parallel_workers = 0;`。

## 链接

[1] https://github.com/hydradatabase/hydra/pull/235
[2] https://github.com/hydradatabase/hydra/pull/245

[Hydra]: https://github.com/hydradatabase/hydra


<div class="just-for-fun">
笑林广记 - 善生虱

有善生虱者。自言一年只生十二虱。诘其故。曰：“我身上的虱者，真真一月一个。”
</div>
