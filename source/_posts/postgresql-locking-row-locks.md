---
title: "【译】PostgreSQL 锁 - Row Locks"
date: 2022-01-13 21:32:04 +0800
categories: 数据库
tags:
  - PostgreSQL
  - Locks
---

了解 PostgreSQL 锁对于构建可扩展的应用程序和避免停机很重要。现代计算机和服务器有许多 CPU 内核，可以并行执行多个查询。包含许多由查询或并行运行的后台进程进行更改的一致结构的数据库可能会使数据库崩溃甚至损坏数据。因此，我们需要能够防止来自并发进程的访问，同时更改共享内存结构或行。一个线程更新结构而所有其他线程等待（排他锁），或者多个线程读取结构并且所有写入等待。等待的副作用是锁争用和服务器资源浪费。因此，重要的是要了解为什么会发生等待以及涉及哪些锁。在本文中，我回顾了 PostgreSQL 行级锁（Row Level Locking）。

在后续文章中，我将研究保护内部数据库结构的[表级锁（Table Level Locks）][]和 [latches 锁][]。

<!--more-->

## 行级锁 - 概述

PostgreSQL 有许多不同抽象级别的锁。应用程序最重要的锁与 [MVCC](https://en.wikipedia.org/wiki/Multiversion_concurrency_control) 实现有关 — 行级锁。其次 — 在维护任务期间出现的锁（在备份/数据库迁移模式更改期间）— 表级锁。也有可能（但很少见）看到等待低级 PostgreSQL 锁。更常见的情况是 CPU 使用率很高，同时运行了许多并发查询，但与正常并行运行的查询数量相比，整体服务器性能降低了。

### 示例环境

接下来，您需要一个 PostgreSQL 服务器，其中包含一个拥有多行记录的单列表：

```
postgres=# CREATE TABLE locktest (c INT);
CREATE TABLE
postgres=# INSERT INTO locktest VALUES (1), (2);
INSERT 0 2
```

### 行级锁

场景：两个并发事务试图选择一行进行更新。

在这种情况下，PostgreSQL 使用行级锁。行级锁与 MVCC 实现紧密集成，并使用隐藏的 `xmin` 和 `xmax` 字段。`xmin` 和 `xmax` 存储了事务 ID。所有需要行级锁的语句都会修改 `xmax` 字段（甚至是 `SELECT FOR UPDATE`）。修改发生在查询返回结果之后，因此为了查看 `xmax` 变化，我们需要运行 `SELECT FOR UPDATE` 两次。通常，`xmax` 字段用于将行标记为已过期（被某些事务完全删除或支持更新的行版本），但它也用于行级锁基础结构。

如果您需要有关 `xmin` 和 `xmax` 隐藏字段以及 MVCC 实现的更多详细信息，请查看我们的 “[Basic Understanding of Bloat and VACUUM in PostgreSQL](https://www.percona.com/blog/2018/08/06/basic-understanding-bloat-vacuum-postgresql-mvcc/)” 博客文章。

```
postgres=# BEGIN;
postgres=# SELECT xmin,xmax, txid_current(), c FROM locktest WHERE c=1 FOR UPDATE;
BEGIN
 xmin | xmax | txid_current | c
------+------+--------------+---
  579 |  581 |          583 | 1
(1 row)
postgres=# SELECT xmin,xmax, txid_current(), c FROM locktest WHERE c=1 FOR UPDATE;
 xmin | xmax | txid_current | c
------+------+--------------+---
  579 |  583 |          583 | 1
(1 row)
```

如果一条语句试图修改同一行，它会检查未完成事务的列表。该语句必须等待修改，直到 `id=xmax` 的事务完成。

没有等待特定行的基础设施，但事务可以等待事务 id。

```
-- second connection
SELECT xmin,xmax,txid_current() FROM locktest WHERE c=1 FOR UPDATE;
```

在第二个连接中运行的 `SELECT FOR UPDATE` 查询未完成，正在等待第一个事务完成。

### pg_locks

通过查询 pg_locks 可以看到这样的等待和锁：

```
postgres=# SELECT locktype,transactionid,virtualtransaction,pid,mode,granted,fastpath
postgres-#  FROM pg_locks WHERE transactionid=583;
   locktype    | transactionid | virtualtransaction |  pid  |     mode      | granted | fastpath
---------------+---------------+--------------------+-------+---------------+---------+----------
 transactionid |           583 | 4/107              | 31369 | ShareLock     | f       | f
 transactionid |           583 | 3/11               | 21144 | ExclusiveLock | t       | f
```

您可以看到 `locktype=transactionid == 583` 的写入者事务 id。让我们获取持有锁的 pid 和后端 id：

```
postgres=# SELECT id,pg_backend_pid() FROM pg_stat_get_backend_idset() AS t(id)
postgres-#  WHERE pg_stat_get_backend_pid(id) = pg_backend_pid();
 id | pg_backend_pid
----+----------------
  3 |          21144
```

此后端已获取了锁 `granted(t)`。每个后端都有一个操作系统进程标识符（PID）和内部 PostgreSQL 标识符（后端 id）。 PostgreSQL 可以处理许多事务，但锁只能发生在后端之间，并且每个后端执行一个事务。内部簿记只需要一个虚拟事务标识符：一对后端 ID 和后端内部的序列号。

无论锁定的行数有多少，PostgreSQL 在 pg_locks 表中都只有一个相关的锁。查询可能会修改数十亿行，但 PostgreSQL 不会为冗余锁结构浪费内存。

写线程在它的 `transactionid` 上设置 `ExclusiveLock`。所有行级锁等待线程都设置了 `ShareLock`。一旦写线程释放锁，锁管理器就会恢复所有以前锁定的线程。

`transactionid` 的锁释放发生在提交或回滚时。

### pg_stat_activity

获取锁定相关详细信息的另一个好方法是从 pg_stat_activity 表中进行选择：

```
postgres=# SELECT pid,backend_xid,wait_event_type,wait_event,state,query FROM pg_stat_activity WHERE pid IN (31369,21144);
-[ RECORD 1 ]---+---------------------------------------------------------------------------------------------------------------------------
pid             | 21144
backend_xid     | 583
wait_event_type | Client
wait_event      | ClientRead
state           | idle in transaction
query           | SELECT id,pg_backend_pid() FROM pg_stat_get_backend_idset() AS t(id) WHERE pg_stat_get_backend_pid(id) = pg_backend_pid();
-[ RECORD 2 ]---+---------------------------------------------------------------------------------------------------------------------------
pid             | 31369
backend_xid     | 585
wait_event_type | Lock
wait_event      | transactionid
state           | active
query           | SELECT xmin,xmax,txid_current() FROM locktest WHERE c=1 FOR UPDATE;
```

### 源代码级调查

让我们使用 gdb 和 [pt-pmp](https://www.percona.com/doc/percona-toolkit/LATEST/pt-pmp.html) 工具检查被阻塞进程的堆栈信息：

```
# pt-pmp -p 31369
Sat Jul 28 10:10:25 UTC 2018
30	../sysdeps/unix/sysv/linux/epoll_wait.c: No such file or directory.
      1 epoll_wait,WaitEventSetWaitBlock,WaitEventSetWait,WaitLatchOrSocket,WaitLatch,ProcSleep,WaitOnLock,LockAcquireExtended,LockAcquire,XactLockTableWait,heap_lock_tuple,ExecLockRows,ExecProcNode,ExecutePlan,standard_ExecutorRun,PortalRunSelect,PortalRun,exec_simple_query,PostgresMain,BackendRun,BackendStartup,ServerLoop,PostmasterMain,main
```

`WaitOnLock` 函数导致等待。该函数位于 lock.c 文件（POSTGRES 主锁机制）中。

锁表是一个共享内存散列表。冲突进程在 `storage/lmgr/proc.c` 中的进行休眠以等待锁。在大多数情况下，此代码应通过 `lmgr.c` 或其他锁管理模块调用，而不是直接调用。

接下来，在 pg_stat_activity 中列为 `Lock` 的锁也称为重量级锁，由锁管理器控制。`HWLocks` 也用于许多高级操作。

顺便说一句，完整的描述可以在这里找到：https://www.postgresql.org/docs/current/static/explicit-locking.html

## 总结

* 避免长时间运行的事务修改频繁更新的行或过多的行。
* 接下来，不要在 MVCC 数据库中使用热点（由多个应用程序客户端连接并行更新的单行或多行）。这种工作负载更适合内存数据库，通常可以与主要业务逻辑分离。

## 译者注

本文翻译自 [Nickolay Ihalainen][] 在 [Percona][] 博客上发布的 [PostgreSQL locking, Part 1: Row Locks][] 一文。


<div class="just-for-fun">
笑林广记 - 老父

一市井受封，初见县官，以其齿尊，称之曰：“老先。”
其人含怒而归，子问其故，曰：“官欺我太甚，彼该称我老先生才是，乃作歇后语叫甚么老先。明系轻薄，我回称也不曾失了便宜。”
子询问何以称呼，答曰：“我本应称他老父母官，今亦缩住后韵，只叫他声老父。”
</div>


[表级锁（Table Level Locks）]: https://www.percona.com/blog/2018/10/24/postgresql-locking-part-2-heavyweight-locks/
[latches 锁]: https://www.percona.com/blog/2018/10/30/postgresql-locking-part-3-lightweight-locks/
[Percona]: https://www.percona.com/blog/
[Nickolay Ihalainen]: https://www.percona.com/blog/author/nickolay-ihalainen/
[PostgreSQL locking, Part 1: Row Locks]: https://www.percona.com/blog/2018/10/16/postgresql-locking-part-1-row-locks/
