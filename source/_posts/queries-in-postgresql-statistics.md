---
title: "【译】PostgreSQL 中的查询 - 统计信息"
date: 2022-03-22 22:33:41 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
---

尽管不幸的事仍在发生<sup>[1]</sup>，但我们还是需要继续这个系列。在{% post_link queries-in-postgresql-query-execution-stages 上一篇文章 %}中，我们回顾了查询执行的各个阶段。在我们继续计划节点操作（数据访问和连接方法）之前，我们需要了解成本优化器的基本要素：统计信息。

和往常一样，我所有的例子都使用[演示数据库](https://postgrespro.com/education/demodb)。您可以下载并跟着一起执行。

今天您会在这里看到很多执行计划。我们将在以后的文章中更详细地讨论这些计划是如何运作的。现在只需注意您在每个计划的第一行中看到的数字，在单词 `rows` 旁边。这些是行数估计值或基数。

<!--more-->

## 基本信息

基本的表级别统计信息存放在 `pg_class` 系统表中。这些信息包括以下内容：

* 表的行数（`reltuples`）
* 表的页面数（`relpages`）
* 在表的可见性图中标记为全部可见的页面数（`relallvisible`）


```sql
SELECT reltuples, relpages, relallvisible
FROM pg_class WHERE relname = 'flights';
```

```
 reltuples | relpages | relallvisible
−−−−−−−−−−−+−−−−−−−−−−+−−−−−−−−−−−−−−−
    214867 |     2624 |         2624
(1 row)
```

对于没有条件（过滤器）的查询，基数估计将等于 `reltuples`：

```sql
EXPLAIN SELECT * FROM flights;
```

```
                           QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=0.00..4772.67 rows=214867 width=63)
(1 row)
```

数据库在自动或手动分析期间收集统计数据。执行某些操作时也会计算基本统计信息，即重要信息，例如 `VACUUM FULL`、`CLUSTER`、`CREATE INDEX` 和 `REINDEX`。系统还会在 `VACUUM` 期间更新统计信息。

为了收集统计信息，分析器随机抽样 `300 * default_statistics_target` 条记录（默认情况下 `default_statistics_target` 为 `100`，即 `30,000` 条记录）。此处未考虑表大小，因为总体数据集大小对什么样的样本大小足以进行准确的统计几乎没有影响。

随机选择的 `300 * default_statistics_target` 样本是从随机的页面中选择的。如果表记录小于样本容量，那么分析器将读取整个表。

在大表中，统计数据将不精确，因为分析器不会扫描每一行。即便如此，统计数据也总会有些过时，因为表数据一直在变化。无论如何，我们不需要统计数据那么精确：高达一个数量级的变化仍然足够准确以产生适当的计划。

让我们创建一个禁用自动清理功能的 `flights` 的副本，以便我们可以控制何时进行分析。

```sql
CREATE TABLE flights_copy(LIKE flights)
WITH (autovacuum_enabled = false);
```

目前，新表还没有统计信息：

```sql
SELECT reltuples, relpages, relallvisible
FROM pg_class WHERE relname = 'flights_copy';
```

```
 reltuples | relpages | relallvisible
−−−−−−−−−−−+−−−−−−−−−−+−−−−−−−−−−−−−−−
        −1 |        0 |             0
(1 row)
```

`reltuples = -1`（PostgreSQL 14 及以上版本）有助于我们区分从未收集过统计信息的表和没有任何行的表。

通常情况下，新创建的表会立即填充。规划器对新表一无所知，因此默认情况下假定该表有 `10` 页。

```sql
EXPLAIN SELECT * FROM flights_copy;
```

```
                           QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights_copy  (cost=0.00..14.10 rows=410 width=170)
(1 row)
```

规划器根据单行的宽度计算行数。宽度通常是在分析期间计算的平均值。但是，这次没有分析数据，因此系统根据列数据类型来近似宽度。

让我们将 `flights` 的数据复制到新表中并运行分析器：

```sql
INSERT INTO flights_copy SELECT * FROM flights;
```

```
INSERT 0 214867
```

```sql
ANALYZE flights_copy;
```

现在统计信息与实际行数匹配。该表足够紧凑，分析器可以遍历每一行：

```sql
SELECT reltuples, relpages, relallvisible
FROM pg_class WHERE relname = 'flights_copy';
```

```
 reltuples | relpages | relallvisible
−−−−−−−−−−−+−−−−−−−−−−+−−−−−−−−−−−−−−−
    214867 |     2624 |             0
(1 row)
```

`relallvisible` 的值将在 `VACUUM` 之后得到更新：

```sql
VACUUM flights_copy;
SELECT relallvisible FROM pg_class WHERE relname = 'flights_copy';
```

```
 relallvisible
−−−−−−−−−−−−−−−
          2624
(1 row)
```

这个值在估计仅索引扫描（index-only scan）时会被用到。

让我们在保留旧统计信息的同时将行数加倍，看看规划器得出的基数是多少：

```sql
INSERT INTO flights_copy SELECT * FROM flights;
SELECT count(*) FROM flights_copy;
```

```
 count
−−−−−−−−
 429734
(1 row)
```

```sql
EXPLAIN SELECT * FROM flights_copy;
```

```
                            QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights_copy  (cost=0.00..9545.34 rows=429734 width=63)
(1 row)
```

尽管 `pg_class` 中的数据已经过时，但是这个估算是准确的：

```sql
SELECT reltuples, relpages
FROM pg_class WHERE relname = 'flights_copy';
```

```
 reltuples | relpages
−−−−−−−−−−−+−−−−−−−−−−
    214867 |     2624
(1 row)
```

规划器注意到数据文件的大小不再匹配旧的 `relpages` 值，因此它适当地缩放 `reltuples` 以尝试提高准确性。文件大小增加了一倍，因此行数也相应调整（假设数据密度不变）：

```sql
SELECT reltuples *
  (pg_relation_size('flights_copy') / 8192) / relpages
FROM pg_class WHERE relname = 'flights_copy';
```

```
 ?column?
−−−−−−−−−−
   429734
(1 row)
```

这种调整并不总是有效（例如，您有可能删除了某些行，但是统计信息没有更改），但是当进行重大更改时，这种方法可以让统计数据保持不变，直到分析器的出现。

## NULL 值

虽然被纯粹主义者看不起，但 `NULL` 值可以方便地表示未知或不存在的值。

但是特殊值需要特殊处理。使用 `NULL` 值时需要牢记一些实际的注意事项。布尔逻辑变成了三进制，`NOT IN` 构造开始表现得很奇怪。目前尚不清楚 NULL 值是否被视为低于或高于常规值（特殊子句 `NULLS FIRST` 和 `NULLS LAST` 对此有所帮助）。在聚合函数中使用 `NULL` 值也很粗略。因为 `NULL` 值实际上根本不是值，所以规划器需要额外的数据来容纳它们。

除了基本的表级统计信息，分析器还收集表中每一列的统计信息。这些据存储在系统目录的 `pg_statistic` 表中，可以使用 `pg_stats` 视图方便地显示。

`NULL` 值率是列级别的统计信息。它在 `pg_stats` 中被指定为 `null_frac`。在这个例子中，一些飞机还没有起飞，所以它们的起飞时间是不确定的：

```sql
EXPLAIN SELECT * FROM flights WHERE actual_departure IS NULL;
```

```
                          QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=0.00..4772.67 rows=16036 width=63)
   Filter: (actual_departure IS NULL)
(2 rows)
```

优化器将总行数乘以 `NULL` 值率得到估计的行数：

```sql
SELECT round(reltuples * s.null_frac) AS rows
FROM pg_class
  JOIN pg_stats s ON s.tablename = relname
WHERE s.tablename = 'flights'
  AND s.attname = 'actual_departure';
```

```
 rows
−−−−−−−
 16036
(1 row)
```

## 不同值

列中不同值（distinct values）的数量存储在 `pg_stats` 的 `n_distinct` 字段中。

如果 `n_distinct` 是负数，它的绝对值表示不同值占总数的比例。例如，`-1` 意味着列中的每个值都是唯一的。当不同值的数量达到总数量的 `10%` 或更多时，分析器将假设修改数据时该比例通常会保持不变，此时使用正数来表示不同值的数量。

如果不同值的数量计算不正确（因为样本恰好不具有代表性），您可以手动设置此值：

```sql
ALTER TABLE ... ALTER COLUMN ... SET (n_distinct = ...);
```

{% asset_img statistics1-en.png %}

在数据均匀分布的情况下，不同值的数量很有用。考虑 `column = expression` 子句的基数估计。如果在规划阶段表达式的值未知，则规划器假定表达式同样可能从列中返回任何值。

```sql
EXPLAIN
SELECT * FROM flights WHERE departure_airport = (
  SELECT airport_code FROM airports WHERE city = 'Saint Petersburg'
);
```

```
                         QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=30.56..5340.40 rows=2066 width=63)
   Filter: (departure_airport = $0)
   InitPlan 1 (returns $0)
     −> Seq Scan on airports_data ml  (cost=0.00..30.56 rows=1 wi...
         Filter: ((city −>> lang()) = 'Saint Petersburg'::text)
(5 rows)
```

`InitPlan` 节点只执行一次，然后在主计划中使用该值替换 `$0`。

```sql
SELECT round(reltuples / s.n_distinct) AS rows
FROM pg_class
  JOIN pg_stats s ON s.tablename = relname
WHERE s.tablename = 'flights'
  AND s.attname = 'departure_airport';
```

```
 rows
−−−−−−
 2066
(1 row)
```

如果所有数据均匀分布，则这些统计数据（连同最小值和最大值）足以进行准确的估计。不幸的是，这种估计不适用于非均匀分布，通常后者更为常见：

```sql
SELECT min(cnt), round(avg(cnt)) avg, max(cnt) FROM (
  SELECT departure_airport, count(*) cnt
  FROM flights GROUP BY departure_airport
) t;
```

```
 min | avg  |  max
−−−−−+−−−−−−+−−−−−−−
 113 | 2066 | 20875
(1 row)
```

## 最常见的值

为了提高非均匀分布的估计精度，分析器收集最常见值 (MCV, Most Common Calues) 及其频率的统计信息。这些信息存储在 `pg_stats` 的 `most_common_vals` 和 `most_common_freqs` 中。

{% asset_img statistics2-en.png %}

以下是最常见飞机类型的此类统计数据示例：

```sql
SELECT most_common_vals AS mcv,
  left(most_common_freqs::text,60) || '...' AS mcf
FROM pg_stats
WHERE tablename = 'flights' AND attname = 'aircraft_code' \gx
```

```
−[ RECORD 1 ]−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
mcv | {CN1,CR2,SU9,321,763,733,319,773}
mcf | {0.2783,0.27473333,0.25816667,0.059233334,0.038533334,0.0370...
```

估计 `column = expression` 的选择率非常简单：规划器只需从 `most_common_vals` 数组中获取一个值，并将其乘以来自 `most_common_freqs` 数组中相同位置的频率。

```sql
EXPLAIN SELECT * FROM flights WHERE aircraft_code = '733';
```

```
                          QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=0.00..5309.84 rows=7957 width=63)
   Filter: (aircraft_code = '733'::bpchar)
(2 rows)
```

```
SELECT round(reltuples * s.most_common_freqs[
  array_position((s.most_common_vals::text::text[]),'733')
])
FROM pg_class
  JOIN pg_stats s ON s.tablename = relname
WHERE s.tablename = 'flights'
  AND s.attname = 'aircraft_code';
```

```
 round
−−−−−−−
  7957
(1 row)
```

这个估计值将接近 `8263` 的真实值。

MCV 列表也用于不等式的选择性估计：为了找到 `column < value` 的选择率，规划器在 `most_common_vals` 中搜索所有低于给定值的值，然后将它们从 `most_common_freqs` 中的频率相加。

当不同值的数量较少时，常用值统计最有效。MCV 数组的最大大小由 `default_statistics_target` 定义，与分析期间记录的样本大小相同。

在某些情况下，将值（以及数组大小）增加到超出默认值将提供更准确的估计。您可以为每列设置此值：

```sql
ALTER TABLE ... ALTER COLUMN ... SET STATISTICS ...;
```

行样本大小也会增加，但仅限于此表。

常用值数组存储值本身，并且根据值的不同，可能会占用大量空间。就是为什么超过 1kB 的值被排除在分析和统计之外的原因。它可以控制 `pg_statistic` 的大小，并且不会使规划器超载。无论如何，这么大的值通常是不同的，不会包含在 `most_common_vals` 中。

## 直方图

当不同值的数量变得太大而无法将它们全部存储在数组中时，系统开始使用直方图（Histogram）表示。直方图使用多个存储桶来存储值。存储桶的数量受相同的 `default_statistics_target` 参数限制。选择每个桶的宽度，以便将值均匀分布在它们之间（如下图所示具有大致相同面积的矩形所示）。这种表示使系统能够只存储直方图边界，而不是浪费空间来存储每个桶的频率。直方图不包括 MCV 列表中的值。

{% asset_img statistics3-en.png %}

边界存储在 `pg_stats` 的 `histogram_bounds` 字段中。任何桶中值的汇总频率等于 1 / 桶数。

直方图存储桶边界数组：

```sql
SELECT left(histogram_bounds::text,60) || '...' AS histogram_bounds
FROM pg_stats s
WHERE s.tablename = 'boarding_passes' AND s.attname = 'seat_no';
```

```
                        histogram_bounds
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 {10B,10D,10D,10F,11B,11C,11H,12H,13B,14B,14H,15H,16D,16D,16H...
(1 row)
```

其中，直方图与 MCV 一起用于评估大于和小于操作的选择率。

示例：计算为后排座位签发的登机牌数量。

```sql
EXPLAIN SELECT * FROM boarding_passes WHERE seat_no > '30C';
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on boarding_passes  (cost=0.00..157353.30 rows=2943394 ...
   Filter: ((seat_no)::text > '30C'::text)
(2 rows)
```

分割的座位号是专门选择在两个桶之间的边缘。

这个条件的选择率是 N / 桶数，其中 N 是具有匹配值的桶的数量（在分割的座位号的右侧）。请记住，直方图没有考虑最常见的值和未定义的值。让我们先看看匹配最常见值的分数：

```sql
SELECT sum(s.most_common_freqs[
  array_position((s.most_common_vals::text::text[]),v)
])
FROM pg_stats s, unnest(s.most_common_vals::text::text[]) v
WHERE s.tablename = 'boarding_passes' AND s.attname = 'seat_no'
AND v > '30C';
```

```
  sum
−−−−−−−−
 0.2127
(1 row)
```

现在让我们看看最常用值的频率（从直方图中排除）：

```sql
SELECT sum(s.most_common_freqs[
  array_position((s.most_common_vals::text::text[]),v)
])
FROM pg_stats s, unnest(s.most_common_vals::text::text[]) v
WHERE s.tablename = 'boarding_passes' AND s.attname = 'seat_no';
```

```
  sum
−−−−−−−−
 0.6762
(1 row)
```

`seat_no` 列中没有 `NULL` 值：

```sql
SELECT s.null_frac
FROM pg_stats s
WHERE s.tablename = 'boarding_passes' AND s.attname = 'seat_no';
```

```
 null_frac
−−−−−−−−−−−
         0
(1 row)
```

区间正好涵盖 49 个桶（总共 100 个）。结果估计：

```sql
SELECT round( reltuples * (
   0.2127 -- from most common values
 + (1 - 0.6762 - 0) * (49 / 100.0) -- from histogram
))
FROM pg_class WHERE relname = 'boarding_passes';
```

```
  round
−−−−−−−−−
 2943394
(1 row)
```

真实值为 `2986429`。

当截止值不在桶的边缘时，该桶的匹配分数是使用线性插值计算的。

{% asset_img statistics4-en.png %}

较高的 `default_statistics_target` 值可能会提高估计精度，但是，即便是在有大量不同的值时，直方图与 MCV 列表一起已经产生了很好的结果：

```sql
SELECT n_distinct FROM pg_stats
WHERE tablename = 'boarding_passes' AND attname = 'seat_no';
```

```
 n_distinct
−−−−−−−−−−−−
        461
(1 row)
```

更高的估计精度只有在提高规划质量时才有用。在没有正当理由的情况下增加 `default_statistics_target` 可能会减慢分析和计划，但对优化没有影响。

另一方面，降低参数（一直降至零）可能会提高分析和计划速度，但也可能导致计划质量低下，因此这种“节省时间”很少有道理。

## 非标量数据类型的统计

非标量数据类型的统计（statistics for nonscalar data types）可能不仅包括非标量值本身的分布数据，还包括它们的组成元素的分布数据。这允许在查询非第一范式中的列时进行更准确的计划。

* 数组 `most_common_elems` 和 `most_common_elem_freqs` 分别包含最常见的元素及其频率。这些统计数据被收集并用于估计数组和 `tsvector` 数据的选择率。
* `elem_count_histogram` 数组是一个值中不同元素数量的直方图。收集这些统计数据并仅用于估计数组的选择率。
* 对于范围数据类型，直方图用于表示范围长度的分布及其下限和上限的分布。然后，这些直方图有助于估计使用这些数据类型的各种操作的选择率。它们没有显示在 `pg_stats` 视图中。这些统计信息也用于 PostgreSQL 14 中引入的多范围数据类型。

## 平均宽度

`pg_stats` 视图中的 `avg_width` 字段表示列中的平均字段宽度（Average field width）。整数或 `char(3)` 等数据类型的字段宽度显然是固定的，但对于没有设置宽度的数据类型，例如文本，值可能会因列而异：

```sql
SELECT attname, avg_width FROM pg_stats
WHERE (tablename, attname) IN ( VALUES
  ('tickets', 'passenger_name'), ('ticket_flights','fare_conditions')
);
```

```
     attname     | avg_width
−−−−−−−−−−−−−−−−−+−−−−−−−−−−−
 fare_conditions |         8
 passenger_name  |        16
(2 rows)
```

这些统计信息有助于估计排序或散列等操作的内存使用情况。

## 相关系数

`pg_stats` 中的字段 `correlation` 表示磁盘上的物理行排序与列值的逻辑排序（“大于”或“小于”）之间的相关性（correlation），范围从 -1 到 +1。如果这些值按顺序存储，则相关性将接近 +1。如果它们以相反的顺序存储，则相关性将更接近 -1。数据在磁盘上分布越混乱，值越接近于零。

```sql
SELECT attname, correlation
FROM pg_stats WHERE tablename = 'airports_data'
ORDER BY abs(correlation) DESC;
```

```
   attname    | correlation
−−−−−−−−−−−−−−+−−−−−−−−−−−−−
 coordinates  |
 airport_code | −0.21120238
 city         |  −0.1970127
 airport_name | −0.18223621
 timezone     |  0.17961165
(5 rows)
```

无法收集 `coordinates` 列的统计信息，因为没有为 `point` 数据类型定义比较操作（“小于”和“大于”）。

相关性用于索引扫描成本估计。

## 表达式统计信息

一般来说，列统计只在操作调用列本身时使用，而不是用于以列为参数的表达式。规划器不知道函数将如何影响列统计信息，因此像 `function-call = constant` 这样的条件总是估计为 0.5%：

```sql
EXPLAIN SELECT * FROM flights
WHERE extract(
  month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow'
) = 1;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=0.00..6384.17 rows=1074 width=63)
   Filter: (EXTRACT(month FROM (scheduled_departure AT TIME ZONE ...
(2 rows)
```

```sql
SELECT round(reltuples * 0.005)
FROM pg_class WHERE relname = 'flights';
```

```
 round
−−−−−−−
  1074
(1 row)
```

规划器甚至无法处理标准函数，而对我们来说，很明显 1 月份的航班比例将约为总航班的 1/12：

```sql
SELECT count(*) AS total,
  count(*) FILTER (WHERE extract(
    month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow'
  ) = 1) AS january
FROM flights;
```

```
 total  | january
−−−−−−−−+−−−−−−−−−
 214867 |   16831
(1 row)
```

这就是表达式统计的用武之地。

### 扩展表达式统计信息

PostgreSQL 14 引入了一种称为扩展表达式统计信息（extended expression statistics）的特性。扩展表达式统计信息不会自动收集。要手动收集它们，请使用 `CREATE STATISTICS` 命令创建扩展的统计数据库对象。

```
CREATE STATISTICS flights_expr ON (extract(
  month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow'
))
FROM flights;
```

新的统计数据将改进估计：

```sql
ANALYZE flights;
EXPLAIN SELECT * FROM flights
WHERE extract(
  month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow'
) = 1;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=0.00..6384.17 rows=16222 width=63)
   Filter: (EXTRACT(month FROM (scheduled_departure AT TIME ZONE ...
(2 rows)
```

要使统计信息起作用，统计信息生成命令中的表达式必须与原始查询中的表达式相同。扩展统计元数据存储在系统目录的 `pg_statistic_ext` 表中，而统计数据本身存储在单独的表 `pg_statistic_ext_data` 中（在 PostgreSQL 12 及更高版本中）。如有必要，它与元数据分开存储，以限制用户访问敏感信息。

有些视图以用户友好的形式显示收集的统计信息。可以使用以下命令显示扩展表达式统计信息：

```sql
SELECT left(expr,50) || '...' AS expr,
  null_frac, avg_width, n_distinct,
  most_common_vals AS mcv,
  left(most_common_freqs::text,50) || '...' AS mcf,
  correlation
FROM pg_stats_ext_exprs WHERE statistics_name = 'flights_expr' \gx
```

```
-[ RECORD 1 ]−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
expr        | EXTRACT(month FROM (scheduled_departure AT TIME ZO...
null_frac   | 0
avg_width   | 8
n_distinct  | 12
mcv         | {8,9,3,5,12,4,10,7,11,1,6,2}
mcf         | {0.12526667,0.11016667,0.07903333,0.07903333,0.078..
correlation | 0.095407926
```

可以使用 `ALTER STATISTICS` 命令更改收集的统计数据量：

```sql
ALTER STATISTICS flights_expr SET STATISTICS 42;
```

### 表达式索引统计信息

建立表达式索引时，系统会收集其统计信息，就像使用常规表一样。规划器也可以使用这些统计数据。这很方便，但前提是我们真正关心索引。


```sql
DROP STATISTICS flights_expr;
CREATE INDEX ON flights(extract(
  month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow'
)); => ANALYZE flights;
EXPLAIN SELECT * FROM flights WHERE extract(
  month FROM scheduled_departure AT TIME ZONE 'Europe/Moscow'
) = 1;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Bitmap Heap Scan on flights  (cost=318.42..3235.96 rows=16774 wi...
   Recheck Cond: (EXTRACT(month FROM (scheduled_departure AT TIME...
   −> Bitmap Index Scan on flights_extract_idx  (cost=0.00..314.2...
       Index Cond: (EXTRACT(month FROM (scheduled_departure AT TI...
(4 rows)
```

表达式索引统计信息的存储方式与表统计信息相同。例如，这是不同值的数量：

```sql
SELECT n_distinct FROM pg_stats
WHERE tablename = 'flights_extract_idx';
```

```
 n_distinct
−−−−−−−−−−−−
         12
(1 row)
```

在 PostgreSQL 11 及更高版本中，可以使用 `ALTER INDEX` 命令更改索引统计信息的准确性。您可能需要引用该表达式的列的名称。例如：

```sql
SELECT attname FROM pg_attribute
WHERE attrelid = 'flights_extract_idx'::regclass;
```

```
 attname
−−−−−−−−−
 extract
(1 row)
```

```
ALTER INDEX flights_extract_idx
  ALTER COLUMN extract SET STATISTICS 42;
```

## 多元统计信息

PostgreSQL 10 引入了同时从多个列收集统计信息的能力，也称为多元统计信息（multivariate statistics）。这需要手动生成必要的扩展统计信息。

多元统计分为三种类型。

### 列之间的功能依赖关系

当一列中的值（完全或部分）由另一列中的值确定，并且在查询中存在引用两列的条件时，结果基数将被低估。

这是一个具有两个条件的示例：

```sql
SELECT count(*) FROM flights
WHERE flight_no = 'PG0007' AND departure_airport = 'VKO';
```

```
 count
−−−−−−−
   396
(1 row)
```

估计值明显低于应有的值，只有 26 行：

```sql
EXPLAIN SELECT * FROM flights
WHERE flight_no = 'PG0007' AND departure_airport = 'VKO';
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Bitmap Heap Scan on flights  (cost=12.03..1238.70 rows=26 width=63)
   Recheck Cond: (flight_no = 'PG0007'::bpchar)
   Filter: (departure_airport = 'VKO'::bpchar)
   −> Bitmap Index Scan on flights_flight_no_scheduled_departure_key
       (cost=0.00..12.02 rows=480 width=0)
       Index Cond: (flight_no = 'PG0007'::bpchar)
(6 rows)
```

这就是臭名昭著的相关谓词（correlated predicates）问题。规划器期望谓词是独立的，并将结果选择率计算为条件选择率的乘积，与 AND 相结合。在应用位图堆扫描中的 `departure_airport` 条件后，为 `flight_no` 条件计算的位图索引扫描估计值明显下降。

事实上，一个航班号已经明确定义了出发机场，所以第二个条件实际上是多余的。这就是扩展的功能依存度统计可以帮助改进估计的地方。

让我们为两列创建扩展的函数依赖统计信息：

```sql
CREATE STATISTICS flights_dep(dependencies)
ON flight_no, departure_airport FROM flights;
```

再次分析，现在使用新的统计数据，估计得到改善：

```sql
ANALYZE flights;
EXPLAIN SELECT * FROM flights
WHERE flight_no = 'PG0007' AND departure_airport = 'VKO';
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Bitmap Heap Scan on flights  (cost=10.56..816.91 rows=276 width=63)
   Recheck Cond: (flight_no = 'PG0007'::bpchar)
   Filter: (departure_airport = 'VKO'::bpchar)
   −> Bitmap Index Scan on flights_flight_no_scheduled_departure_key
       (cost=0.00..10.49 rows=276 width=0)
       Index Cond: (flight_no = 'PG0007'::bpchar)
(6 rows)
```

统计信息存储在系统目录中，可以使用以下命令查看：

```sql
SELECT dependencies
FROM pg_stats_ext WHERE statistics_name = 'flights_dep';
```

```
               dependencies
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 {"2 => 5": 1.000000, "5 => 2": 0.010567}
(1 row)
```

数字 2 和 5 是来自 `pg_attribute` 的表列号。它们旁边的值表示函数依赖的程度，从 0（独立）到 1（第二列中的值完全由第一列中的值定义）。

### 多元不同值的数量

来自多列的不同值组合数量的统计信息将显着提高对多列进行 `GROUP BY` 操作的基数。

在此示例中，规划器将可能的出发和到达机场对的数量估计为机场总数的平方。然而，真实的成对数量要低得多，因为并非每两个机场都通过直飞航班连接：

```sql
SELECT count(*) FROM (
  SELECT DISTINCT departure_airport, arrival_airport FROM flights
) t;
```

```
 count
−−−−−−−
   618
(1 row)
```

```sql
EXPLAIN
SELECT DISTINCT departure_airport, arrival_airport FROM flights;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 HashAggregate  (cost=5847.01..5955.16 rows=10816 width=8)
   Group Key: departure_airport, arrival_airport
   −> Seq Scan on flights  (cost=0.00..4772.67 rows=214867 width=8)
(3 rows)
```

让我们为不同值的数量创建一个扩展统计信息：

```sql
CREATE STATISTICS flights_nd(ndistinct)
ON departure_airport, arrival_airport FROM flights;
ANALYZE flights;
EXPLAIN
SELECT DISTINCT departure_airport, arrival_airport FROM flights;
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 HashAggregate (cost=5847.01..5853.19 rows=618 width=8)
   Group Key: departure_airport, arrival_airport
   −> Seq Scan on flights  (cost=0.00..4772.67 rows=214867 width=8)
(3 rows)
```

统计信息存储在系统目录中：

```sql
SELECT n_distinct
FROM pg_stats_ext WHERE statistics_name = 'flights_nd';
```

```
  n_distinct
−−−−−−−−−−−−−−−
 {"5, 6": 618}
(1 row)
```

### 多元最常见值列表

当值分布不均匀时，仅功能依赖数据可能不够，因为估计值将根据特定的值对而显着变化。考虑这个例子，规划器错误地估计了波音 737 从 Sheremetyevo 机场起飞的航班数量：

```sql
SELECT count(*) FROM flights
WHERE departure_airport = 'SVO' AND aircraft_code = '733'
```

```
 count
−−−−−−−
  2037
(1 row)
```

```sql
EXPLAIN SELECT * FROM flights
WHERE departure_airport = 'SVO' AND aircraft_code = '733';
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=0.00..5847.00 rows=733 width=63)
   Filter: ((departure_airport = 'SVO'::bpchar) AND (aircraft_cod...
(2 rows)
```

我们可以使用多元 MCV 列表统计来改进估计：

```sql
CREATE STATISTICS flights_mcv(mcv)
ON departure_airport, aircraft_code FROM flights;
ANALYZE flights;
EXPLAIN SELECT * FROM flights
WHERE departure_airport = 'SVO' AND aircraft_code = '733';
```

```
                             QUERY PLAN
−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−
 Seq Scan on flights  (cost=0.00..5847.00 rows=2077 width=63)
   Filter: ((departure_airport = 'SVO'::bpchar) AND (aircraft_cod...
(2 rows)
```

现在系统表中有频率数据供规划器使用：

```sql
SELECT values, frequency
FROM pg_statistic_ext stx
  JOIN pg_statistic_ext_data stxd ON stx.oid = stxd.stxoid,
  pg_mcv_list_items(stxdmcv) m
WHERE stxname = 'flights_mcv'
AND values = '{SVO,773}';
```

```
  values   |      frequency
−−−−−−−−−−−+−−−−−−−−−−−−−−−−−−−−−−
 {SVO,773} | 0.005733333333333333
(1 row)
```

多元最常见值列表存储 `default_statistics_target` 个值，就像常规 MCV 列表一样。如果参数是在列级别定义的，则使用最大值。

与扩展表达式统计信息一样，您可以更改列表大小（在 PostgreSQL 13 及更高版本中）：

```sql
ALTER STATISTICS ... SET STATISTICS ...;
```

在这些示例中，仅为两列收集了多元统计信息，但您可以根据需要为任意多的列收集它们。

您还可以将不同类型的统计信息收集到单个扩展统计信息对象中。为此，只需在创建对象时列出用逗号分隔的所需统计类型。如果没有定义特定的统计类型，系统将一次收集所有可用的统计信息。

PostgreSQL 14 还允许您在进行多元变量和表达式统计时不仅使用列名，还可以使用任意表达式。

未完待续。


## 译者著

本文翻译自 [PostgreSQL Pro](https://postgrespro.com/) 的 [Queries in PostgreSQL: 2. Statistics](https://postgrespro.com/blog/pgsql/5969296)。

<hr/>

[1] 应该指的是俄乌战争。

<div class="just-for-fun">
笑林广记 - 半字不值

一监生妻谓其孤陋寡闻。使劝读书。
问：“读书有甚好处？”
妻曰：“一字值千金，如何无益？”
生答曰：“难道我此身半个字也不值？”
</div>
