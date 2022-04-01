---
title: "【译】PostgreSQL 中的查询 - 查询执行阶段"
date: 2022-03-21 23:32:56 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
---

您好！我正在开始另一个关于 PostgreSQL 内部的文章系列。这一篇将侧重于查询计划和执行机制。本系列将涵盖：

1. 查询执行阶段（本文）
2. {% post_link queries-in-postgresql-statistics 统计信息 %}
3. 顺序扫描
4. 索引扫描
5. 嵌套循环连接
6. Hash 连接
7. 归并连接

本文借鉴了我们的 [QPT 查询优化](https://postgrespro.ru/education/courses/QPT)课程（即将推出英文版），但主要关注查询执行的内部机制，而将优化方面放在一边。另请注意，本系列文章是针对 PostgreSQL 14 编写的。

<!--more-->

## 简单查询协议

PostgreSQL 客户端-服务器协议的基本目的有两个：它向服务器发送 SQL 查询，并接收整个执行结果作为响应。服务器收到要执行的查询需经过几个阶段。

### 解析

首先，解析查询文本，以便服务器准确了解需要做什么。

词法分析器（**Lexer**）和解析器（**Parser**）。词法分析器负责识别查询字符串中的词位（如 SQL 关键字、字符串和数字文字等），而解析器确保生成的词位集在语法上是有效的。解析器和词法分析器是使用标准工具 Bison 和 Flex 实现的。

解析的查询表示为抽象语法树。例如：

```sql
SELECT schemaname, tablename
FROM pg_tables
WHERE tableowner = 'postgres'
ORDER BY tablename;
```

上述 SQL 语句将在后端内存中构建一棵树。下图以高度简化的形式显示了树。树的节点用查询的相应部分标记。

{% asset_img query1.png %}

`RTE` 是一个比较晦涩的缩写，它表示 `Range Table Entry`。PostgreSQL 源码中的 `range table` 指的是表、子查询、连接结果 -- 换句话说，SQL 语句操作的任何记录集。

语义分析器（**Semantic analyzer**)。语义分析器通过名称确定数据库中是否有查询引用的表和其它对象，以及用户是否有权访问这些对象。语义分析所需的所有信息都存储在系统表中。

语义分析器从解析器接收解析树并重建它，并用对特定数据库对象、数据类型信息等的引用来补充它。

如果参数 `debug_print_parse` 开启，则完整的树将显示在服务器消息日志中，尽管这没有什么实际意义。

### 转换

接下来，可以转换（重写）查询。

系统核心将转换用于多种目的。其中之一是将解析树中的视图名称替换为与该视图的查询相对应的子树。

上例中的 `pg_tables` 是一个视图，转换后解析树将采用以下形式：

{% asset_img query2.png %}

此解析树对应于以下查询（尽管所有操作都只在树上执行，而不是在查询文本上）：

```sql
SELECT schemaname, tablename
FROM (
    -- pg_tables
    SELECT n.nspname AS schemaname,
      c.relname AS tablename,
      pg_get_userbyid(c.relowner) AS tableowner,
      ...
    FROM pg_class c
      LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
    WHERE c.relkind = ANY (ARRAY['r'::char, 'p'::char])
)
WHERE tableowner = 'postgres'
ORDER BY tablename;
```

解析树反映查询的句法结构，但不反映执行操作的顺序。

行级安全性在转换阶段实施。系统核心使用转换的另一个例子是版本 14 中递归查询的 SEARCH 和 CYCLE 子句的实现。

PostgreSQL 支持自定义转换，用户可以使用重写规则系统来实现。

规则系统旨在作为 Postgres 的[主要功能之一](https://dsf.berkeley.edu/papers/ERL-M85-95.pdf)。这些规则得到了项目基础的支持，并在早期开发过程中反复重新设计。这是一个强大的机制，但难以理解和调试。甚至有人提议从 PostgreSQL 中完全删除规则，但没有得到普遍支持。在大多数情况下，使用触发器而不是规则更安全、更方便。

如果参数 `debug_print_rewritten` 开启，则完整转换的解析树将显示在服务器消息日志中。

### 规划

SQL 是一种声明性语言：查询指定要检索什么，但不指定如何检索它。

任何查询都可以通过多种方式执行。解析树中的每个操作都有多个执行选项。例如，您可以通过读取整个表并丢弃不需要的行来从表中检索特定记录，或者您可以使用索引来查找与您的查询匹配的记录。数据集总是成对连接。连接顺序的变化会产生大量的执行选项。然后有多种方法可以将两组记录连接在一起。例如，您可以逐个遍历第一个集合中的记录并在另一个集合中查找匹配的记录，或者您可以先对两个集合进行排序，然后将它们合并在一起。不同的方法在某些情况下表现更好，在另一些情况下表现更差。

最佳计划的执行速度可能比非最佳计划快几个数量级。这就是为什么优化解析查询的规划器是系统中最复杂的元素之一。

计划树（**Plan tree**）。执行计划也可以表示为树，但其节点是对数据的物理操作而不是逻辑操作。

{% asset_img query3.png %}

如果参数 `debug_print_plan` 开启，则完整的计划树将显示在服务器消息日志中。这是非常不切实际的，因为日志非常混乱。更方便的选择是使用 `EXPLAIN` 命令：

```sql
EXPLAIN
SELECT schemaname, tablename
FROM pg_tables
WHERE tableowner = 'postgres'
ORDER BY tablename;
```

```
                            QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Sort  (cost=21.03..21.04 rows=1 width=128)
   Sort Key: c.relname
   −> Nested Loop Left Join  (cost=0.00..21.02 rows=1 width=128)
       Join Filter: (n.oid = c.relnamespace)
       −> Seq Scan on pg_class c  (cost=0.00..19.93 rows=1 width=72)
           Filter: ((relkind = ANY ('{r,p}'::"char"[])) AND (pg_g...
       −> Seq Scan on pg_namespace n  (cost=0.00..1.04 rows=4 wid...
(7 rows)
```

该图显示了树的主要节点。相同的节点在 `EXPLAIN` 输出中用箭头标记。

`Seq Scan` 节点代表读表操作，而 `Nested Loop` 节点代表连接操作。这里有两个有趣的点需要注意：

* 初始表之一从计划树中消失了，因为规划器发现不需要处理查询并将其删除。
* 估计要处理的行数和每个节点旁边的处理成本。

计划搜索（**Plan search**）。为了找到最佳计划，PostgreSQL 使用了基于成本的查询优化器（*cost-based query optimizer*）。优化器会检查各种可用的执行计划并估计所需的资源量，例如 I/O 操作和 CPU 周期。这个计算出来的估计，转换成任意单位，被称为计划成本（*plan cost*）。选择成本最低的计划来执行。

问题是，可能的计划数量随着连接数量的增加而呈指数增长，即使对于相对简单的查询，也无法一一筛选所有计划。因此，动态规划和启发式用于限制搜索范围。这允许在合理的时间内精确地解决查询中更多表的问题，但所选计划不能保证是真正最优的，因为计划员使用简化的数学模型，并且可能使用不精确的初始数据。

连接顺序（**Ordering joins**）。可以以特定方式构建查询，以显着缩小搜索范围（有可能错过找到最佳计划的机会）

* 公共表表达式通常与主查询分开优化。从版本 12 开始，可以使用 MATERIALIZE 子句强制执行此操作。
* 来自非 SQL 函数的查询与主查询分开优化。（在某些情况下，SQL 函数可以内联到主查询中。）
* `join_collapse_limit` 参数与显式 JOIN 子句以及 `from_collapse_limit` 参数与子查询一起可以定义某些连接的顺序，具体取决于查询语法。

最后一个可能需要解释。下面的查询调用 `FROM` 子句中的几个表，没有显式连接：

```sql
SELECT ...
FROM a, b, c, d, e
WHERE ...
```

这是此查询的解析树：

{% asset_img query4.png %}

在这个查询中，规划器将考虑所有可能的连接顺序。

在下一个示例中，一些连接由 JOIN 子句显式定义：

```sql
SELECT ...
FROM a, b JOIN c ON ..., d, e
WHERE ...
```

解析树反映了这一点：

{% asset_img query5.png %}

规划器折叠连接树，有效地将其转换为上一个示例中的树。该算法递归地遍历树并用其组件的平面列表替换每个 `JOINEXPR` 节点。

但是，只有在生成的平面列表包含不超过 `join_collapse_limit` 个元素（默认为 8 个）时，才会发生这种“扁平化”。在上面的示例中，如果将 `join_collapse_limit` 设置为 5 或更少，则不会折叠 `JOINEXPR` 节点。对于规划器来说，这意味着两件事：

* 表 B 必须和表 C 进行连接（反之亦然，对中的连接顺序不受限制）。
* 表 A，D，E 和表 B，C 连接结果可以以任意顺序进行连接。

如果 `join_collapse_limit` 设置为 `1`，则将保留任何显式 `JOIN` 顺序。

请注意，无论 `join_collapse_limit` 如何，操作 `FULL OUTER JOIN` 都不会折叠。

`from_collapse_limit` 参数（默认也是 8）以类似的方式限制子查询的展平。子查询似乎与连接没有太多共同之处，但是当它来到解析树级别时，相似性是显而易见的。例如：

```sql
SELECT ...
FROM a, b JOIN c ON ..., d, e
WHERE ...
```

这是它的树：

{% asset_img query6.png %}

这里唯一的区别是 `JOINEXPR` 节点被替换为 `FROMEXPR`（因此参数名称为 `FROM`）。

遗传搜索（**Genetic search**）。每当生成的扁平树以太多相同级别的节点（表或连接结果）结束时，规划时间可能会飙升，因为每个节点都需要单独优化。如果参数 `geqo` 开启（默认开启），当同级节点数量达到 `geqo_threshold`（默认为 12）时，PostgreSQL 将切换到遗传搜索。

遗传搜索比动态规划方法快得多，但它并不能保证找到最佳计划。该算法有许多可调整的选项，但这是另一篇文章的主题。

选择最佳计划（**Selecting the best plan**）。最佳计划的定义因预期用途而异。当需要完整的输出（例如，生成报告）时，计划必须优化与查询匹配的所有记录的检索。另一方面，如果您只想要前几个匹配的记录（例如，显示在屏幕上），则最佳计划可能会完全不同。

PostgreSQL 通过计算两个成本来解决这个问题。它们显示在 `cost` 一词之后的查询计划输出中：

```
 Sort  (cost=21.03..21.04 rows=1 width=128)
```

第一个组成部分，启动成本，是为节点执行做准备的成本；第二个组成部分，总成本，代表总节点执行成本。

当选择计划时，规划器首先检查游标是否正在使用（可以在 PL/pgSQL 中使用 `DECLARE` 命令设置游标或明确声明）。如果没有使用游标，那么规划器假定需要全部输出并选择总成本最低的计划。

否则，如果使用游标，那么规划器会选择一个计划，以最佳方式检索匹配行总数中等于 `cursor_tuple_fraction`（默认为 0.1）的行数。或者，更具体地说，最低的计划 `startup cost + cursor_tuple_fraction * (total cost - startup cost)`。

成本计算过程（**Cost calculation process**）。要估计计划成本，必须单独估计其每个节点。节点成本取决于节点类型（从表中读取的成本远低于对表排序的成本）和处理的数据量（通常，数据越多，成本越高）。虽然节点类型是立即知道的，但要评估数据量，我们首先需要估计节点的基数（输入行的数量）和选择率（剩余用于输出的行的比例）。为此，我们需要数据统计：表大小、跨列的数据分布。

因此，优化依赖于准确的统计数据，这些数据由自动分析过程收集并保持最新。

如果每个计划节点的基数估计准确，计算出的总成本通常会与实际成本相匹配。常见的计划偏差通常是基数和选择率估计不正确的结果。这些错误是由不准确、过时或不可用的统计数据引起的，并且在较小程度上是规划器所基于的固有模型不完善。

基数估计（**Cardinality estimation**）。基数估计是递归执行的。节点基数使用两个值计算：

* 节点的子节点的基数，或输入行数。
* 节点的选择率，或输出行与输入行的比例。

基数是这两个值的乘积。

选择率是一个介于 0 到 1 之间的数字。选择率的值越接近 0 则具有更高的选择率，反之，越接近 1 则具有更低的选择率。这是因为高选择率会消除较高比例的行，而较低的选择率值会降低阈值，因此丢弃的行数会更少。

首先处理具有数据访问方法的叶节点。这就是统计信息的来源，例如表大小。

应用于表的条件的选择率取决于条件类型。在最简单的形式中，选择率可以是一个常数值，但规划器会尝试使用所有可用信息来产生最准确的估计。最简单条件的选择率估计作为基础，使用布尔运算构建的复杂条件可以使用以下简单公式进一步计算：

$$
sel_{x\ and\ y} = sel_{x}\ sel_{y}
$$

$$
sel_{x\ or\ y} = 1 - (1 -sel_{x})(1 - sel_{y}) = sel_{x} + sel_{y} - sel_{x}\ sel_{y}
$$

在这些公式中，$x$ 和 $y$ 被认为是独立的。如果它们相关，则仍使用这些公式，但估计会不太准确。

对于连接的基数估计，计算两个值：笛卡尔积的基数（两个数据集的基数的乘积）和连接条件的选择率，这又取决于条件类型。

其他节点类型的基数，例如排序或聚合节点，也是类似地计算的。

请注意，较低节点中的基数计算错误将向上传播，导致成本估算不准确，并最终导致次优计划。规划器只有表的统计数据，而不是连接结果的统计数据，这使情况变得更糟。

成本估算（**Cost estimation**）。成本估算过程也是递归的。子树的成本包括其子节点的成本加上父节点的成本。

节点成本计算基于其执行操作的数学模型。已经计算的基数用作输入。该过程计算启动成本和总成本。

有些操作不需要任何准备，可以立即开始执行。对于这些操作，启动成本将为零。

其他操作可能有先决条件。例如，排序节点通常需要来自其子节点的所有数据才能开始操作。这些节点的启动成本不为零。即使下一个节点（或客户端）只需要单行输出，也必须支付此成本。

成本是计划者的最佳估计。任何计划错误都会影响成本与实际执行时间的相关程度。成本评估的主要目的是让计划者在相同条件下比较相同查询的不同执行计划。在任何其他情况下，按成本比较查询（更糟糕的是，不同的查询）是没有意义和错误的。例如，考虑由于统计数据不准确而被低估的成本。更新统计数据——成本可能会发生变化，但估算会变得更加准确，计划最终会得到改进。

### 执行

按照计划执行优化查询。

在后端内存中创建了一个称为 `portal` 的对象。`protal` 在查询执行时存储查询的状态。此状态表示为一棵树，其结构与计划树相同。

树的节点充当装配线，相互请求和传递行。

{% asset_img query7.png %}

执行器从根节点开始。根节点（示例中的排序节点 `SORT`）向子节点请求数据。当它接收到所有请求的数据时，它会执行排序操作，然后将数据向上传递给客户端。

一些节点（例如`NESTLOOP` 节点）连接来自不同来源的数据。该节点从两个子节点请求数据。在接收到与连接条件匹配的两行后，节点立即将结果行传递给父节点（与排序不同，排序必须在处理它们之前接收所有行）。然后该节点停止，直到其父节点请求另一行。因此，如果只需要部分结果（例如由 `LIMIT` 设置），则操作将不会完全执行。

两个 `SEQSCAN` 叶是表扫描。根据父节点的请求，叶节点从表中读取下一行并将其返回。

这个节点和其他一些节点根本不存储行，而只是交付并立即丢弃它们。其他节点，例如排序，可能需要一次存储大量数据。为了解决这个问题，在后端内存中分配了一个 `work_mem` 内存块。它的默认大小为 `4MB`，这过于保守；当内存用完时，多余的数据会被发送到磁盘上的临时文件中。

一个计划可能包括多个具有存储要求的节点，因此它可能分配了几个内存块，每个内存块的大小为 `work_mem`。查询进程可能占用的总内存大小没有限制。

## 扩展查询协议

使用简单的查询协议，任何命令，即使它一次又一次地重复，也会经历上述所有这些阶段：

1. 解析
2. 转换
3. 规划
4. 执行

但是没有理由一遍又一遍地解析同一个查询。如果它们仅在常量上有所不同，也没有任何理由重新解析查询：解析树将是相同的。

简单查询协议的另一个烦恼是客户端接收完整的输出，不管它可能有多长。

这两个问题都可以通过使用 SQL 命令来解决：第一个问题可以通过 `PREPARE` 和 `EXECUTE` 来解决，第二个问题可以通过 `DECLARE` 和 `FETCH` 来解决。但是随后客户端将不得不处理命名新对象，而服务器将需要解析额外的命令。

扩展查询协议可以在协议命令级别对单独的执行阶段进行精确控制。

### PREPARE

在 `PREPARE` 期间，查询会像往常一样被解析和转换，但解析树存储在后端内存中。

PostgreSQL 没有用于解析查询的全局缓存。即使一个进程之前已经解析过查询，其他进程也必须再次解析它。然而，这种设计也有好处。在高负载下，全局内存缓存很容易因为锁而成为瓶颈。一个客户端发送多个小命令可能会影响整个实例的性能。在 PostgreSQL 中，查询解析很便宜并且与其他进程隔离。

可以为 `PREPARE` 命令附加查询参数。下面是一个使用 SQL 命令的例子（同样，这并不等同于协议命令级别的准备，但最终的效果是一样的）：

```sql
PREPARE plane(text) AS
SELECT * FROM aircrafts WHERE aircraft_code = $1;
```

本系列文章中的大多数示例将使用[“航空公司”演示数据库](https://postgrespro.com/education/demodb)。

此视图显示所有命名的预准备语句：

```sql
SELECT name, statement, parameter_types
FROM pg_prepared_statements \gx
```

```
−[ RECORD 1 ]−−−+−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
name            | plane
statement       | PREPARE plane(text) AS                           +
                | SELECT * FROM aircrafts WHERE aircraft_code = $1;
parameter_types | {text}
```

该视图没有列出任何未命名的语句（使用扩展协议或 PL/pgSQL）。它也没有列出来自其他会话的准备好的语句：访问另一个会话的内存是不可能的。

### 参数绑定

在执行 `PREPARE` 的查询之前，会绑定当前参数值。

```sql
EXECUTE plane('733');
```

```
 aircraft_code |     model      | range
---------------+----------------+-------
 733           | Boeing 737−300 |  4200
(1 row)
```

与文字表达式的串联相比，`PREPARE` 语句的一个优点是可以防止任何类型的 SQL 注入，因为参数值不会影响已经构建的解析树。在没有 `PREPARE` 的声明的情况下达到相同的安全级别将需要对来自不受信任来源的所有值进行广泛的转义。

#### 规划和执行

执行 `PREPARE` 语句时，首先会考虑提供的参数来计划其查询，然后发送选择的计划以执行。

实际参数值对规划器很重要，因为不同参数集的最优规划也可能不同。例如，在查找高级航班预订时，使用索引扫描（如 `Index Scan` 字样所示），因为计划者预计匹配的行不多：

```sql
CREATE INDEX ON bookings(total_amount);
EXPLAIN SELECT * FROM bookings WHERE total_amount > 1000000;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Bitmap Heap Scan on bookings  (cost=86.38..9227.74 rows=4380 wid...
   Recheck Cond: (total_amount > '1000000'::numeric)
   −> Bitmap Index Scan on bookings_total_amount_idx  (cost=0.00....
       Index Cond: (total_amount > '1000000'::numeric)
(4 rows)
```

然而，下一个条件完全符合所有预订。索引扫描在这里没用，进行顺序扫描（`Seq Scan`）：

```sql
EXPLAIN SELECT * FROM bookings WHERE total_amount > 100;
```

```
                            QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on bookings  (cost=0.00..39835.88 rows=2111110 width=21)
   Filter: (total_amount > '100'::numeric)
(2 rows)
```

在某些情况下，除了解析树之外，规划器还会存储查询计划，以避免在出现时再次规划它。这个没有参数值的计划称为通用计划，而不是使用给定参数值生成的自定义计划。通用计划的一个明显用例是没有参数的语句。

对于前四次运行，带有参数的预处理语句总是根据实际参数值进行优化。然后计算平均计划成本。在第五次及以后，如果通用计划平均比自定义计划便宜（每次都必须重新构建），那么规划器将从那时起存储和使用通用计划，并进行进一步优化。

`PREPARE` 语句 `plane` 已经执行过一次。在接下来的两次执行中，仍然使用自定义计划，如查询计划中的参数值所示：

```sql
EXECUTE plane('763');
EXECUTE plane('773');
EXPLAIN EXECUTE plane('319');
```

```
                            QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on aircrafts_data ml  (cost=0.00..1.39 rows=1 width=52)
   Filter: ((aircraft_code)::text = '319'::text)
(2 rows)
```

执行四次后，规划器将切换到通用规划。在这种情况下，通用计划与定制计划相同，成本相同，因此更可取。现在 `EXPLAIN` 命令显示参数编号，而不是实际值：

```sql
EXECUTE plane('320');
EXPLAIN EXECUTE plane('321');
```

```
                            QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on aircrafts_data ml  (cost=0.00..1.39 rows=1 width=52)
   Filter: ((aircraft_code)::text = '$1'::text)
(2 rows)
```

不幸的是，只有前四个定制计划比通用计划更昂贵，而任何进一步的定制计划都会更便宜——但规划器会完全忽略它们。另一个可能的不完善来源是规划器比较成本估算，而不是要花费的实际资源成本。

这就是为什么在版本 12 及更高版本中，如果用户不喜欢自动结果，他们可以强制系统使用通用计划或自定义计划。这是通过参数 `plan_cache_mode` 完成的：

```
SET plan_cache_mode = 'force_custom_plan';
EXPLAIN EXECUTE plane('CN1');
```

```
                           QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
Seq Scan on aircrafts_data ml  (cost=0.00..1.39 rows=1 width=52)
  Filter: ((aircraft_code)::text = 'CN1'::text)
(2 rows)
```

在 14 及更高版本中，`pg_prepared_statements` 视图还可以显示计划选择统计信息：

```
SELECT name, generic_plans, custom_plans
FROM pg_prepared_statements;
```

```
 name  | generic_plans | custom_plans
−−−−−−−+−−−−−−−−−−−−−−−+−−−−−−−−−−−−−−
 plane |             1 |            6
(1 row)
```

### 获取输出

扩展查询协议允许客户端批量获取输出，一次多行，而不是一次全部获取。借助 SQL 游标也可以实现相同的目的，但成本更高，并且规划器将优化对第一个 `cursor_tuple_fraction` 行的检索：

```sql
BEGIN;
DECLARE cur CURSOR FOR
  SELECT * FROM aircrafts ORDER BY aircraft_code;
FETCH 3 FROM cur;
```

```
 aircraft_code |      model       | range
−−−−−−−−−−−−−−−+−−−−−−−−−−−−−−−−−−+−−−−−−−
 319           | Airbus A319−100 |  6700
 320           | Airbus A320−200 |  5700
 321           | Airbus A321−200 |  5600
(3 rows)
```

```sql
FETCH 2 FROM cur;
```

```
 aircraft_code |     model     | range
−−−−−−−−−−−−−−−+−−−−−−−−−−−−−−−+−−−−−−−
           733 | Boeing 737−300 |  4200
           763 | Boeing 767−300 |  7900
(2 rows)
```

```sql
COMMIT;
```

每当查询返回大量行并且客户端都需要它们时，一次检索的行数对于整体数据传输速度至关重要。单批行越大，往返延迟损失的时间就越少。然而，随着批量大小的增加，节省的效率会下降。例如，从批量大小 1 切换到批量大小 10 将显着增加时间节省，但从 10 切换到 100 几乎没有任何区别。

请继续关注[下一篇文章](https://postgrespro.com/blog/pgsql/5969296)，我们将讨论成本优化的基础：统计。

## 译者著

本文翻译自 [PostgreSQL Pro](https://postgrespro.com/) 的 [Queries in PostgreSQL: 1. Query execution stages](https://postgrespro.com/blog/pgsql/5969262)。

<div class="just-for-fun">
笑林广记 - 监生拜父

一人援例入监，吩咐家人备帖拜老相公。
仆曰：“父子如何用帖，恐被人谈论。”
生曰：“不然，今日进身之始，他客俱拜，焉有亲父不拜之理。”
仆问：“用何称呼？”
生沉吟曰：“写个‘眷侍教生’罢。”
父见，怒责之，生曰：“称呼斟酌切当，你自不解。父子一本至亲，故下一眷字；侍者，父坐子立也；教者，从幼延师教训；生者，父母生我也。”
父怒转盛，责其不通。
生谓仆曰：“想是嫌我太妄了，你去另换个晚生帖儿来罢。”
</div>