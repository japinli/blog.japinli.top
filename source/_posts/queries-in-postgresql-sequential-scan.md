---
title: "【译】PostgreSQL 中的查询 - 顺序扫描"
date: 2022-04-06 21:44:07 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
---

在之前的文章中，我们讨论了系统如何{% post_link queries-in-postgresql-query-execution-stages 规划查询 %}以及如何{% post_link queries-in-postgresql-statistics 收集统计信息%}以选择最佳执行计划。从这篇文章开始，后续的文章将终点关注计划的本质、它的组成以及如何执行。

在本文中，我将演示规划器如何计算执行成本。我还将讨论访问方法（Access Methods）以及它们如何影响这些成本，并使用顺序扫描方法作为说明。最后，我将谈谈 PostgreSQL 中的并行执行的工作原理以及何时使用它。

我将在本文后面使用几个看似复杂的数学公式。您无需记住任何一个公式也可以理解规划器是如何工作的；它们只是为了显示我的数据来源。

<!--more-->

## 可插拔存储引擎

PostgreSQL 将数据存储在磁盘上的方法并不是对所有的负载类型都是最佳的。幸运的是，您有选择的权利。PostgreSQL 12 及更高版本兑现了其可扩展性的承诺，实现了自定义表访问方法（存储引擎），不过它默认只带有一个对表存储引擎（heap）：

```sql
SELECT amname, amhandler FROM pg_am WHERE amtype = 't';
```

```
 amname |      amhandler
−−−−−−−−+−−−−−−−−−−−−−−−−−−−−−−
 heap   | heap_tableam_handler
(1 row)
```

您可以在创建表时指定存储引擎 `(CREATE TABLE ... USING)`。如果没有指定，那么将使用 `default_table_access_method` 中定义的引擎。

系统表 `pg_am` 中存储了引擎名称（`amname` 列）以及它们的处理函数（`amhandler`）。每个存储引擎都伴随着一个内核需要的接口，以便充分的使用存储引擎。处理函数的工作是返回有关接口所有必需的信息。

大多数存储引擎利用现有内核的系统组件：

* 事务管理器，包括 ACID 的支持以及快照隔离
* 缓冲区管理
* I/O 子系统
* TOAST
* 查询优化器和执行器
* 索引支持

存储引擎不一定会使用所有这些组件，但这种能力依然存在。接着，存储引擎必须定义一些东西：

* 行版本格式和数据结构
* 表扫描例程
* 插入、删除、更新和 lock 例程
* 行版本可见性规则
* VACUUM 和 ANALYZE 过程
* 顺序扫描成本估算过程

传统上，PostgreSQL 使用单一的数据存储系统，即直接内置到内核中，没有接口。现在，创建一个新的接口是一项挑战--适应标准引擎的所有长期特殊性并且不干扰其他访问方法。由于开销巨大，现有的[通用的 WAL 日志](https://postgrespro.com/docs/postgresql/13/generic-wal)机制很少成为一种选择。您可以为新的日志记录类型设计一个单独的接口，但这会使崩溃恢复依赖于外部代码，这是您一直想要避免的。到目前为止，重构内核代码以适应新引擎仍然是唯一可行的选择。

说到新的存储引擎，目前有几个正在开发中。以下是一些比较突出的：

* [Zheap][] 是针对表膨胀而设计的存储引擎。它实现就地行版本更新并将快照数据存储在单独的 undo 日志中。该引擎对更新密集型工作负载有效。该存储引擎设计类似于 Oracle 的存储引擎（比如索引访问方法接口不支持自带多版本并发控制的索引）。

* [Zedstore][] 实现了列式存储，旨在更有效地处理 OLAP 事务。它将数据组织到由行版本 ID 组成的主 B 树中，并且每一列都存储在其自己的 B 树中，该 B 树引用主 B 树。未来，该存储引擎可能支持在一棵树中存储多个列，本质上成为一个混合存储引擎。

## 顺序扫描

存储引擎确定表数据在磁盘上的物理分布方式并提供访问它的方法。顺序扫描是一种对主表 fork 的文件进行完整扫描的方法。在每一页上，系统检查每一行版本的可见性，并丢弃与查询不匹配的版本。

{% asset_img seqscan1-en.png %}

扫描是通过缓冲区高速缓存完成的。系统使用一个小的环形缓冲区来防止较大的表从缓存中淘汰可能有用的数据。当另一个进程需要扫描同一张表时，它会加入缓冲环，节省磁盘读取时间。因此，扫描不一定从文件的开头开始。

顺序扫描是扫描整个表或其中重要部分的最具成本效益的方法。换句话说，当选择率较低时，顺序扫描是有效的。在更高的选择率下，当表中只有一小部分行满足筛选要求时，通常最好使用索引扫描。

### 示例

执行计划中的顺序扫描阶段由 `Seq Scan` 节点表示。

```sql
EXPLAIN SELECT * FROM flights;
```

```
                           QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=0.00..4772.67 rows=214867 width=63)
(1 row)
```

行数估计是一个基本的统计量：

```sql
SELECT reltuples FROM pg_class WHERE relname = 'flights';
```

```
 reltuples
−−−−−−−−−−−
    214867
(1 row)
```

在估算成本时，优化器会考虑磁盘输入/输出和 CPU 处理成本。

I/O 成本按照读取单个页面的开销乘以表中的页面数来估算，前提是这些页面按顺序读取。当缓冲区管理器向操作系统请求一个页面时，系统实际上从磁盘读取了更大的数据块，因此接下来的几个页面可能已经在操作系统的缓存中。这使得顺序读取成本（规划器中由 `seq_page_cost` 参数给出权重，默认为 1）大大低于随机读取的成本（由 `random_page_cost` 参数给出权重，默认为 4）。

默认权重适用于 HDD 驱动器。如果您使用 SSD，则可以将 `random_page_cost` 设置得更低（`seq_page_cost` 通常保留为 1 作为参考值）。成本取决于硬件，因此通常在表空间级别设置 `(ALTER TABLESPACE ... SET)`。

```sql
SELECT relpages, current_setting('seq_page_cost') AS seq_page_cost,
  relpages * current_setting('seq_page_cost')::real AS total
FROM pg_class WHERE relname='flights';
```

```
 relpages | seq_page_cost | total
−−−−−−−−−−+−−−−−−−−−−−−−−−+−−−−−−−
     2624 |             1 | 2624
(1 row)
```

这个公式完美地说明了由于后期清理导致的表膨胀的结果。主表越大，要获取的页面就越多，无论这些页面中的数据是否是最新的。

CPU 处理成本估计为每个行版本的处理成本之和（规划器中由 `cpu_tuple_cost` 给出权重，默认为 0.01）：

```sql
SELECT reltuples,
  current_setting('cpu_tuple_cost') AS cpu_tuple_cost,
  reltuples * current_setting('cpu_tuple_cost')::real AS total
FROM pg_class WHERE relname='flights';
```

```
 reltuples | cpu_tuple_cost | total
−−−−−−−−−−−+−−−−−−−−−−−−−−−−+−−−−−−−−−
    214867 |           0.01 | 2148.67
(1 row)
```

两项成本之后构成了计划的总成本。该计划的启动成本为零，因为顺序扫描不需要任何准备步骤。

任何表过滤器都将列在计划中 `Seq Scan` 节点的下方。行数估计将考虑过滤器的选择性，成本估计将包括它们的处理成本。`EXPLAIN ANALYZE` 命令显示扫描的实际行数和过滤器删除的行数：

```sql
EXPLAIN (analyze, timing off, summary off)
SELECT * FROM flights WHERE status = 'Scheduled';
```

```
                   QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights
   (cost=0.00..5309.84 rows=15383 width=63)
   (actual rows=15383 loops=1)
   Filter: ((status)::text = 'Scheduled'::text)
   Rows Removed by Filter: 199484
(5 rows)
```

### 带有聚合的计划示例

考虑这个涉及聚合的执行计划：

```sql
EXPLAIN SELECT count(*) FROM seats;
```

```
                          QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Aggregate  (cost=24.74..24.75 rows=1 width=8)
   −> Seq Scan on seats (cost=0.00..21.39 rows=1339 width=0)
(2 rows)
```

该计划中有两个节点：`Aggregate` 和 `Seq Scan`。`Seq Scan` 扫描表并将数据向上传递给 `Aggregate`，而 `Aggregate` 则持续对行进行计数。

注意到 `Aggregate` 有一个启动成本：聚合函数本身的成本，即需要计算来自子节点的所有行。估计值是根据输入行数乘以任意操作的成本来计算的（`cpu_operator_cost`，默认为 0.0025）：

```sql
SELECT
  reltuples,
  current_setting('cpu_operator_cost') AS cpu_operator_cost,
  round((
    reltuples * current_setting('cpu_operator_cost')::real
  )::numeric, 2) AS cpu_cost
FROM pg_class WHERE relname='seats';
```

```
 reltuples | cpu_operator_cost | cpu_cost
−−−−−−−−−−−+−−−−−−−−−−−−−−−−−−−+−−−−−−−−−−
      1339 |            0.0025 | 3.35
(1 row)
```

随后在该估计值的基础上加上 `Seq Scan` 节点的总成本。

然后，`Aggregate` 的总成本需要加上 `cpu_tuple_cost` 的成本，`cpu_tuple_cost` 是结果输出行的处理成本：

```sql
WITH t(cpu_cost) AS (
  SELECT round((
    reltuples * current_setting('cpu_operator_cost')::real
  )::numeric, 2)
  FROM pg_class WHERE relname = 'seats'
)
SELECT 21.39 + t.cpu_cost AS startup_cost,
  round((
    21.39 + t.cpu_cost +
    1 * current_setting('cpu_tuple_cost')::real
  )::numeric, 2) AS total_cost
FROM t;
```

```
 startup_cost | total_cost
−−−−−−−−−−−−−−+−−−−−−−−−−−−
        24.74 |      24.75
(1 row)
```

## 并行执行计划

在 PostgreSQL 9.6 及更高的版本中，计划的并行执行是很重要的一件事。它是这样工作的：leader 进程创建（通过 postmaster 进程）多个 worker 进程，然后这些进程同时并行执行计划的一部分，最后由 leader 进程在 `Gather` 节点收集结果。当 leader 进程没有收集数据时，它也可以参与并行计算。

您可以通过设置 `parallel_leader_participation` 为 0 来禁止 leader 进程参与并行计算，但是仅在 11 及之后的版本中支持。

{% asset_img seqscan2-en.png %}

产生新进程并在它们之间发送数据会增加总成本，因此您通常最好不要使用并行执行。

此外，有些操作根本无法并行执行。即使启用了并行模式，leader 进程仍将单独按顺序执行某些步骤。


### 并行顺序扫描

该方法的名称可能听起来有争议，声称同时是并行和顺序的，但这正是 `Parallel Seq Scan` 节点所做的事情。从磁盘的角度来看，所有文件页面都是按顺序获取的，与常规顺序扫描相同。然而，读取是由多个并行工作的进程完成的。这些进程在一个特殊的共享内存部分中同步它们的读取计划，以避免重复读取相同的页面。

另一方面，操作系统不认为这种获取是顺序的。从操作系统的角度来看，它只是几个进程请求看似随机页面。这打破了通过常规顺序扫描为我们提供的预取服务。这个问题在 PostgreSQL 14 中得到了修复，当系统开始时，为每个并行进程分配几个连续的页面来读取而不是一个页面。

并行扫描本身对成本效率没有多大帮助。事实上，它所做的只是在常规页面读取成本之上增加了进程之间的数据传输成本。但是，如果工作进程不仅扫描行，还对它们进行某种程度的处理（例如聚合），那么您可能会节省大量时间。

### 带有聚合的并行计划示例

优化器在一个大表上看到这个简单的聚合查询，并提出最佳策略是并行模式：

```sql
EXPLAIN SELECT count(*) FROM bookings;
```

```
                          QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Finalize Aggregate  (cost=25442.58..25442.59 rows=1 width=8)
   −> Gather (cost=25442.36..25442.57 rows=2 width=8)
       Workers Planned: 2
       −> Partial Aggregate
          (cost=24442.36..24442.37 rows=1 width=8)
          −> Parallel Seq Scan on bookings
              (cost=0.00..22243.29 rows=879629 width=0)
(7 rows)
```

`Gather` 节点下的所有节点都是计划中并行的部分。它将由所有的 worker 进程（在本例中，包含 2 个 worker 进程）和 leader 进程（除非禁用 `parallel_leader_participation` 选项）执行。`Gather` 节点和它上面的所有节点由 leader 进程顺序执行。

扫描本身发生在 `Parallel Seq Scan` 节点。`rows` 字段显示一个进程要处理的行的估计值。计划包含了两个 worker 进程，并且 leader 进程也将提供帮助，因此行估计值等于总表行数除以 2.4（worker 进程为 2，leader 进程为 0.4，worker 进程越多，leader 进程贡献越少）。

```sql
SELECT reltuples::numeric, round(reltuples / 2.4) AS per_process
FROM pg_class WHERE relname = 'bookings';
```

```
 reltuples | per_process
−−−−−−−−−−−+−−−−−−−−−−−−−
   2111110 |      879629
(1 row)
```

`Parallel Seq Scan` 成本的估算方式与 `Seq Scan` 成本估算大致相同。我们通过让每个进程处理更少的行来赢得时间，但我们仍然通过和通过读取表，因此 I/O 成本不受影响：

```sql
SELECT round((
  relpages * current_setting('seq_page_cost')::real +
  reltuples / 2.4 * current_setting('cpu_tuple_cost')::real
)::numeric, 2)
FROM pg_class WHERE relname = 'bookings';
```

```
  round
−−−−−−−−−−
 22243.29
(1 row)
```

`Partial Aggregate` 节点将聚合 worker 进程产生的所有数据（在本例中是统计行数）。

聚合的成本估算与之前的方式相同，需要加上扫描的成本。

```sql
WITH t(startup_cost) AS (
  SELECT 22243.29 + round((
    reltuples / 2.4 * current_setting('cpu_operator_cost')::real
  )::numeric, 2)
  FROM pg_class WHERE relname='bookings'
)
SELECT startup_cost,
  startup_cost + round((
    1 * current_setting('cpu_tuple_cost')::real
  )::numeric, 2) AS total_cost
FROM t;
```

```
 startup_cost | total_cost
−−−−−−−−−−−−−−+−−−−−−−−−−−−
     24442.36 |   24442.37
(1 row)
```

下一个 `Gathere` 节点则由 leader 进程来执行。该节点启动 worker 进程并收集它们输出的数据。

启动一个 worker 进程（或多个；成本不变）的成本由参数 `parallel_setup_cost`（默认为 1000）定义。将单行从一个进程发送到另一个进程的成本由 `parallel_tuple_cost`（默认为 0.1）设置。大部分节点成本是并行进程的初始化。它被添加到 `Partial Aggregate` 节点的启动成本中。它还包括两个数据传输的成本；该成本被添加到 `Partial Aggregate` 节点的总成本中。

```sql
SELECT
24442.36 + round(
  current_setting('parallel_setup_cost')::numeric,
2) AS setup_cost,
24442.37 + round(
  current_setting('parallel_setup_cost')::numeric +
  2 * current_setting('parallel_tuple_cost')::numeric,
2) AS total_cost;
```

```
 setup_cost | total_cost
−−−−−−−−−−−−+−−−−−−−−−−−−
   25442.36 |   25442.57
(1 row)
```

`Finalize Aggregate` 节点将 `Gather` 节点收集的部分数据连接在一起。它的成本估算就像使用常规的 `Aggregate` 一样。启动成本包括三个聚合的成本和 `Gather` 节点的总成本（因为 `Finalize Aggregate` 需要其所有输出进行计算）。总成本之上的额外开销是一行输出结果的开销。

```sql
WITH t(startup_cost) AS (
  SELECT 25442.57 + round((
    3 * current_setting('cpu_operator_cost')::real
  )::numeric, 2)
  FROM pg_class WHERE relname = 'bookings'
)
SELECT startup_cost,
  startup_cost + round((
    1 * current_setting('cpu_tuple_cost')::real
  )::numeric, 2) AS total_cost
FROM t;
```

```
 startup_cost | total_cost
−−−−−−−−−−−−−−+−−−−−−−−−−−−
     25442.58 |   25442.59
(1 row)
```

### 并行处理的限制

我们应该牢记并行处理的几个限制。

#### worker 进程数

后台 worker 进程的使用不限于并行查询执行：它们由逻辑复制机制使用，并且可以由扩展创建。系统最多可以同时运行 `max_worker_processes` 个后台 worker 进程（默认为 8 个）。

其中，最多可以将 `max_parallel_workers`（默认情况下也是 8 个）分配给并行查询执行。

每个 leader 进程允许的 worker 进程数由 `max_parallel_workers_per_gather` 参数给出（默认为 2 个）。

您可以根据以下几个因素选择更改这些值：

* 硬件配置：系统必须有备用处理器内核。
* 表大小：并行查询对较大的表很有帮助。
* 负载类型：从并行执行中受益最多的查询应该很普遍。

这些因素对于 OLAP 系统通常是正确的，而对于 OLTP 系统通常是错误的。

规划器甚至不会考虑并行扫描，除非它期望读取至少 `min_parallel_table_scan_size` 的数据（默认为 8MB）。

下面是计算计划 worker 进程数的公式：

{% asset_img seqscan3-en.png %}

本质上，每当表大小增加三倍时，规划器就会增加一个并行 worker 进程。这是一个带有默认参数的示例表。

| 表 (MB) | worker 进程数 |
|:-------:|:-------------:|
| 8       | 1             |
| 24      | 2             |
| 72      | 3             |
| 216     | 4             |
| 648     | 5             |
| 1944    | 6             |

您可以使用表存储参数 `parallel_workers` 显式地设置 worker 进程的数量。不过，worker 进程的数量仍然受到 `max_parallel_workers_per_gather` 参数的限制。

让我们查询一个 19MB 的小表。这将只会计划和创建一个 worker 进程（查看 `Workers Planned` 和 `Workers Launched`）：

```sql
EXPLAIN (analyze, costs off, timing off)
SELECT count(*) FROM flights;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Finalize Aggregate (actual rows=1 loops=1)
   −> Gather (actual rows=2 loops=1)
       Workers Planned: 1
       Workers Launched: 1
       −> Partial Aggregate (actual rows=1 loops=2)
           −> Parallel Seq Scan on flights (actual rows=107434 lo...
(6 rows)
```

现在让我们查询一个 105MB 的表。系统将只创建两个 worker 进程，遵守 `max_parallel_workers_per_gather` 的限制。

```sql
EXPLAIN (analyze, costs off, timing off)
SELECT count(*) FROM bookings;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Finalize Aggregate (actual rows=1 loops=1)
   −> Gather (actual rows=3 loops=1)
       Workers Planned: 2
       Workers Launched: 2
       −> Partial Aggregate (actual rows=1 loops=3)
           −> Parallel Seq Scan on bookings (actual rows=703703 l...
(6 rows)
```

如果增加限制，则会创建三个 worker 进程：

```sql
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
SELECT pg_reload_conf();
EXPLAIN (analyze, costs off, timing off)
SELECT count(*) FROM bookings;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Finalize Aggregate (actual rows=1 loops=1)
   −> Gather (actual rows=4 loops=1)
       Workers Planned: 3
       Workers Launched: 3
       −> Partial Aggregate (actual rows=1 loops=4)
           −> Parallel Seq Scan on bookings (actual rows=527778 l...
(6 rows)
```

当查询执行时，如果计划的 worker 进程并可用的 worker 进程插槽要多，系统也只会创建与可用的 worker 进程插槽相等的 worker 进程。

#### 不可并行的查询

[并不是所有的查询都可以并行](https://postgrespro.com/docs/postgresql/13/when-can-parallel-query-be-used)。这些是不可并行化查询的类型：

* 修改或锁定数据的查询（`UPDATE`, `DELETE`, `SELECT FOR UPDATE` 等）。

  在 PostgreSQL 11 中，诸如 `CREATE TABLE AS`, `SELECT INTO` 和 `CREATE MATERIALIZED VIEW` 这样的查询仍然是可以并行的（在 14 和更高的版本 `REFRESH MATERIALIZED VIEW` 同样可以并行）。

  但是，即使在这些情况下，所有 `INSERT` 操作仍将按顺序执行。

* 可以在执行期间暂停的任何查询。游标内的查询，包括 PL/pgSQL `FOR` 循环中的查询。

* 调用 `PARALLEL UNSAFE` 函数的查询。默认情况下，这包括所有用户定义的函数和一些标准函数。您可以从系统表中获取不安全函数的完整列表：
  ```
  SELECT * FROM pg_proc WHERE proparallel = 'u';
  ```

* 从已经并行化的查询中调用的函数中的查询（避免递归创建新的后台 worker 进程）。

未来的 PostgreSQL 版本可能会消除其中一些限制。例如，版本 12 添加了在 `Serializable` 隔离级别并行化查询的能力。

查询不会并行运行的可能原因有多种：

* 它首先是不可并行的。

* 您的配置阻止创建并行计划（包括当表小于并行化阈值时）。

* 并行计划比顺序计划成本更高。

如果您想强制并行执行查询（用于研究或其他目的），您可以将参数 `force_parallel_mode` 设置为 `on`。这将使规划器总是产生并行计划，除非查询是严格不可并行的：

```sql
EXPLAIN SELECT * FROM flights;
```

```
                           QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=0.00..4772.67 rows=214867 width=63)
(1 row)
```

```sql
SET force_parallel_mode = on;
EXPLAIN SELECT * FROM flights;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Gather (cost=1000.00..27259.37 rows=214867 width=63)
   Workers Planned: 1
   Single Copy: true
   −> Seq Scan on flights (cost=0.00..4772.67 rows=214867 width=63)
(4 rows)
```

#### 并行受限的查询

一般来说，并行计划的好处主要取决于计划中有多少是并行兼容的。然而，有些操作在技术上不会阻止并行化，[但只能由 leader 进程按顺序执行](https://postgrespro.com/docs/postgresql/13/parallel-safety)。换句话说，这些操作不能出现在计划的并行部分，在 `Gather` 节点下面。

__不可扩展的子查询__。包含不可扩展子查询的操作的一个基本示例是公用表表达式扫描（即下面的 `CTE Scan` 扫描节点）：

```sql
EXPLAIN (costs off)
WITH t AS MATERIALIZED (
  SELECT * FROM flights
)
SELECT count(*) FROM t;
```

```
         QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Aggregate
   CTE t
     −> Seq Scan on flights
   −> CTE Scan on t
(4 rows)
```

如果公用表表达式没有进行物化（这只会在 PostgreSQL 12 及更高的版本中可能），那么这里将不会有 `CTE Scan` 节点并且也不会出现问题。

如果它是更快的选项，表达式本身可以并行处理，

```sql
EXPLAIN (costs off)
WITH t AS MATERIALIZED (
  SELECT count(*) FROM flights
)
SELECT * FROM t;
```

```
                   QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 CTE Scan on t
   CTE t
     −> Finalize Aggregate
         −> Gather
             Workers Planned: 1
             −> Partial Aggregate
                 −> Parallel Seq Scan on flights
(7 rows)
```

不可扩展子查询的另一个示例是带有 `SubPlan` 节点的查询。

```sql
EXPLAIN (costs off)
SELECT *
FROM flights f
WHERE f.scheduled_departure > ( -- SubPlan
  SELECT min(f2.scheduled_departure)
  FROM flights f2
  WHERE f2.aircraft_code = f.aircraft_code
);
```

```
                      QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights f
   Filter: (scheduled_departure > (SubPlan 1))
   SubPlan 1
     −> Aggregate
         −> Seq Scan on flights f2
            Filter: (aircraft_code = f.aircraft_code)
(6 rows)
```

前两行显示主查询的计划：扫描 `flights` 表并过滤每一行。过滤条件包括一个子查询，其计划遵循主计划。`SubPlan` 节点执行多次：在这种情况下，每个扫描行执行一次。

父节点 `Seq Scan` 无法并行化，因为它需要 `SubPlan` 输出才能继续。

最后一个示例是执行由 `InitPlan` 节点表示的不可扩展子查询。

```sql
EXPLAIN (costs off)
SELECT *
FROM flights f
WHERE f.scheduled_departure > ( -- SubPlan
  SELECT min(f2.scheduled_departure) FROM flights f2
  WHERE EXISTS ( -- InitPlan
    SELECT *
    FROM ticket_flights tf
    WHERE tf.flight_id = f.flight_id
  )
);
```

```
                      QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights f
   Filter: (scheduled_departure > (SubPlan 2))
   SubPlan 2
     −> Finalize Aggregate
         InitPlan 1 (returns $1)
           −> Seq Scan on ticket_flights tf
               Filter: (flight_id = f.flight_id)
         −> Gather
             Workers Planned: 1
             Params Evaluated: $1
             −> Partial Aggregate
                 −> Result
                     One−Time Filter: $1
                     −> Parallel Seq Scan on flights f2
(14 rows)
```

与 `SubPlan` 不同，`InitPlan` 节点只执行一次（在这种情况下，每次 `SubPlan 2` 执行一次）。

`InitPlan` 节点的父节点不能并行化，但使用 `InitPlan` 输出的节点可以，如此处所示。

__临时表__。临时表只能按顺序扫描，因为只有 leader 进程才能访问它们。

```sql
CREATE TEMPORARY TABLE flights_tmp AS SELECT * FROM flights;
EXPLAIN (costs off)
SELECT count(*) FROM flights_tmp;
```

```
          QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Aggregate
   −> Seq Scan on flights_tmp
(2 rows)
```

__并行受限的函数__。调用标记为 `PARALLEL RESTRICTED` 的函数只允许在计划的顺序部分内。您可以在系统表中找到受限函数的列表：

```sql
SELECT * FROM pg_proc WHERE proparallel = 'r';
```

只有在彻底研究了现有的限制并非常小心之后，才能标记您自己的函数为 `PARALLEL RESTRICTED`（更不用说 `PARALLEL SAFE`）。

未完待续。

## 译者著

本文翻译自 [PostgreSQL Pro](https://postgrespro.com/) 的 [Queries in PostgreSQL: 3. Sequential scan](https://postgrespro.com/blog/pgsql/5969403)。

<div class="just-for-fun">
笑林广记 - 酸臭

小虎谓老虎曰：“今日出山，搏得一人食之，滋味甚异，上半截酸，下半截臭，究竟不知是何等人。”
老虎曰：“此必是秀才纳监者。”
</div>

[Zheap]: https://github.com/EnterpriseDB/zheap
[Zedstore]: https://github.com/greenplum-db/postgres/tree/zedstore
