---
title: "PostgreSQL 的 repeat 函数"
date: 2022-07-15 21:44:38 +0800
categories: 数据库
tags:
  - PostgreSQL
---

PostgreSQL 的 `repeat()` 函数用于重复生成给定的字符串。例如：

```
repeat('abc', 3) -> 'abcabcabc'
```

最近在使用这个方法来生成 1GB 的数据时，遇到了一点问题。如下所示：

```sql
postgres=# CREATE TABLE myrepeat AS SELECT repeat('a', 1024 * 1024 * 1024);
ERROR:  invalid memory alloc request size 1073741828
```

<!--more-->

## 分析

通过查找 `invalid memory alloc request size` 字符串，我发现这是和 PostgreSQL 自带的内存管理模块有关。

```shell
$ grep 'invalid memory alloc request size' -rn src/
src/backend/utils/mmgr/mcxt.c:871:              elog(ERROR, "invalid memory alloc request size %zu", size);
src/backend/utils/mmgr/mcxt.c:914:              elog(ERROR, "invalid memory alloc request size %zu", size);
src/backend/utils/mmgr/mcxt.c:952:              elog(ERROR, "invalid memory alloc request size %zu", size);
src/backend/utils/mmgr/mcxt.c:988:              elog(ERROR, "invalid memory alloc request size %zu", size);
src/backend/utils/mmgr/mcxt.c:1078:             elog(ERROR, "invalid memory alloc request size %zu", size);
src/backend/utils/mmgr/mcxt.c:1109:             elog(ERROR, "invalid memory alloc request size %zu", size);
src/backend/utils/mmgr/mcxt.c:1143:             elog(ERROR, "invalid memory alloc request size %zu", size);
src/backend/utils/mmgr/mcxt.c:1194:             elog(ERROR, "invalid memory alloc request size %zu", size);
src/backend/utils/mmgr/mcxt.c:1232:             elog(ERROR, "invalid memory alloc request size %zu", size);
src/backend/utils/mmgr/mcxt.c:1264:             elog(ERROR, "invalid memory alloc request size %zu", size);
```

与 `invalid memory alloc request size` 有关的判断只有两个 `AllocHugeSizeIsValid()` 和 `AllocSizeIsValid()`，它们都是宏定义，如下所示：

```c
/*
 * MaxAllocSize, MaxAllocHugeSize
 *      Quasi-arbitrary limits on size of allocations.
 *
 * Note:
 *      There is no guarantee that smaller allocations will succeed, but
 *      larger requests will be summarily denied.
 *
 * palloc() enforces MaxAllocSize, chosen to correspond to the limiting size
 * of varlena objects under TOAST.  See VARSIZE_4B() and related macros in
 * postgres.h.  Many datatypes assume that any allocatable size can be
 * represented in a varlena header.  This limit also permits a caller to use
 * an "int" variable for an index into or length of an allocation.  Callers
 * careful to avoid these hazards can access the higher limit with
 * MemoryContextAllocHuge().  Both limits permit code to assume that it may
 * compute twice an allocation's size without overflow.
 */
#define MaxAllocSize    ((Size) 0x3fffffff) /* 1 gigabyte - 1 */

#define AllocSizeIsValid(size)  ((Size) (size) <= MaxAllocSize)

#define MaxAllocHugeSize    (SIZE_MAX / 2)

#define AllocHugeSizeIsValid(size)  ((Size) (size) <= MaxAllocHugeSize)
```

通过调试我发现 `repeat()` 函数会调用 `palloc()` 进行内存分配，这也就意味着它最大可以分配到 `1GB - 1` 的内存大小。

然而，我们的 `repeat('a', 1024 * 1024 * 1024)` 实际上却需要 `1073741828 = 1024 * 1024 * 1024 + 4` 的内存大小，这是为什么呢？我们来看一下 `repeat()` 函数的实现。

```c
Datum
repeat(PG_FUNCTION_ARGS)
{
    text       *string = PG_GETARG_TEXT_PP(0);
    int32       count = PG_GETARG_INT32(1);
    text       *result;
    int         slen,
                tlen;
    int         i;
    char       *cp,
               *sp;

    if (count < 0)
        count = 0;

    slen = VARSIZE_ANY_EXHDR(string);

    if (unlikely(pg_mul_s32_overflow(count, slen, &tlen)) ||
        unlikely(pg_add_s32_overflow(tlen, VARHDRSZ, &tlen)))
        ereport(ERROR,
                (errcode(ERRCODE_PROGRAM_LIMIT_EXCEEDED),
                 errmsg("requested length too large")));

    result = (text *) palloc(tlen);

    SET_VARSIZE(result, tlen);
    cp = VARDATA(result);
    sp = VARDATA_ANY(string);
    for (i = 0; i < count; i++)
    {
        memcpy(cp, sp, slen);
        cp += slen;
        CHECK_FOR_INTERRUPTS();
    }

    PG_RETURN_TEXT_P(result);
}
```

需要注意的是，在调用 `palloc()` 之前 `repeat()` 函数通过 `pg_mul_s32_overflow()` 和 `pg_add_s32_overflow()` 函数来计算出我们需要分配的内存大小。当执行 `pg_mul_s32_overflow()` 之后，一切都是正常的，我们需要分配 `1GB` 的内存，但是由于 PostgreSQL 内部对于 `text` 类型的处理需要额外的 `4` 个字节来存储数据的长度，因此它调用 `pg_add_s32_overflow()` 来计算实际需要分配的内存大小，`VARHDRSZ` 的定义如下所示，这也正好解释了为什么会多出 4 字节。

```c
#define VARHDRSZ            ((int32) sizeof(int32))
```

我们尝试使用减小所需的内存大小。

```sql
postgres=# CREATE TABLE myrepeat AS SELECT repeat('a', 1024 * 1024 * 1024 - 5);
ERROR:  invalid memory alloc request size 1073741871
```

通过前面的分析，我们知道 `repeat('a', 1024 * 1024 * 1024 - 5)` 的大小为 `1073741823`，那 `1073741871 - 1073741823 = 48` 是怎么来的呢？通过调试，其堆栈如下所示：

```
#0  palloc0 (size=1073741871) at /mnt/workspace/postgresql/build/../src/backend/utils/mmgr/mcxt.c:1103
#1  0x0000561925199faf in heap_form_tuple (tupleDescriptor=0x561927cb4310, values=0x561927cb4470, isnull=0x561927cb4478)
    at /mnt/workspace/postgresql/build/../src/backend/access/common/heaptuple.c:1069
#2  0x00005619254879aa in tts_virtual_copy_heap_tuple (slot=0x561927cb4428) at /mnt/workspace/postgresql/build/../src/backend/executor/execTuples.c:280
#3  0x000056192548a40c in ExecFetchSlotHeapTuple (slot=0x561927cb4428, materialize=true, shouldFree=0x7ffc9cc5197f)
    at /mnt/workspace/postgresql/build/../src/backend/executor/execTuples.c:1660
#4  0x000056192520e0c9 in heapam_tuple_insert (relation=0x7fdacaa9d3e0, slot=0x561927cb4428, cid=5, options=2, bistate=0x561927cb83f0)
    at /mnt/workspace/postgresql/build/../src/backend/access/heap/heapam_handler.c:245
#5  0x00005619253b2edf in table_tuple_insert (rel=0x7fdacaa9d3e0, slot=0x561927cb4428, cid=5, options=2, bistate=0x561927cb83f0)
    at /mnt/workspace/postgresql/build/../src/include/access/tableam.h:1376
#6  0x00005619253b3d73 in intorel_receive (slot=0x561927cb4428, self=0x561927c82430) at /mnt/workspace/postgresql/build/../src/backend/commands/createas.c:586
#7  0x0000561925478d86 in ExecutePlan (estate=0x561927cb3ed0, planstate=0x561927cb4108, use_parallel_mode=false, operation=CMD_SELECT, sendTuples=true, numberTuples=0,
    direction=ForwardScanDirection, dest=0x561927c82430, execute_once=true) at /mnt/workspace/postgresql/build/../src/backend/executor/execMain.c:1667
#8  0x0000561925476735 in standard_ExecutorRun (queryDesc=0x561927cab990, direction=ForwardScanDirection, count=0, execute_once=true)
    at /mnt/workspace/postgresql/build/../src/backend/executor/execMain.c:363
#9  0x000056192547654b in ExecutorRun (queryDesc=0x561927cab990, direction=ForwardScanDirection, count=0, execute_once=true)
    at /mnt/workspace/postgresql/build/../src/backend/executor/execMain.c:307
#10 0x00005619253b3711 in ExecCreateTableAs (pstate=0x561927c35b00, stmt=0x561927b5aa70, params=0x0, queryEnv=0x0, qc=0x7ffc9cc52370)
```

关键的核心就在 `heap_form_tuple()` 函数。其中关于内存分配的代码如下所示：

```c
HeapTuple
heap_form_tuple(TupleDesc tupleDescriptor,
                Datum *values,
                bool *isnull)
{
    [...]

    /*
     * Determine total space needed
     */
    len = offsetof(HeapTupleHeaderData, t_bits);

    if (hasnull)
        len += BITMAPLEN(numberOfAttributes);

    hoff = len = MAXALIGN(len); /* align user data safely */

    data_len = heap_compute_data_size(tupleDescriptor, values, isnull);

    len += data_len;

    /*
     * Allocate and zero the space needed.  Note that the tuple body and
     * HeapTupleData management structure are allocated in one chunk.
     */
    tuple = (HeapTuple) palloc0(HEAPTUPLESIZE + len);

    [...]
}
```

首先，我们需要一个 `HeapTupleHeaderData` 结构，随后是 `NULL` 值的 bitmap（如果有的话），接着是数据，最后还需要包含一个 `HEAPTUPLESIZE` 大小。其中 `HeapTupleHeaderData` 和 `HEAPTUPLESIZE` 大小是固定的，均为 `24`，在这里没有 `NULL` bitmap，因此其长度为 `0`，在加上数据长度 `1073741823`，所以，最终我们需要 `1073741823 + 24 + 24 = 1073741871`。

```sql
postgres=# CREATE TABLE myrepeat AS SELECT repeat('a', 1024 * 1024 * 1024 - 5 - 48);
SELECT 1
```

此外，如果我们直接使用 `SELECT` 的话，会报如下错误：

```sql
postgres=# SELECT repeat('a', 1024 * 1024 * 1024 - 5);
ERROR:  out of memory
DETAIL:  Cannot enlarge string buffer containing 6 bytes by 1073741819 more bytes.
```
通过上面的错误提示，可以推测是 `enlargeStringInfo()` 函数报的错，查找源码发现确实如此。

```bash
$ grep 'Cannot enlarge string buffer containing' -rn src/ --exclude "*.po"
src/common/stringinfo.c:306:                             errdetail("Cannot enlarge string buffer containing %d bytes by %d more bytes.",
src/common/stringinfo.c:310:                            _("out of memory\n\nCannot enlarge string buffer containing %d bytes by %d more bytes.\n"),
```

通过断点调试可以看到其堆栈信息如下所示：

```
#0  enlargeStringInfo (str=0x561927cacf70, needed=1073741819) at /mnt/workspace/postgresql/build/../src/common/stringinfo.c:291
#1  0x000056192591e042 in appendBinaryStringInfoNT (str=0x561927cacf70, data=0x7fda8aa49050 'a' <repeats 200 times>..., datalen=1073741819)
    at /mnt/workspace/postgresql/build/../src/common/stringinfo.c:258
#2  0x00005619254fb323 in pq_sendcountedtext (buf=0x561927cacf70, str=0x7fda8aa49050 'a' <repeats 200 times>..., slen=1073741819, countincludesself=false)
    at /mnt/workspace/postgresql/build/../src/backend/libpq/pqformat.c:159
#3  0x000056192519d6af in printtup (slot=0x561927c7b2c8, self=0x561927cacf20) at /mnt/workspace/postgresql/build/../src/backend/access/common/printtup.c:358
```

从 `printtup()` 函数可以看到服务器是如何将数据传输到客户端的。

```c
static bool
printtup(TupleTableSlot *slot, DestReceiver *self)
{
    [...]

    /*
     * Prepare a DataRow message (note buffer is in per-row context)
     */
    pq_beginmessage_reuse(buf, 'D');

    pq_sendint16(buf, natts);

    /*
     * send the attributes of this tuple
     */
    for (i = 0; i < natts; ++i)
    {
        PrinttupAttrInfo *thisState = myState->myinfo + i;
        Datum       attr = slot->tts_values[i];

        if (slot->tts_isnull[i])
        {
            pq_sendint32(buf, -1);
            continue;
        }

        /*
         * Here we catch undefined bytes in datums that are returned to the
         * client without hitting disk; see comments at the related check in
         * PageAddItem().  This test is most useful for uncompressed,
         * non-external datums, but we're quite likely to see such here when
         * testing new C functions.
         */
        if (thisState->typisvarlena)
            VALGRIND_CHECK_MEM_IS_DEFINED(DatumGetPointer(attr),
                                          VARSIZE_ANY(attr));
        if (thisState->format == 0)
        {
            /* Text output */
            char       *outputstr;

            outputstr = OutputFunctionCall(&thisState->finfo, attr);
            pq_sendcountedtext(buf, outputstr, strlen(outputstr), false);
        }
        else
        {
            /* Binary output */
            bytea      *outputbytes;

            outputbytes = SendFunctionCall(&thisState->finfo, attr);
            pq_sendint32(buf, VARSIZE(outputbytes) - VARHDRSZ);
            pq_sendbytes(buf, VARDATA(outputbytes),
                         VARSIZE(outputbytes) - VARHDRSZ);
        }
    }

    pq_endmessage_reuse(buf);

    [...]

    return true;
}
```

首先，它包含一个 `16` 位的属性列数量。然后是每个属性列值的长度和值。属性列数量的长度为 `2`，属性列值的长度为 `32` 位整型，长度为 `4`，因此总长度为 `6`，最后附加上字符串长度 `1073741823`。然而，`enlargeStringInfo()` 最大能分配 `1073741823` 的内存空间，然而在当前的 `StringInfoData` 中已经包含了 `6` 个字节，但是我们还需要 `1024 * 1024 * 1024 - 5 = 1073741819` 个字节，`1073741819 + 6 = 1073741825` 超出了 `1073741823` 的限制。如果我们执行下面的查询，那么便可以获取到数据。

```sql
SELECT repeat('a', 1024 * 1024 * 1024 - 5 - 3);
```

注意，这里减去 `3` 是因为 `enlargeStringInfo()` 函数里面的 `needed` 不包含末尾的 `null` 字符。嗷嗷嗷！世界一下子就清静了！

## 解决方案

当然就是避免使用这么大的字段咯！实际中估计也很少用到吧！:)

## 参考

[1] https://www.postgresql.org/docs/current/functions-string.html
[2] https://postgr.es/m/ME3P282MB16676ED32167189CB0462173B6D69@ME3P282MB1667.AUSP282.PROD.OUTLOOK.COM

<div class="just-for-fun">
笑林广记 - 仿制字

一生见有投制生帖者，深叹制字新奇，偶致一远札，遂效之。
仆致书回，生问见书有何话说，仆曰：“当面启看，便问老相公无恙，又问老安人好否。予曰：‘俱安。’乃沉吟半晌，带笑而入，才发回书。”
生大喜曰：“人不可不学，只一字用着得当，便一家俱问到，添下许多殷勤。”
</div>
