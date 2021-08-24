---
title: "【译】PostgreSQL 分组集：ROLLUP & CUBE"
date: 2021-08-23 22:53:52 +0800
category: 数据库
tags:
  - PostgreSQL
  - 翻译
---

PostgreSQL 是世界上最好的 OLTP 数据库（[OLTP][]，即在线事务处理）之一。然而，它可以做的不仅仅是 OLTP。PostgreSQL 提供了许多与更具 OLAP 风格的工作负载相关的附加功能。其中一个特性称为“GROUPING SETS”（GROUPING SETS，即分组集）。

<!-- more -->

在我们深入研究细节之前，我提供了一些示例数据，您可以轻松地将它们加载到您的 SQL 数据库中：

```sql
CREATE TABLE t_sales
(
    country        text,
    product_name   text,
    year           int,
    amount_sold    numeric
);

INSERT INTO t_sales VALUES
    ('Argentina', 'Shoes', 2020, 12),
    ('Argentina', 'Shoes', 2021, 14),
    ('Argentina', 'Hats', 2020, 54),
    ('Argentina', 'Hats', 2021, 57),
    ('Germany', 'Shoes', 2020, 34),
    ('Germany', 'Shoes', 2021, 29),
    ('Germany', 'Hats', 2020, 19),
    ('Germany', 'Hats', 2021, 22),
    ('USA', 'Shoes', 2020, 99),
    ('USA', 'Shoes', 2021, 103),
    ('USA', 'Hats', 2020, 81),
    ('USA', 'Hats', 2021, 90)
;
```

请注意，您在本博客中看到的所有内容都非常符合 SQL 标准，因此您可以预期大部分内容也适用于其他专业SQL数据库。

让我们从一个简单的聚合开始：

```
test=# SELECT  country, sum(amount_sold)
       FROM    t_sales
       GROUP BY 1;
 country   | sum
-----------+-----
 USA       | 373
 Germany   | 104
 Argentina | 137
(3 rows)
```

这里没什么好说的，除了我们将为每个小组得到一个总数。然而，有一点哲学上的讨论正在进行。`GROUP BY 1` 基本上是指 `GROUP BY country`，相当于 SELECT 子句中的第一列。因此，`GROUP BY country` 和 `GROUP BY 1` 是一回事：

```
test=# SELECT  country, product_name, sum(amount_sold)
       FROM    t_sales
       GROUP BY 1, 2
       ORDER BY 1, 2;
 country   | product_name | sum
-----------+--------------+-----
 Argentina | Hats         | 111
 Argentina | Shoes        |  26
 Germany   | Hats         |  41
 Germany   | Shoes        |  63
 USA       | Hats         | 171
 USA       | Shoes        | 202
(6 rows)
```

当然，这也适用于不止一列。不过，我想指出一点。考虑以下示例：

```
test=# SELECT CASE WHEN country = 'USA'
                THEN 'USA'
                ELSE 'non-US'
              END,
              sum(amount_sold)
       FROM t_sales
       GROUP BY 1;
 case   | sum
--------+-----
 USA    | 373
 non-US | 241
(2 rows)
```

大多数人按列名分组。在某些情况下，按表达式分组是有意义的。在我的例子中，我们是在运行中形成组（即一个组用于美国销售，一个组用于非美国销售）。这个功能往往没有得到重视。然而，它在许多现实世界的场景中是很有用的。请记住，您将要看到的所有东西也可以与表达式一起工作，这意味着可以进行更灵活的分组。

## 分组集：基本构建块

`GROUP BY` 将把一列中每一个不同的条目变成一个组。有时您可能想一次做更多的分组。为什么有这个必要呢？假设你正在处理一个 10TB 的表。显然，读取这些数据通常是性能方面的限制因素。因此，一次读取数据并一次产生更多的结果是很有吸引力的。这正是您可以用 `GROUP BY GROUP SETS` 做的事情。假设我们想一次产生两个结果：

* `GROUP BY country`
* `GROUP BY product_name`

这是它如何工作的：

```
test=# SELECT  country, product_name, sum(amount_sold)
       FROM    t_sales
       GROUP BY GROUPING SETS ((1), (2))
       ORDER BY 1, 2;
 country   | product_name | sum
-----------+--------------+-----
 Argentina |              | 137
 Germany   |              | 104
 USA       |              | 373
           | Hats         | 323
           | Shoes        | 291
(5 rows)
```

在这种情况下，PostgreSQL 只是简单地附加结果。前三行代表 `GROUP BY country`。接下来的两行包含 `GROUP BY product_name` 的结果。从逻辑上讲，它相当于以下查询：

```
test=# SELECT  NULL AS country , product_name, sum(amount_sold)
       FROM    t_sales
       GROUP BY  1, 2
       UNION ALL
       SELECT  country, NULL, sum(amount_sold)
       FROM    t_sales
       GROUP BY  1, 2
       ORDER BY 1, 2;
 country   | product_name | sum
-----------+--------------+-----
 Argentina |              | 137
 Germany   |              | 104
 USA       |              | 373
           | Hats         | 323
           | Shoes        | 291
(5 rows)
```

但是，`GROUPING SETS` 版本的效率更高，因为它只需要读取一次数据。

## ROLLUP: 添加“底线”

在创建报告时，您通常需要“底线”来总结表中显示的内容。在 SQL 中这样做的方法是使用 `GROUP BY ROLLUP`：

```
test=# SELECT  country, product_name, sum(amount_sold)
       FROM    t_sales
       GROUP BY ROLLUP (1, 2)
       ORDER BY 1, 2;
 country   | product_name | sum
-----------+--------------+-----
 Argentina | Hats         | 111
 Argentina | Shoes        |  26
 Argentina |              | 137
 Germany   | Hats         |  41
 Germany   | Shoes        |  63
 Germany   |              | 104
 USA       | Hats         | 171
 USA       | Shoes        | 202
 USA       |              | 373
           |              | 614
(10 rows)
```

PostgreSQL 将在结果中注入几行。如您所见，`Argentina` 返回了 3 行，而不仅仅是 2 行记录。`product_name = NULL` 记录是由 `ROLLUP` 添加的。它包含了所有 `Argentina` 销售额的总和（`116 + 27 = 137`）。其他两个国家都有额外的行被注入。最后，为全球总销售额添加了一行。

通常，这些空记录不是人们希望看到的，因此用其他类型的条目替换它们是有意义的。实现这一点的方法是使用一个 `subselect` 来检查 `NULL` 记录并进行替换。下面是它的工作原理：

```
test=# SELECT   CASE WHEN country IS NULL
                      THEN 'TOTAL' ELSE country END,
                CASE WHEN product_name IS NULL
                      THEN 'TOTAL' ELSE product_name END,
                sum
       FROM (SELECT    country, product_name, sum(amount_sold)
             FROM      t_sales
             GROUP BY ROLLUP (1, 2)
             ORDER BY 1, 2
           ) AS x;
 country   | product_name | sum
-----------+--------------+-----
 Argentina | Hats         | 111
 Argentina | Shoes        |  26
 Argentina | TOTAL        | 137
 Germany   | Hats         |  41
 Germany   | Shoes        |  63
 Germany   | TOTAL        | 104
 USA       | Hats         | 171
 USA       | Shoes        | 202
 USA       | TOTAL        | 373
 TOTAL     | TOTAL        | 614
(10 rows)
```

如您所见，所有 `NULL` 记录都已替换为 `TOTAL`，__这在许多情况下是显示此数据的更理想方式__。

## CUBE: 在 PostgreSQL 中高效创建数据立方体

如果您想添加“底线”，`ROLLUP` 很有用。__但是，您通常希望查看国家和产品的所有组合。`GROUP BY CUBE` 将做到这一点：__

```
test=# SELECT  country, product_name, sum(amount_sold)
       FROM    t_sales
       GROUP BY CUBE (1, 2)
       ORDER BY 1, 2;
 country   | product_name | sum
-----------+--------------+-----
 Argentina | Hats         | 111
 Argentina | Shoes        |  26
 Argentina |              | 137
 Germany   | Hats         |  41
 Germany   | Shoes        |  63
 Germany   |              | 104
 USA       | Hats         | 171
 USA       | Shoes        | 202
 USA       |              | 373
           | Hats         | 323
           | Shoes        | 291
           |              | 614
(12 rows)
```

在这种情况下，我们有所有的组合。从技术上讲，它等同于：`GROUP BY country` + `GROUP BY product_name` + `GROUP BY country_product_name` + `GROUP BY()`。我们可以使用多个语句来做到这一点，但一次做起来更容易——而且效率更高。

同样，添加 `NULL` 值以指示各种聚合级别。

## 分组集：执行计划

分组集不只是简单地重写查询以将其转换为 `UNION ALL` —— 数据库引擎中实际上有特定的代码来执行这些聚合。

您将看到的是一个 `MixedAggregate`，它能够同时在各个级别进行聚合。下面是一个例子：

```
test=# explain SELECT country, product_name, sum(amount_sold)
           FROM t_sales
           GROUP BY CUBE (1, 2)
           ORDER BY 1, 2;
                          QUERY PLAN
-----------------------------------------------------------
 Sort  (cost=64.15..65.65 rows=601 width=96)
   Sort Key: country, product_name
   ->  MixedAggregate  (cost=0.00..36.41 rows=601 width=96)
     Hash Key: country, product_name
     Hash Key: country
     Hash Key: product_name
     Group Key: ()
     ->  Seq Scan on t_sales ...
(8 rows)
```

查看 `MixedAggregate` 还揭示了哪些聚合是作为分组集的一部分执行的。

## 最后

一般来说，分组集是一个非常酷的功能，但通常不为人所知或被忽视。我们强烈建议使用这个很棒的东西来加速你的聚合。如果您正在处理大型数据集，它特别有用。

如果您想了解更多关于 PostgreSQL 和 SQL 的一般信息，您可能还会喜欢我关于“[使用 SQL 进行字符串编码][1]”的文章。

## 译者著

* 本文翻译自 Hans-Jürgen Schönig 的 [POSTGRESQL GROUPING SETS: ROLLUP & CUBE](https://www.cybertec-postgresql.com/en/postgresql-grouping-sets-rollup-cube/)。
* 您也可以在《由浅入深 PostgreSQL》一书的“第 4 章-处理高级 SQL”中查看有关分组集的使用。

<div class="just-for-fun">
笑林广记 - 启奏

一官被妻踏破纱帽。怒奏曰：“臣启陛下，臣妻罗唣，昨日相争，踏破臣的纱帽。”
上传旨云：“卿须忍耐，皇后有些惫赖，与朕一言不合，平天冠打得粉碎。你的纱帽只算得个卵袋。”
</div>

[OLTP]: https://en.wikipedia.org/wiki/Online_transaction_processing
[1]: https://www.cybertec-postgresql.com/en/finding-patterns-in-timeseries-a-poor-mans-method/
