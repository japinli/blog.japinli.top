---
title: "PostgreSQL TDE 读取文件参数无效分析"
date: 2022-09-27 23:25:52 +0800
categories: 数据库
tags:
  - PostgreSQL
---

本文记录 Cybertec PostgreSQL 数据库在 [`maintenance_work_mem`][] 较大时导致的读取文件参数无效或崩溃的情况。

<!--more-->

## 重现

我们可以使用下面的命令来重现这个问题。首先，我们下载 [Cybertec 的 PostgreSQL 数据库](https://github.com/cybertec-postgresql/postgres)，并进行编译安装，这里需要使用到 OpenSSL，同时为了便于调试，编译优化采用 `-O0`。

```bash
$ git clone https://github.com/cybertec-postgresql/postgres.git pgtde
$ cd pgtde  # commit (038a08243)
$ git checkout -b PG_14_TDE_1_1 origin/PG_14_TDE_1_1
$ mkdir build && cd build
$ ../configure --prefix=$PWD/tde --with-openssl --enable-debug CFLAGS='-O0'
$ make -j $(nproc) && make install
```

紧接着，配置环境变量，方便操作，这里我们用到了 `keycmd.sh` 来为数据库提供一个加解密密钥（确保其具有可执行权限）。

```bash
$ cat <<END > env.sh
export PGHOME=$PWD/tde
export PGPORT=8743
export PGDATA=\$PGHOME/pgdata
export PATH=\$PGHOME/bin:\$PATH
export LD_LIBRARY_PATH=\$PGHOME/lib:\$LD_LIBRARY_PATH
export PGENCRKEYCMD=$PWD/keycmd.sh
END
$ cat <<END > keycmd.sh
#!/bin/bash
echo "882fb7c12e80280fd664c69d2d636913"
END
$ chmod +x keycmd.sh
$ source env.sh
```

随后，初始化数据库，修改配置参数并启动服务器。

```
$ initdb
$ cat <<END >> $PGDATA/postgresql.auto.conf
maintenance_work_mem = '128MB'
END
$ pg_ctl -l log start
```

最后，使用 `pgbench` 初始化数据，复现错误场景。

```bash
$ pgbench -i -s 100 postgres
NOTICE:  table "pgbench_accounts" does not exist, skipping
NOTICE:  table "pgbench_branches" does not exist, skipping
NOTICE:  table "pgbench_history" does not exist, skipping
NOTICE:  table "pgbench_tellers" does not exist, skipping
creating tables...
generating data (client-side)...
10000000 of 10000000 tuples (100%) done (elapsed 43.01 s, remaining 0.00 s)
vacuuming...
creating primary keys...
pgbench: fatal: query failed: ERROR:  could not read file "(null)": Invalid argument
pgbench: query was: alter table pgbench_accounts add primary key (aid)
```

## 分析

最初，我们在默认的配置上测试，并没有任何问题，当在修改了默认参数之后，遇到了这个问题，经过反复修改参数并测试，最终定位到 [`maintenance_work_mem`][] 上，当采用默认的 `64MB` 一切正常，如果过是修改为 `128MB` 或更大，那么这个问题就可以得到稳定的重现（有时是上面看到的错误，有时是直接崩溃）。

经过反复的调试，我们最终定位到了 [`BufFileLogicalToPhysicalPos()`][] 函数，该函数是用于将逻辑位置转换为物理位置的，它在计算时出现了溢出的情况。我们可以通过 GDB 附加到进程并新增下面的断点来观察。

```gdb
(gdb) b tuplesort.c:3137 if srcTape == 2 && state->maxTapes == 4
```


上述步骤完成之后，我们在 psql 中执行下面的语句：

```sql
ALTER TABLE pgbench_accounts ADD PRIMARY KEY (aid);
```

断点触发之后，我们可以再新增一个断点 `b BufFileLogicalToPhysicalPos`，随后在 GDB 中执行 `continue`，此时的堆栈信息如下：

```
#0  BufFileLogicalToPhysicalPos (pos=2142765056) at /home/japin/Codes/pgtde/build/../src/include/storage/buffile.h:100
#1  0x00005606b8dfa46e in BufFileSeek (file=0x5606ba03e808, fileno=2, offset=0, whence=0)
    at /home/japin/Codes/pgtde/build/../src/backend/storage/file/buffile.c:961
#2  0x00005606b8dfaacf in BufFileSeekBlock (file=0x5606ba03e808, blknum=261568)
    at /home/japin/Codes/pgtde/build/../src/backend/storage/file/buffile.c:1176
#3  0x00005606b9017eca in ltsReadBlock (lts=0x5606ba0449c0, blocknum=261568, buffer=0x7fe2b0418048)
    at /home/japin/Codes/pgtde/build/../src/backend/utils/sort/logtape.c:288
#4  0x00005606b901800b in ltsReadFillBuffer (lts=0x5606ba0449c0, lt=0x5606ba044c00)
    at /home/japin/Codes/pgtde/build/../src/backend/utils/sort/logtape.c:324
#5  0x00005606b9018993 in ltsInitReadBuffer (lts=0x5606ba0449c0, lt=0x5606ba044c00)
    at /home/japin/Codes/pgtde/build/../src/backend/utils/sort/logtape.c:661
#6  0x00005606b9019157 in LogicalTapeRead (lts=0x5606ba0449c0, tapenum=2, ptr=0x7fff52ff05b4, size=4)
    at /home/japin/Codes/pgtde/build/../src/backend/utils/sort/logtape.c:989
#7  0x00005606b9021ebc in getlen (state=0x5606ba0286b8, tapenum=2, eofOK=true)
    at /home/japin/Codes/pgtde/build/../src/backend/utils/sort/tuplesort.c:3706
#8  0x00005606b9020fe9 in mergereadnext (state=0x5606ba0286b8, srcTape=2, stup=0x7fff52ff0630)
    at /home/japin/Codes/pgtde/build/../src/backend/utils/sort/tuplesort.c:3159
#9  0x00005606b9020f58 in beginmerge (state=0x5606ba0286b8)
    at /home/japin/Codes/pgtde/build/../src/backend/utils/sort/tuplesort.c:3137
```

从堆栈信息我们可以看到调用 [`BufFileLogicalToPhysicalPos()`] 函数的参数 `pos=2142765056`，结合下面该函数的定义，我们代入计算一下就可以知道发生溢出了。

```c
static inline off_t
BufFileLogicalToPhysicalPos(off_t pos)
{
    off_t   last_seg_bytes, result;
    int full_segs;

    if (!data_encrypted)
        return pos;

    /*
     * BYTES_PER_SEGMENT_LOGICAL -> buffile_seg_blocks_logical * BLCKSZ
     *                                  i.e. 130784 * 8192 = 1071382528
     * BYTES_PER_SEGMENT         ->         buffile_seg_blocks * BLCKSZ
     *                                  i.e. 131072 * 8192 = 1073741824
     *
     *      full_seg = 2142765056 / 1071382528 = 2
     *      result = 2 * 1073741824 = 2147483648
     *
     * 这里特别要注意 full_segs * BYTES_PER_SEGMENT 的运算，由于 full_segs 和
     * buffile_seg_blocks 均为 int 类型，因此它们更加 int 类型的规则进行运算，
     * 然而 int 类型最大能存储 2^31 - 1 = 2147483647，因此上述结果发生溢出。
     * 2147483648 = 0x80000000 在赋值给 off_t（8 字节有符号整数）时，由于类型
     * 转换时的高字节填充原则，从而变成 `0xffffffff80000000`，即 -2147483648。
     */
    full_segs = pos / BYTES_PER_SEGMENT_LOGICAL;
    result = full_segs * BYTES_PER_SEGMENT;

    last_seg_bytes = pos % BYTES_PER_SEGMENT_LOGICAL;
    if (last_seg_bytes > 0)
    {
        off_t   full_blocks;
        int     last_block_usage;
        int     useful_per_block = BLCKSZ - SizeOfBufFilePageHeader;

        full_blocks = last_seg_bytes / useful_per_block;
        result += full_blocks * BLCKSZ;

        last_block_usage = last_seg_bytes % useful_per_block;
        if (last_block_usage > 0)
            result += last_block_usage;
    }

    /*
     * Even if we're at block boundary, add the header size so that we end
     * up at usable position.
     *
     * 再加上 18 字节的头部长度，结果为 -2147483630
     */
    result += SizeOfBufFilePageHeader;

    return result;
}
```

上述函数返回之后将进行下面的计算：

```
fileno = pos_phys / BYTES_PER_SEGMENT;  /* -2147483630 / 1073741824 = -1 */
offset = pos_phys % BYTES_PER_SEGMENT;  /* -2147483630 % 1073741824 = -1073741806 */
```

随后在 [`BufFileSeek()`][] 函数中将 `fileno` 保存到 `file->common.curFile` 并通过 [`BufFileLoadBuffer()`] 函数加载数据。[`BufFileLoadBuffer()`] 的定义如下：

```c
static void
BufFileLoadBuffer(BufFile *file)
{
    BufFileCommon   *f = &file->common;
    BufFileSegment      *thisfile;

    /*
     * Only whole multiple of BLCKSZ can be encrypted / decrypted.
     */
    Assert(f->curOffset % BLCKSZ == 0 || !data_encrypted);

    /*
     * Advance to next component file if necessary and possible.
     */
    if (f->curOffset >= buffile_max_filesize &&
        f->curFile + 1 < file->numFiles)
    {
        f->curFile++;
        f->curOffset = 0L;
    }

    /*
     * Read whatever we can get, up to a full bufferload.
     * 这里由于 f->curFile 为 -1，因此取出来的 thisfile 是无效的（数组越界了），
     * 出现非法的数据，导致 FileRead() 函数执行出错，这里的出错是随机的，取决于
     * 内存中的数据（这就是为什么有时候崩溃，有时候是报读取文件错误（参数无效）。
     */
    thisfile = &file->files[f->curFile];
    f->nbytes = FileRead(thisfile->vfd,
                         f->buffer.data,
                         sizeof(f->buffer),
                         f->curOffset,
                         WAIT_EVENT_BUFFILE_READ);
    if (f->nbytes < 0)
    {
        f->nbytes = 0;
        ereport(ERROR,
                (errcode_for_file_access(),
                 errmsg("could not read file \"%s\": %m",
                        FilePathName(thisfile->vfd))));
    }

    /* we choose not to advance curOffset here */

    if (data_encrypted)
        BufFileAdjustUsefulBytes(f, file->files, ERROR);

    if (f->nbytes > 0)
        pgBufferUsage.temp_blks_read++;
}
```

这个问题是溢出导致，那么我们可以在计算的时候强制转换为 `off_t` 类型或者将 `full_segs` 定义为 `off_t` 类型，从而保证结果的正确性。修复方法如下所示：

```diff
diff --git a/src/include/storage/buffile.h b/src/include/storage/buffile.h
index 00723f45fd..e5964f5948 100644
--- a/src/include/storage/buffile.h
+++ b/src/include/storage/buffile.h
@@ -95,7 +95,7 @@ static inline off_t
 BufFileLogicalToPhysicalPos(off_t pos)
 {
        off_t   last_seg_bytes, result;
-       int     full_segs;
+       off_t   full_segs;

        if (!data_encrypted)
                return pos;
@@ -130,7 +130,7 @@ BufFileLogicalToPhysicalPos(off_t pos)
 static inline off_t
 BufFilePhysicalToLogicalPos(off_t pos)
 {
-       int             full_segs;
+       off_t   full_segs;
        off_t   last_seg_bytes, result;

        if (!data_encrypted)
```

经测试，上述代码可以有效地解决了该问题，代码里面还有其他地方可能存在类似的问题，在给 Cybertec 发送了定位分析之后，他们着手[修复了这个问题](https://github.com/cybertec-postgresql/postgres/commit/20880085986344177f32ffb36c513381d650b361)。

然而，还有一个问题，为什么 `64MB` 的 `maintenance_work_mem` 不会出现这个问题呢？在进行上述问题定位的时候，我们发现它是在执行并行的索引创建过程，为此，我们测试了当不采用并行时，程序的运行结果。

```psql
postgres=# SHOW max_parallel_maintenance_workers;
 max_parallel_maintenance_workers
----------------------------------
 2
(1 row)

postgres=# ALTER TABLE pgbench_accounts ADD PRIMARY KEY (aid);
2022-09-23 15:51:46.657 CST [25168] ERROR:  could not read file "(null)": Invalid argument
2022-09-23 15:51:46.657 CST [25168] STATEMENT:  alter table pgbench_accounts add primary key (aid);
ERROR:  could not read file "(null)": Invalid argument
postgres=# SET max_parallel_maintenance_workers TO 0;
SET
postgres=# ALTER TABLE pgbench_accounts ADD PRIMARY KEY (aid);
ALTER TABLE
```

从上面的输出可以看到，当并行被禁用之后，一切都是正常的。那么 [`maintenance_work_mem`][] 是如何影响并行的呢？答案就在 [`plan_create_index_workers()`][] 函数中。

```c
int
plan_create_index_workers(Oid tableOid, Oid indexOid)
{
    [...]

    /*
     * If parallel_workers storage parameter is set for the table, accept that
     * as the number of parallel worker processes to launch (though still cap
     * at max_parallel_maintenance_workers).  Note that we deliberately do not
     * consider any other factor when parallel_workers is set. (e.g., memory
     * use by workers.)
     */
    if (rel->rel_parallel_workers != -1)
    {
        parallel_workers = Min(rel->rel_parallel_workers,
                               max_parallel_maintenance_workers);
        goto done;
    }

	[...]

    /*
     * Estimate heap relation size ourselves, since rel->pages cannot be
     * trusted (heap RTE was marked as inheritance parent)
     */
    estimate_rel_size(heap, NULL, &heap_blocks, &reltuples, &allvisfrac);

    /*
     * Determine number of workers to scan the heap relation using generic
     * model
     */
    parallel_workers = compute_parallel_worker(rel, heap_blocks, -1,
                                               max_parallel_maintenance_workers);

    /*
     * Cap workers based on available maintenance_work_mem as needed.
     *
     * Note that each tuplesort participant receives an even share of the
     * total maintenance_work_mem budget.  Aim to leave participants
     * (including the leader as a participant) with no less than 32MB of
     * memory.  This leaves cases where maintenance_work_mem is set to 64MB
     * immediately past the threshold of being capable of launching a single
     * parallel worker to sort.
     */
    while (parallel_workers > 0 &&
           maintenance_work_mem / (parallel_workers + 1) < 32768L)
        parallel_workers--;

    [...]

    return parallel_workers;
}
```

上面的代码用于计算并行工作的进程数。其流程大致如下：

1. 如果用户为表指定了 [`parallel_workers`][]，那么并行的工作进程数为该参数和 [`max_parallel_maintenance_workers`][] 中较小的，此时不会考虑工作进程使用的内存。
2. 如果用户没有指定，则分三个步骤来计算并行工作的进程数：
   2.1. 先通过 [`estimate_rel_size()`][] 评估表的大小（主要是计算出实际的页面数），实际是调用 [`table_block_relation_estimate_size()`][] 函数进行计算；
   2.2. 随后通过 [`compute_parallel_worker()`][] 函数计算并行的工作进程数；该函数会根据表和索引的页面数量来计算并行工作进程的数量（涉及到 [`min_parallel_table_scan_size`][] 和 [`min_parallel_index_scan_size`][] 两个参数）。默认情况下，一个工作线进程处理约 `24MB` 的表数据 (`min_parallel_table_sacn_size * BLCKSZ * 3`)，或 `1536KB` 的索引数据 (`min_parallel_index_scan_size * BLCKSZ * 3`)；然后取处理表数据和索引数据中较小的工作进程数；最后还需要保证不超过最大的并行维护工作进程数 [`max_parallel_maintenance_workers`][]。
   2.3. 根据步骤 2 计算的并行工作进程数和 [`maintenance_work_mem`][] 调整并行工作的进程数。确保每个并行工作的进程都能从 [`maintenance_work_mem`][] 中分配到至少 `32MB` 的内存。

## 参考

[1] https://github.com/cybertec-postgresql/postgres
[2] https://www.postgresql.org/docs/14/runtime-config-resource.html
[3] https://www.postgresql.org/docs/14/sql-createtable.html
[4] https://www.postgresql.org/docs/14/runtime-config-query.html

[`BufFileLoadBuffer()`]: https://github.com/cybertec-postgresql/postgres/blob/038a08243ff7765d9d11052e91f43ed97fe199fb/src/backend/storage/file/buffile.c#L1543
[`BufFileLogicalToPhysicalPos()`]: https://github.com/cybertec-postgresql/postgres/blob/038a08243ff7765d9d11052e91f43ed97fe199fb/src/include/storage/buffile.h#L89
[`BufFileSeek()`]: https://github.com/cybertec-postgresql/postgres/blob/038a08243ff7765d9d11052e91f43ed97fe199fb/src/backend/storage/file/buffile.c#L916
[`compute_parallel_worker()`]: https://github.com/cybertec-postgresql/postgres/blob/a8de814ba12c1454089be2cd0a3f71ec52513690/src/backend/optimizer/path/allpaths.c#L3734
[`estimate_rel_size()`]: https://github.com/cybertec-postgresql/postgres/blob/a8de814ba12c1454089be2cd0a3f71ec52513690/src/backend/optimizer/util/plancat.c#L948
[`plan_create_index_workers()`]: https://github.com/cybertec-postgresql/postgres/blob/a8de814ba12c1454089be2cd0a3f71ec52513690/src/backend/optimizer/plan/planner.c#L5835
[`table_block_relation_estimate_size()`]: https://github.com/cybertec-postgresql/postgres/blob/a8de814ba12c1454089be2cd0a3f71ec52513690/src/backend/access/table/tableam.c#L647

[`maintenance_work_mem`]: https://www.postgresql.org/docs/14/runtime-config-resource.html#GUC-MAINTENANCE-WORK-MEM
[`max_parallel_maintenance_workers`]: https://www.postgresql.org/docs/14/runtime-config-resource.html#GUC-MAX-PARALLEL-MAINTENANCE-WORKERS
[`min_parallel_index_scan_size`]: https://www.postgresql.org/docs/14/runtime-config-query.html#GUC-MIN-PARALLEL-INDEX-SCAN-SIZE
[`min_parallel_table_scan_size`]: https://www.postgresql.org/docs/14/runtime-config-query.html#GUC-MIN-PARALLEL-TABLE-SCAN-SIZE
[`parallel_workers`]: https://www.postgresql.org/docs/14/sql-createtable.html#RELOPTION-PARALLEL-WORKERS

<div class="just-for-fun">
笑林广记 - 胡瘌杀

或看审囚回，人问之，答曰：“今年重囚五人，俱有认色：一痴子、一颠子、一瞎子、一胡子、一瘌痢。”
问如何审了，答曰：“只胡子与瘌痢吃亏，其余免死。”
又问何故，曰：“只听见问官说痴弗杀，颠弗杀，一眼弗杀，胡子搭瘌杀。”
</div>
