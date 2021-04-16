---
title: "PostgreSQL 同步逻辑复制 TRUNCATE 表 hang 住"
date: 2021-04-16 23:09:12 +0800
category: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

在目前的 PostgreSQL 13 中，如果我们采用同步逻辑复制，那么在同步 TRUNCATE 表时，可能会发生数据库 hang 住的可能。本文便是针对这一问题进行分析。

<!-- more -->

## 现象

这个问题来自于 [PostgresSQL 邮件列表][1]，下面我们来复现一下这个问题（此处我使用的时 [pg 14devel][2] 进行复现）。

```
$ -- 配置主节点
$ initdb -D pubdb
$ cat << END >> pubdb/postgresql.auto.conf
port = '5433'
wal_level = 'logical'
wal_sender_timeout = '0'
wal_receiver_timeout = '0'
END
$ pg_ctl -l pub.log -D pubdb start

$ -- 配置从节点
$ initdb -D subdb
$ cat << END >> subdb/postgresql.auto.conf
port = '5434'
wal_level = 'logical'
wal_sender_timeout = '0'
wal_receiver_timeout = '0'
END
$ pg_ctl -l sub.log -D subdb start
```

这里设置 `wal_sender_timeout` 和 `wal_receiver_timeout` 主要时为了方便调试。

接着，我们创建一个两个表用于逻辑复制。

```
-- 主节点创建表和发布者
$ psql -p 5433 postgres -c 'CREATE TABLE tbl1 (a int primary key);' -c 'CREATE TABLE tbl2 (a int);'
$ psql -p 5433 postgres -c 'CREATE PUBLICATION pub FOR TABLE tbl1, tbl2;'

-- 从节点创建表和订阅者
$ psql -p 5434 postgres -c 'CREATE TABLE tbl1 (a int primary key);' -c 'CREATE TABLE tbl2 (a int);'
$ psql -p 5434 postgres -c "CREATE SUBSCRIPTION sub CONNECTION 'dbname=postgres port=5433' PUBLICATION pub;"
```

默认情况下，`CREATE SUBSCRIPTION` 命令会在主节点创建一个与其同名的复制槽。

```
$ psql -p 5433 postgres -c 'INSERT INTO tbl1 VALUES (1);'
$ psql -p 5433 postgres -c 'INSERT INTO tbl2 VALUES (1);'

$ psql -p 5434 postgres -c 'SELECT * FROM tbl1;'
 a
---
 1
(1 row)

$ psql -p 5434 postgres -c 'SELECT * FROM tbl2;'
 a
---
 1
(1 row)
```

我们在主节点执行 `TRUNCATE` 命令。

```
$ psql -p 5433 postgres -c 'TRUNCATE tbl2;'
$ psql -p 5434 postgres -c 'SELECT * FROM tbl2;'
 a
---
(0 rows)

$ psql -p 5433 postgres -c 'TRUNCATE tbl1;'
$ psql -p 5434 postgres -c 'SELECT * FROM tbl1;'
 a
---
(0 rows)
```

上面时异步模式的逻辑复制，下面我们来测试一下同步情况下的逻辑复制。

```
$ psql -p 5433 postgres -c "ALTER SYSTEM SET synchronous_standby_names TO 'sub';"
$ psql -p 5433 postgres -c "SELECT pg_reload_conf();"

$ psql -p 5433 postgres -c 'INSERT INTO tbl2 VALUES (10);'
$ psql -p 5434 postgres -c 'SELECT * FROM tbl2;'
 a
----
 10
(1 row)
$ psql -p 5433 postgres -c 'TRUNCATE tbl2;'
$ psql -p 5434 postgres -c 'SELECT * FROM tbl2;'
 a
---
(0 rows)

$ psql -p 5433 postgres -c 'INSERT INTO tbl1 VALUES (10);'
$ psql -p 5434 postgres -c 'SELECT * FROM tbl1;'
 a
----
 10
(1 row)
$ psql -p 5433 postgres -c 'TRUNCATE tbl1;'
hang 住了

$ psql -p 5434 postgres -c 'SELECT * FROM tbl1;'
 a
----
 10
(1 row)
```

我们来看一下数据库中的锁。

```
$ psql -p 5433 postgres -c 'SELECT * FROM pg_locks;'
   locktype    | database | relation | page | tuple | virtualxid | transactionid | classid | objid | objsubid | virtualtransaction |  pid  |        mode         | granted | fastpath |           waitstart
---------------+----------+----------+------+-------+------------+---------------+---------+-------+----------+--------------------+-------+---------------------+---------+----------+-------------------------------
 relation      |    14016 |    13289 |      |       |            |               |         |       |          | 5/19               | 21612 | AccessShareLock     | t       | t        |
 virtualxid    |          |          |      |       | 5/19       |               |         |       |          | 5/19               | 21612 | ExclusiveLock       | t       | t        |
 virtualxid    |          |          |      |       | 4/49       |               |         |       |          | 4/49               | 21133 | ExclusiveLock       | t       | t        |
 virtualxid    |          |          |      |       | 3/29       |               |         |       |          | 3/29               | 19592 | ExclusiveLock       | t       | t        |
 relation      |    14016 |    16387 |      |       |            |               |         |       |          | 3/29               | 19592 | AccessShareLock     | f       | f        | 2021-04-16 16:51:16.268573+08
 relation      |    14016 |    16387 |      |       |            |               |         |       |          | 4/49               | 21133 | AccessExclusiveLock | t       | f        |
 relation      |    14016 |    16384 |      |       |            |               |         |       |          | 4/49               | 21133 | ShareLock           | t       | f        |
 relation      |    14016 |    16384 |      |       |            |               |         |       |          | 4/49               | 21133 | AccessExclusiveLock | t       | f        |
 transactionid |          |          |      |       |            |           553 |         |       |          | 4/49               | 21133 | ExclusiveLock       | t       | f        |

$ ps -ef | grep postgres
japin    18477     1  0 16:32 ?        00:00:00 /home/japin/Codes/postgres/Debug/pg/bin/postgres -D pubdb
japin    18479 18477  0 16:32 ?        00:00:00 postgres: checkpointer
japin    18480 18477  0 16:32 ?        00:00:00 postgres: background writer
japin    18481 18477  0 16:32 ?        00:00:00 postgres: walwriter
japin    18482 18477  0 16:32 ?        00:00:00 postgres: autovacuum launcher
japin    18483 18477  0 16:32 ?        00:00:00 postgres: stats collector
japin    18484 18477  0 16:32 ?        00:00:00 postgres: logical replication launcher
japin    18646     1  0 16:33 ?        00:00:00 /home/japin/Codes/postgres/Debug/pg/bin/postgres -D subdb
japin    18648 18646  0 16:33 ?        00:00:00 postgres: checkpointer
japin    18649 18646  0 16:33 ?        00:00:00 postgres: background writer
japin    18650 18646  0 16:33 ?        00:00:00 postgres: walwriter
japin    18651 18646  0 16:33 ?        00:00:00 postgres: autovacuum launcher
japin    18652 18646  0 16:33 ?        00:00:00 postgres: stats collector
japin    18653 18646  0 16:33 ?        00:00:00 postgres: logical replication launcher
japin    19590 18646  0 16:40 ?        00:00:00 postgres: logical replication worker for subscription 16392
japin    19592 18477  0 16:40 ?        00:00:00 postgres: walsender japin [local] START_REPLICATION waiting
japin    21132 32595  0 16:51 pts/7    00:00:00 psql -p 5433 postgres -c TRUNCATE tbl1;
japin    21133 18477  0 16:51 ?        00:00:00 postgres: japin postgres [local] TRUNCATE TABLE waiting for 0/1632600
japin    21670  2878  0 16:55 pts/8    00:00:00 grep --color=auto postgres

$ psql -p 5433 postgres -c 'SELECT pg_blocking_pids('19592');'
 pg_blocking_pids
------------------
 {21133}
(1 row)
```

从上面可以看到，进程 `21133` 是执行 `TRUNCATE` 命令的进程，由于是同步提交，因此它在等待来自从节点的回应，此时进程 `19592`（walsender 进程）需要获取 `14016/16387` 上的 `AccessShareLock` 锁，而进程 `21133` 在 `14016/16387` 上持有了 `AccessExclusiveLock` 锁，因此导致 walsender 进程无法获取锁，这就导致的整个进程 hang 住了。

```
$ psql -p 5433 postgres -c 'SELECT relname, relkind FROM pg_class WHERE oid = 16387;'
  relname  | relkind
-----------+---------
 tbl1_pkey | i
(1 row)
```

`14016/16387` 对应的就是 `tbl1` 上的主键索引。

## 分析

这里需要弄清楚为什么 `tbl1` 别阻塞了，而 `tbl2` 没有被阻塞。它们的唯一区别是 `tbl1` 有一个主键索引，在逻辑复制中，它将被作为逻辑复制的 [Replica Identity][4]，可以推测是否是这个原因导致的呢？

我们使用 gdb 附加到 walsender 其调用栈如下所示。

```
(gdb) bt
#0  0x00007f296071da07 in epoll_wait (epfd=12, events=0x55af98fb9d18, maxevents=1, timeout=-1) at ../sysdeps/unix/sysv/linux/epoll_wait.c:30
#1  0x000055af97aa3731 in WaitEventSetWaitBlock (set=0x55af98fb9cb8, cur_timeout=-1, occurred_events=0x7fffbc568a90, nevents=1) at /home/japin/Codes/postgres/Debug/../src/backend/storage/ipc/latch.c:1452
#2  0x000055af97aa35ac in WaitEventSetWait (set=0x55af98fb9cb8, timeout=-1, occurred_events=0x7fffbc568a90, nevents=1, wait_event_info=50331648) at /home/japin/Codes/postgres/Debug/../src/backend/storage/ipc/latch.c:1398
#3  0x000055af97aa290f in WaitLatch (latch=0x7f295fbf4414, wakeEvents=33, timeout=0, wait_event_info=50331648) at /home/japin/Codes/postgres/Debug/../src/backend/storage/ipc/latch.c:473
#4  0x000055af97ace672 in ProcSleep (locallock=0x55af98fdeb28, lockMethodTable=0x55af981ba820 <default_lockmethod>) at /home/japin/Codes/postgres/Debug/../src/backend/storage/lmgr/proc.c:1361
#5  0x000055af97abc12f in WaitOnLock (locallock=0x55af98fdeb28, owner=0x55af99039de0) at /home/japin/Codes/postgres/Debug/../src/backend/storage/lmgr/lock.c:1858
#6  0x000055af97ababff in LockAcquireExtended (locktag=0x7fffbc568e50, lockmode=1, sessionLock=false, dontWait=false, reportMemoryError=true, locallockp=0x7fffbc568e48)
    at /home/japin/Codes/postgres/Debug/../src/backend/storage/lmgr/lock.c:1100
#7  0x000055af97ab7a0e in LockRelationOid (relid=16387, lockmode=1) at /home/japin/Codes/postgres/Debug/../src/backend/storage/lmgr/lmgr.c:117
#8  0x000055af975afa9e in relation_open (relationId=16387, lockmode=1) at /home/japin/Codes/postgres/Debug/../src/backend/access/common/relation.c:56
#9  0x000055af9763c76e in index_open (relationId=16387, lockmode=1) at /home/japin/Codes/postgres/Debug/../src/backend/access/index/indexam.c:136
#10 0x000055af97c7be60 in RelationGetIndexAttrBitmap (relation=0x7f2961ce9648, attrKind=INDEX_ATTR_BITMAP_IDENTITY_KEY) at /home/japin/Codes/postgres/Debug/../src/backend/utils/cache/relcache.c:5063
#11 0x000055af97a362b1 in logicalrep_write_attrs (out=0x55af990887d0, rel=0x7f2961ce9648) at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/proto.c:671
#12 0x000055af97a35952 in logicalrep_write_rel (out=0x55af990887d0, xid=0, rel=0x7f2961ce9648) at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/proto.c:418
#13 0x00007f2956c8f7c5 in send_relation_and_attrs (relation=0x7f2961ce9648, xid=0, ctx=0x55af99080450) at /home/japin/Codes/postgres/Debug/../src/backend/replication/pgoutput/pgoutput.c:502
#14 0x00007f2956c8f6a1 in maybe_send_schema (ctx=0x55af99080450, txn=0x55af990ad658, change=0x55af990b69a8, relation=0x7f2961ce9648, relentry=0x55af9909a218)
    at /home/japin/Codes/postgres/Debug/../src/backend/replication/pgoutput/pgoutput.c:460
#15 0x00007f2956c8fe13 in pgoutput_truncate (ctx=0x55af99080450, txn=0x55af990ad658, nrelations=1, relations=0x55af990b4608, change=0x55af990b69a8) at /home/japin/Codes/postgres/Debug/../src/backend/replication/pgoutput/pgoutput.c:691
#16 0x000055af97a2f8fe in truncate_cb_wrapper (cache=0x55af99082460, txn=0x55af990ad658, nrelations=1, relations=0x55af990b4608, change=0x55af990b69a8) at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/logical.c:1089
#17 0x000055af97a3adbc in ReorderBufferApplyTruncate (rb=0x55af99082460, txn=0x55af990ad658, nrelations=1, relations=0x55af990b4608, change=0x55af990b69a8, streaming=false)
    at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/reorderbuffer.c:1910
#18 0x000055af97a3b910 in ReorderBufferProcessTXN (rb=0x55af99082460, txn=0x55af990ad658, commit_lsn=23274800, snapshot_now=0x55af99082678, command_id=2, streaming=false)
    at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/reorderbuffer.c:2270
#19 0x000055af97a3c147 in ReorderBufferReplay (txn=0x55af990ad658, rb=0x55af99082460, xid=553, commit_lsn=23274800, end_lsn=23275008, commit_time=671878276266624, origin_id=0, origin_lsn=0)
    at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/reorderbuffer.c:2568
#20 0x000055af97a3c1c5 in ReorderBufferCommit (rb=0x55af99082460, xid=553, commit_lsn=23274800, end_lsn=23275008, commit_time=671878276266624, origin_id=0, origin_lsn=0)
    at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/reorderbuffer.c:2592
#21 0x000055af97a2a8e3 in DecodeCommit (ctx=0x55af99080450, buf=0x7fffbc5696c0, parsed=0x7fffbc569560, xid=553, two_phase=false) at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/decode.c:744
#22 0x000055af97a29be6 in DecodeXactOp (ctx=0x55af99080450, buf=0x7fffbc5696c0) at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/decode.c:278
#23 0x000055af97a297ff in LogicalDecodingProcessRecord (ctx=0x55af99080450, record=0x55af99080810) at /home/japin/Codes/postgres/Debug/../src/backend/replication/logical/decode.c:142
#24 0x000055af97a674e7 in XLogSendLogical () at /home/japin/Codes/postgres/Debug/../src/backend/replication/walsender.c:2865
#25 0x000055af97a666d3 in WalSndLoop (send_data=0x55af97a67408 <XLogSendLogical>) at /home/japin/Codes/postgres/Debug/../src/backend/replication/walsender.c:2290
#26 0x000055af97a6505f in StartLogicalReplication (cmd=0x55af99046958) at /home/japin/Codes/postgres/Debug/../src/backend/replication/walsender.c:1207
#27 0x000055af97a659f7 in exec_replication_command (cmd_string=0x55af98fc0f20 "START_REPLICATION SLOT \"sub\" LOGICAL 0/0 (proto_version '2', publication_names '\"pub\"')")
    at /home/japin/Codes/postgres/Debug/../src/backend/replication/walsender.c:1647
#28 0x000055af97addd72 in PostgresMain (argc=1, argv=0x7fffbc5699d0, dbname=0x55af98fecbe8 "postgres", username=0x55af98fecbc8 "japin") at /home/japin/Codes/postgres/Debug/../src/backend/tcop/postgres.c:4454
#29 0x000055af97a0c450 in BackendRun (port=0x55af98fe46f0) at /home/japin/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:4483
#30 0x000055af97a0bcfe in BackendStartup (port=0x55af98fe46f0) at /home/japin/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:4205
#31 0x000055af97a07e10 in ServerLoop () at /home/japin/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:1737
#32 0x000055af97a075c1 in PostmasterMain (argc=3, argv=0x55af98fb96c0) at /home/japin/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:1409
#33 0x000055af978fd9d7 in main (argc=3, argv=0x55af98fb96c0) at /home/japin/Codes/postgres/Debug/../src/backend/main/main.c:209
```

从堆栈可以看到 `logicalrep_write_attrs()` 函数调用 `RelationGetIndexAttrBitmap()` 函数并在其内部调用 `index_open()` 中打开索引时无法获取锁，从而导致进程 hang 住。

```
static void
logicalrep_write_attrs(StringInfo out, Relation rel)
{
    TupleDesc   desc;
    int         i;
    uint16      nliveatts = 0;
    Bitmapset  *idattrs = NULL;
    bool        replidentfull;

    desc = RelationGetDescr(rel);

    /* send number of live attributes */
    for (i = 0; i < desc->natts; i++)
    {
        if (TupleDescAttr(desc, i)->attisdropped || TupleDescAttr(desc, i)->attgenerated)
            continue;
        nliveatts++;
    }
    pq_sendint16(out, nliveatts);

    /* fetch bitmap of REPLICATION IDENTITY attributes */
    replidentfull = (rel->rd_rel->relreplident == REPLICA_IDENTITY_FULL);
    if (!replidentfull)
        idattrs = RelationGetIndexAttrBitmap(rel,
                                             INDEX_ATTR_BITMAP_IDENTITY_KEY);

	... ...
}
```

从上面的代码中，我们可以看到到不为 `REPLICA_IDENTITY_FULL` 时，我们需要调用 `RelationGetIndexAttrBitmap()` 函数来获取 Replica Identity 属性，`tbl2` 表在执行时由于没有调用 `RelationGetIndexAttrBitmap()` 所以不会 hang 住。

我们看看 `21133` 进程的堆栈，可以发现其阻塞在 `SyncRepWaitForLSN()` 函数调用中，该函数用于等待从节点对于当前事务的提交状态。

```
(gdb) bt
#0  0x00007f296071da07 in epoll_wait (epfd=12, events=0x55af98fb9d18, maxevents=1, timeout=-1)
    at ../sysdeps/unix/sysv/linux/epoll_wait.c:30
#1  0x000055af97aa3731 in WaitEventSetWaitBlock (set=0x55af98fb9cb8, cur_timeout=-1, occurred_events=0x7fffbc5695e0,
    nevents=1) at /home/japin/Codes/postgres/Debug/../src/backend/storage/ipc/latch.c:1452
#2  0x000055af97aa35ac in WaitEventSetWait (set=0x55af98fb9cb8, timeout=-1, occurred_events=0x7fffbc5695e0,
    nevents=1, wait_event_info=134217771) at /home/japin/Codes/postgres/Debug/../src/backend/storage/ipc/latch.c:1398
#3  0x000055af97aa290f in WaitLatch (latch=0x7f295fbef874, wakeEvents=17, timeout=-1, wait_event_info=134217771)
    at /home/japin/Codes/postgres/Debug/../src/backend/storage/ipc/latch.c:473
#4  0x000055af97a5b667 in SyncRepWaitForLSN (lsn=23275008, commit=true)
    at /home/japin/Codes/postgres/Debug/../src/backend/replication/syncrep.c:296
#5  0x000055af976a11d8 in RecordTransactionCommit ()
    at /home/japin/Codes/postgres/Debug/../src/backend/access/transam/xact.c:1456
#6  0x000055af976a1e52 in CommitTransaction ()
    at /home/japin/Codes/postgres/Debug/../src/backend/access/transam/xact.c:2188
#7  0x000055af976a2bef in CommitTransactionCommand ()
    at /home/japin/Codes/postgres/Debug/../src/backend/access/transam/xact.c:2965
#8  0x000055af97adbae4 in finish_xact_command ()
    at /home/japin/Codes/postgres/Debug/../src/backend/tcop/postgres.c:2703
#9  0x000055af97ad9282 in exec_simple_query (query_string=0x55af98fc0f20 "TRUNCATE tbl1;")
    at /home/japin/Codes/postgres/Debug/../src/backend/tcop/postgres.c:1221
#10 0x000055af97addd99 in PostgresMain (argc=1, argv=0x7fffbc5699d0, dbname=0x55af98ff4448 "postgres",
    username=0x55af98ff4428 "japin") at /home/japin/Codes/postgres/Debug/../src/backend/tcop/postgres.c:4458
#11 0x000055af97a0c450 in BackendRun (port=0x55af98fe6ac0)
    at /home/japin/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:4483
#12 0x000055af97a0bcfe in BackendStartup (port=0x55af98fe6ac0)
    at /home/japin/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:4205
#13 0x000055af97a07e10 in ServerLoop ()
    at /home/japin/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:1737
#14 0x000055af97a075c1 in PostmasterMain (argc=3, argv=0x55af98fb96c0)
    at /home/japin/Codes/postgres/Debug/../src/backend/postmaster/postmaster.c:1409
#15 0x000055af978fd9d7 in main (argc=3, argv=0x55af98fb96c0)
    at /home/japin/Codes/postgres/Debug/../src/backend/main/main.c:209
```

事务持用的锁当执行完 `RecordTransactionCommit()` 函数后，将由 `CommitTransaction()` 调用 `ResourceOwnerRelease(RESOURCE_RELEASE_LOCKS)` 来释放锁资源。

那么为什么在异步的情况下不会出现这种情况呢？这就需要理解 PostgreSQL 的同步复制，当异步复制时，PostgreSQL 并不会等待从节点的回应，因此锁可以得到释放。然而在同步模式下，从上面可以看出其没有机会释放锁，从而导致 walsender 进程无法获取锁。

## 解决

既然锁是由执行 `TRUNCATE` 命令的进程持有，从下面的代码可以看到 `TRUNCATE` 进程在等待来自从节点的响应时，WAL 日志其实已经刷盘了。那么我们是否可以在等待从节点之前释放锁资源呢?

```
static TransactionId
RecordTransactionCommit(void)
{
	... ...

    if ((wrote_xlog && markXidCommitted &&
         synchronous_commit > SYNCHRONOUS_COMMIT_OFF) ||
        forceSyncCommit || nrels > 0)
    {
        XLogFlush(XactLastRecEnd);

        /*
         * Now we may update the CLOG, if we wrote a COMMIT record above
         */
        if (markXidCommitted)
            TransactionIdCommitTree(xid, nchildren, children);
    }
    else
    {
        /*
         * Asynchronous commit case:
         *
         * This enables possible committed transaction loss in the case of a
         * postmaster crash because WAL buffers are left unwritten. Ideally we
         * could issue the WAL write without the fsync, but some
         * wal_sync_methods do not allow separate write/fsync.
         *
         * Report the latest async commit LSN, so that the WAL writer knows to
         * flush this commit.
         */
        XLogSetAsyncXactLSN(XactLastRecEnd);

        /*
         * We must not immediately update the CLOG, since we didn't flush the
         * XLOG. Instead, we store the LSN up to which the XLOG must be
         * flushed before the CLOG may be updated.
         */
        if (markXidCommitted)
            TransactionIdAsyncCommitTree(xid, nchildren, children, XactLastRecEnd);
    }

	... ...

    /*
     * Wait for synchronous replication, if required. Similar to the decision
     * above about using committing asynchronously we only want to wait if
     * this backend assigned an xid and wrote WAL.  No need to wait if an xid
     * was assigned due to temporary/unlogged tables or due to HOT pruning.
     *
     * Note that at this stage we have marked clog, but still show as running
     * in the procarray and continue to hold locks.
     */
    if (wrote_xlog && markXidCommitted)
        SyncRepWaitForLSN(XactLastRecEnd, true);

	... ...
}
```

经过测试，这样做是可以的，它能解决同步流复制下 `TRUNCATE` 被 hang 的问题，同时整个数据库的测试（`make check-world`）也可以通过。那么是否就意味这样解决就可以了呢？

上面的解决方案其实就有点类似于头痛医头、脚痛医脚的感觉。这个方案基本上都没有入了社区大神的眼，那么大神们是怎么解决的呢？其实这样的场景存在同步流复制中，那么为什么同步流复制下没有这个问题呢？基于此，Amit Kapila 给出的建议是我们是否可以避免调用 `index_open()` 函数来打开索引，而是使用缓存中的对象来获取逻辑复制的 Replica Identity，即通过 `RelationIdGetRelation()` 函数来获取表对象构建 Replica Identity。

下面是一个简单的 POC 测试修改补丁，经过测试其能够修复这个问题。

```
diff --git a/src/backend/utils/cache/relcache.c b/src/backend/utils/cache/relcache.c
index 29702d6eab..0ad59ef189 100644
--- a/src/backend/utils/cache/relcache.c
+++ b/src/backend/utils/cache/relcache.c
@@ -5060,7 +5060,7 @@ restart:
                bool            isPK;           /* primary key */
                bool            isIDKey;        /* replica identity index */

-               indexDesc = index_open(indexOid, AccessShareLock);
+               indexDesc = RelationIdGetRelation(indexOid);

                /*
                 * Extract index expressions and index predicate.  Note: Don't use
@@ -5134,7 +5134,7 @@ restart:
                /* Collect all attributes in the index predicate, too */
                pull_varattnos(indexPredicate, 1, &indexattrs);

-               index_close(indexDesc, AccessShareLock);
+               RelationClose(indexDesc);
        }
```

`RelationGetIndexAttrBitmap()` 函数会被其他函数调用，因此这样修改可能会引起其他部分的问题，Amit Kapila 建议单独弄一个函数来实现该功能，目前补丁正在由 Takamichi Osumi 进行更新，后续 review 之后应该就会合并到 14 分支中，至于会不会 backpatch 到其他分支还有待后续，个人认为应该会做 backpatch。

## 总结

这次的分析过程收益还是颇多的，对 PostgreSQL 的流复制有了更深刻的认识。此外对于 PostgreSQL 的 TAP 测试也有了一点心得，不再像之前修复[逻辑复制行为异常][3]那样对 TAP 测试茫然了。

## 讨论

\[1] [Truncate in synchronous logical replication failed][1]

[1]: https://www.postgresql.org/message-id/OS0PR01MB6113C2499C7DC70EE55ADB82FB759%40OS0PR01MB6113.jpnprd01.prod.outlook.com
[2]: https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=409723365b2708acd3bdf2e830257504bdefac4b
[3]: https://www.postgresql.org/message-id/CALj2ACV%2B0UFpcZs5czYgBpujM9p0Hg1qdOZai_43OU7bqHU_xw%40mail.gmail.com
[4]: https://www.postgresql.org/docs/devel/sql-altertable.html#SQL-ALTERTABLE-REPLICA-IDENTITY
