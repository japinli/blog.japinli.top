---
title: "PostgreSQL 快照导出和导入"
date: 2022-09-21 20:10:29 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

PostgreSQL 允许数据库会话同步它们的快照。快照确定哪些数据对使用快照的事务可见。当两个或多个会话需要查看数据库中的相同内容时，需要同步快照。如果两个会话只是独立地开始它们的事务，在两个 `START TRANSACTION` 命令的执行之间总是有可能提交第三个事务，这样一个会话可以看到该事务的效果，而另一个则看不到。

为了解决这个问题，PostgreSQL 允许事务导出它正在使用的快照。只要导出快照的事务保持打开状态，其他事务就可以导入这个快照，从而保证它们看到的数据库视图与第一个事务看到的完全相同。

快照可以通过 [`pg_export_snapshot()`][] 函数导出，并通过 [`SET TRANSACTION`][] 命令导入。本文我将从源码角度分析一下快照导出和导入的流程。

<!--more-->

## 用法

[`pg_export_snapshot()`][] 的使用非常简单，直接在事务中调用该函数即可，如果需要，您可以在同一个事务中多次导出快照（仅在 `READ COMMITTED` 级别下非常有用，在 `REPEATABLE READ` 和更高的隔离级别中，事务在其整个生命周期中使用相同的快照）。如下所示，我们在 `READ COMMITTED` 隔离级别下导出了一个名为 `00000003-00000009-1` 的快照。

```sql
postgres=# BEGIN;
postgres=*# SELECT pg_export_snapshot();
 pg_export_snapshot
---------------------
 00000003-00000009-1
(1 row)
```

此时，我们在开启另一个事务来导入快照。

```sql
postgres=# BEGIN ISOLATION LEVEL REPEATABLE READ;
postgres=*# SET TRANSACTION snapshot '00000003-00000009-1';  -- 在执行任何查询之前

postgres=# BEGIN;  -- 等效于上面的
postgres=*# SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
postgres=*# SET TRANSACTION snapshot '00000003-00000009-1';
```

快照的导出、导入需要注意以下几点：

1. 在导出快照的事务中不能使用 [`PREPARE TRANSACTION`][] 语句。

   ```sql
   postgres=# BEGIN;
   postgres=*# SELECT pg_export_snapshot();
    pg_export_snapshot
   ---------------------
    00000003-0000000A-1
   (1 row)

   postgres=*# PREPARE TRANSACTION 'foo';
   ERROR:  cannot PREPARE a transaction that has exported snapshots
   ```

2. 在子事务中不能导出快照。

   ```sql
   postgres=# BEGIN;
   postgres=*# SAVEPOINT s1;
   postgres=*# select pg_export_snapshot();
   ERROR:  cannot export a snapshot from a subtransaction
   ```
3. 快照的导入必须在任何查询执行之前进行。

   ```sql
   postgres=# BEGIN;
   postgres=*# SELECT 1;
    ?column?
   ----------
           1
   (1 row)

   postgres=*# SET TRANSACTION SNAPSHOT '00000003-0000000C-1';
   ERROR:  SET TRANSACTION SNAPSHOT must be called before any query
   ```

4. 导入快照的事务隔离级别必须是 `REPEATABLE READ` 或更高的隔离级别。

   ```sql
   postgres=# BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
   BEGIN
   postgres=*# SET TRANSACTION SNAPSHOT '00000003-0000000C-1';
   ERROR:  a snapshot-importing transaction must have isolation level SERIALIZABLE or REPEATABLE READ
   ```

5. 如果导入事务使用 `SERIALIZABLE` 隔离级别，则导出快照的事务也必须使用该隔离级别。

   ```sql
   postgres=# BEGIN ISOLATION LEVEL SERIALIZABLE;
   postgres=*# SET TRANSACTION SNAPSHOT '00000003-0000000C-1';
   ERROR:  a serializable transaction cannot import a snapshot from a non-serializable transaction
   ```

6. 非只读可序列化事务无法从只读事务导入快照。

   ```sql
   postgres=# BEGIN ISOLATION LEVEL SERIALIZABLE;
   postgres=*# SET TRANSACTION SNAPSHOT '00000003-0000000D-1';
   ERROR:  a non-read-only serializable transaction cannot import a snapshot from a read-only transaction
   ```

7. 导出的快照不能导入到其他数据库中，即导出、导入快照的数据库必须相同。

   ```sql
   testdb=# BEGIN ISOLATION LEVEL SERIALIZABLE;
   testdb=*# SET TRANSACTION SNAPSHOT '00000003-0000000D-1';
   ERROR:  cannot import a snapshot from a different database
   ```

**备注：**在事务中慎用 psql 的 TAB 补全功能，因为它可能会去查询系统表。

## 实现

在了解了基本的使用之后，我们来看看 PostgreSQL 是如何实现快照的导出、导入的。

### 快照导出

首先我们看看导出的实现，由于它是一个函数，我们可以通过查看 `pg_proc` 系统表来获取到其对应的代码实现函数名。

```sql
postgres=# SELECT proname, prosrc FROM pg_proc WHERE proname = 'pg_export_snapshot';
      proname       |       prosrc
--------------------+--------------------
 pg_export_snapshot | pg_export_snapshot
(1 row)
```

随后我们可以到源码中找到 `pg_export_snapshot()` 函数的实现。

```c
/*
 * pg_export_snapshot
 *      SQL-callable wrapper for ExportSnapshot.
 */
Datum
pg_export_snapshot(PG_FUNCTION_ARGS)
{
    char       *snapshotName;

    snapshotName = ExportSnapshot(GetActiveSnapshot());
    PG_RETURN_TEXT_P(cstring_to_text(snapshotName));
}
```

从上面的代码可以看到，核心在 `GetActiveSnapshot()` 和 [`ExportSnapshot()`][] 两个函数中，`GetActiveSnapshot()` 用于获取当前活跃的快照（本文将不在此处详细说明），本文主要关注 [`ExportSnapshot()`][] 函数导出快照的处理。

[`ExportSnapshot()`][] 函数主要做了以下几件事情：

1. 复制快照、封装为 `ExportedSnapshot` 对象并将其链接到 `exportedSnapshots` 链表中；
2. 格式化快照信息；
3. 打开文件并将格式化后的快照信息写入到 `pg_snapshots` 目录下面。

下面是一个导出快照的示例：

```bash
$ cat pg_snapshots/00000003-00000010-2
vxid:3/16
pid:31163
dbid:5
iso:1
ro:0
xmin:740
xmax:744
xcnt:2
xip:740
xip:742
sof:0
sxcnt:1
sxp:741
rec:0
```

上面的文件包含了导出快照的完整信息，下面是对其的解读：

* 虚拟事务 ID，后端进程 ID 和本地事务 ID 组成 (`MyProc->backendId` 和 `MyProc->lxid`)
* 进程 ID，`MyProcPid`
* 数据库 OID，`MyDatabaseId`
* 事务隔离级别
  - `XACT_READ_UNCOMMITTED` -> 0
  - `XACT_READ_COMMITTED` -> 1
  - `XACT_REPEATABLE_READ` -> 2
  - `XACT_SERIALIZABLE` -> 3
* 事务模式
  - `READ ONLY` -> 0
  - `READ WRITE` -> 1
* `xmin`，最早正在运行的事务 ID
* `xmax`，最近已完成的事务 ID + 1
* 正在运行的事务数量
* 正在运行的事务列表，换行符分割每个事务
* 子事务是否溢出
  - 子事务溢出则没有子事务相关的信息
  - 子事务没有溢出则包含
    - 子事务的数量
	- 子事务列表
* 快照是否在恢复时获取的

### 快照导入

上述就是快照导出的内容，接下来我们看看快照导入，[`ImportSnapshot()`][] 负责快照的导入工作（对应 [`SET TRANSACTION SANPSHOT snapshot_id`][`SET TRANSACTION`] 语法），该函数的主要工作是从 `pg_snapshots` 目录下读取快照文件，并将文件内容解析到 `SnapshotData` 对象中，随后进行一些必要的检查，最后在交由 [`SetTransactionSnapshot()`][] 函数处理，[`SetTransactionSnapshot()`][] 函数主要做了以下几件事情：

1. 调用 `GetSnapshotData()` 函数获取当前快照信息，虽然在这里不会使用该函数计算的快照，但是通过这个函数可以帮助我们做以下两件事：
   - 确保 `CurrentSnapshotData` 的事务 ID 数组已经分配
   - 更新快照中有关 `GlobalVis*` 的信息
2. 复制快照信息到 `CurrentSnapshot` 中，包括：
   - 最早正在运行的事务 ID（`xmin`）
   - 最近已完成的事务 ID + 1（`xmax`）
   - 活跃事务信息（`xcnt`, `xip`）
   - 子事务信息（`subxcnt`, `subxip`）
   - 子事务是否溢出（`suboverflowed`）
   - 快照是否在恢复时获取的（`takenDuringRecovey`）
3. 设置第一个事务快照 `FirstXactSanpshot`（在 `REPEATABLE READ` 或更高的隔离级别下，我们需要保证事务快照在整个事务生命周期可见）

PostgreSQL 中的快照导出、导入流程并不复杂，但实现的功能却比较强大。例如在 [`pg_dump`][] 应用程序中，当使用并行模式备份时，就需要利用到这个功能。

## 参考

[1] https://www.postgresql.org/docs/14/functions-admin.html
[2] https://www.postgresql.org/docs/14/sql-set-transaction.html


[`SET TRANSACTION`]: https://www.postgresql.org/docs/14/sql-set-transaction.html
[`pg_export_snapshot()`]: https://www.postgresql.org/docs/14/functions-admin.html#FUNCTIONS-SNAPSHOT-SYNCHRONIZATION-TABLE
[`PREPARE TRANSACTION`]: https://www.postgresql.org/docs/14/sql-prepare-transaction.html
[`ExportSnapshot()`]: https://github.com/postgres/postgres/blob/REL_14_STABLE/src/backend/utils/time/snapmgr.c#L1116
[`ImportSnapshot()`]: https://github.com/postgres/postgres/blob/REL_14_STABLE/src/backend/utils/time/snapmgr.c#L1387
[`SetTransactionSnapshot()`]: https://github.com/postgres/postgres/blob/REL_14_STABLE/src/backend/utils/time/snapmgr.c#L502
[`pg_dump`]: https://www.postgresql.org/docs/14/app-pgdump.html

<div class="just-for-fun">
笑林广记 - 田主见鸡

一富人有余田数亩，租与张三者种，每亩索鸡一只。
张三将鸡藏于背后，田主遂作吟哦之声曰：“此田不与张三种。”
张三忙将鸡献出，田主又吟曰：“不与张三却与谁？”
张三曰：“初问不与我，后又与我何也？”
田主曰：“初乃无稽（鸡）之谈，后乃见机（鸡）而作也。”
</div>
