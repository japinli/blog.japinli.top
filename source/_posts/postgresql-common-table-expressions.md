---
title: "PostgreSQL Common Table Expressions"
date: 2019-03-08 21:34:43 +0800
category: Database
tags:
  - PostgreSQL
  - CTE
---

本文将介绍 PostgreSQL 中的 Common Table Expressions, CTE，也叫做公用表表达式。在介绍 CTE 之前，我们需要先了解 WITH 查询。WITH 查询是 PostgreSQL 针对复杂查询，允许用户在该查询内容编写辅助语句的功能，其中用户编写的辅助语句就是今天介绍的 CTE，你可以将 CTE 视为在当前查询中的一个临时表。CTE 的一大优点就是我们可将查询中的较为耗时且多次重复使用的部分通过 CTE 缓存起来，从而避免多次执行。

<!-- more -->

## 基本用法

下面是一个基本的 CTE 使用示列：

``` sql
WITH x AS (
    SELECT relkind, COUNT(*) FROM pg_class GROUP BY relkind
)
SELECT * FROM x WHERE relkind = 'r';
 relkind | count
---------+-------
 r       |    69
(1 row)

Time: 1.515 ms
```

上述示列中 CTE 的名称为 `x`，实质上就是由一个 `SELECT` 语句定义出来的，返回的结果是 `relkind` 以及该类型的表的数量。外围的 SQL 语句会将其视为一个临时表来使用。其实上述查询等价于下面的查询：

``` sql
SELECT * FROM (
    SELECT relkind, COUNT(*) FROM pg_class GROUP BY relkind
) AS x
WHERE relkind = 'r';
 relkind | count
---------+-------
 r       |    69
(1 row)

Time: 0.954 ms
```

## CTE 的缺点

从上面的查询结果可以看到，采用 CTE 的查询方式其执行的时间反而比子查询的方式要慢。这是为什么呢？我们先来看看他们之间的查询计划有什么不一样。

``` sql
EXPLAIN (analyze on, timing on)
WITH x AS (
    SELECT relkind, COUNT(*) FROM pg_class GROUP by relkind
)
SELECT * FROM x WHERE relkind = 'r';
                                                     QUERY PLAN
---------------------------------------------------------------------------------------------------------------------
 CTE Scan on x  (cost=17.17..17.26 rows=1 width=9) (actual time=0.678..0.687 rows=1 loops=1)
   Filter: (relkind = 'r'::"char")
   Rows Removed by Filter: 3
   CTE x
     ->  HashAggregate  (cost=17.13..17.17 rows=4 width=9) (actual time=0.670..0.675 rows=4 loops=1)
           Group Key: pg_class.relkind
           ->  Seq Scan on pg_class  (cost=0.00..15.42 rows=342 width=1) (actual time=0.011..0.150 rows=342 loops=1)
 Planning Time: 1.025 ms
 Execution Time: 1.054 ms
(9 rows)

EXPLAIN (analyze on, timing on)
SELECT * FROM (
	SELECT relkind, COUNT(*) FROM pg_class GROUP BY relkind
) AS x
WHERE relkind = 'r';
                                                QUERY PLAN
-----------------------------------------------------------------------------------------------------------
 GroupAggregate  (cost=0.00..16.66 rows=4 width=9) (actual time=0.291..0.292 rows=1 loops=1)
   Group Key: pg_class.relkind
   ->  Seq Scan on pg_class  (cost=0.00..16.27 rows=69 width=1) (actual time=0.018..0.261 rows=69 loops=1)
         Filter: (relkind = 'r'::"char")
         Rows Removed by Filter: 273
 Planning Time: 0.249 ms
 Execution Time: 0.395 ms
(7 rows)
```

目前，PostgreSQL 会将 CTE 的结构进行物化 (Materialize)，这就意味着创建一个临时表来存储其返回的结果，随后在该临时表上面进行过滤，正如查询计划中展示的一样。由于过滤条件不能直接应用到 CTE 中，PostgreSQL 也就无法在将上层的过滤条件下推到 CTE 中执行。然而，通过子查询的方式，PostgreSQL 可以很自然的将过滤条件下推到子查询中。从上面的结果可以看到，子查询的方式显然优于 CTE 的查询方式，这是因为 CTE 的查询方式执行了两次全表扫描以及需要额外的存储空间来存放 CTE 返回的结果。

而在 PostgreSQL 的官方文档中也存在如下描述：

> A useful property of WITH queries is that they are evaluated only once per
> execution of the parent query, even if they are referred to more than once by
> the parent query or sibling WITH queries. Thus, expensive calculations that
> are needed in multiple places can be placed within a WITH query to avoid
> redundant work. Another possible application is to prevent unwanted multiple
> evaluations of functions with side-effects. However, the other side of this
> coin is that the optimizer is less able to push restrictions from the parent
> query down into a WITH query than an ordinary subquery. The WITH query will
> generally be evaluated as written, without suppression of rows that the parent
> query might discard afterwards. (But, as mentioned above, evaluation might stop
> early if the reference(s) to the query demand only a limited number of rows.)

因此，我们在使用 CTE 时需要特别注意，正确的使用 CTE 将会带来性能的提升；如果使用不当，则很可能影响数据库性能。

## 禁止 CTE 物化？

那么我们是否能禁止 CTE 物化结果呢？就目前 PostgreSQL 来说，这是不可能的。但是在 2019 年 2 月 16 日 Tom Lane 提交了一个[补丁](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commitdiff;h=608b167f9f9c4553c35bb1ec0eab9ddae643989b)来解决该问题。

> Historically we've always materialized the full output of a CTE query,
> treating WITH as an optimization fence (so that, for example, restrictions
> from the outer query cannot be pushed into it).  This is appropriate when
> the CTE query is INSERT/UPDATE/DELETE, or is recursive; but when the CTE
> query is non-recursive and side-effect-free, there's no hazard of changing
> the query results by pushing restrictions down.
>
> Another argument for materialization is that it can avoid duplicate
> computation of an expensive WITH query --- but that only applies if
> the WITH query is called more than once in the outer query.  Even then
> it could still be a net loss, if each call has restrictions that
> would allow just a small part of the WITH query to be computed.
>
> Hence, let's change the behavior for WITH queries that are non-recursive
> and side-effect-free.  By default, we will inline them into the outer
> query (removing the optimization fence) if they are called just once.
> If they are called more than once, we will keep the old behavior by
> default, but the user can override this and force inlining by specifying
> NOT MATERIALIZED.  Lastly, the user can force the old behavior by
> specifying MATERIALIZED; this would mainly be useful when the query had
> deliberately been employing WITH as an optimization fence to prevent a
> poor choice of plan.
>
> Andreas Karlsson, Andrew Gierth, David Fetter
>
> Discussion: https://postgr.es/m/87sh48ffhb.fsf@news-spur.riddles.org.uk

这让用户禁止 CTE 物化结果成为可能，该功能预计在 PostgreSQL 12 版本中推出。

下面是在 PostgreSQL 12 开发版中的测试结果：

``` sql
EXPLAIN (analyze on, timing on)
WITH x AS (
    SELECT relkind, COUNT(*) FROM pg_class GROUP by relkind
)
SELECT * FROM x WHERE relkind = 'r';
                                                QUERY PLAN
-----------------------------------------------------------------------------------------------------------
 GroupAggregate  (cost=0.00..18.21 rows=4 width=9) (actual time=0.103..0.103 rows=1 loops=1)
   Group Key: pg_class.relkind
   ->  Seq Scan on pg_class  (cost=0.00..17.82 rows=69 width=1) (actual time=0.009..0.092 rows=69 loops=1)
         Filter: (relkind = 'r'::"char")
         Rows Removed by Filter: 317
 Planning Time: 0.406 ms
 Execution Time: 0.196 ms
(7 rows)

EXPLAIN (analyze on, timing on)
SELECT * FROM (
	SELECT relkind, COUNT(*) FROM pg_class GROUP BY relkind
) AS x
WHERE relkind = 'r';
                                                QUERY PLAN
-----------------------------------------------------------------------------------------------------------
 GroupAggregate  (cost=0.00..18.21 rows=4 width=9) (actual time=0.118..0.118 rows=1 loops=1)
   Group Key: pg_class.relkind
   ->  Seq Scan on pg_class  (cost=0.00..17.82 rows=69 width=1) (actual time=0.011..0.106 rows=69 loops=1)
         Filter: (relkind = 'r'::"char")
         Rows Removed by Filter: 317
 Planning Time: 0.120 ms
 Execution Time: 0.151 ms
(7 rows)

EXPLAIN (analyze on, timing on)
WITH x AS  MATERIALIZED (
    SELECT relkind, COUNT(*) FROM pg_class GROUP by relkind
)
SELECT * FROM x WHERE relkind = 'r';
                                                     QUERY PLAN
---------------------------------------------------------------------------------------------------------------------
 CTE Scan on x  (cost=18.83..18.92 rows=1 width=9) (actual time=0.174..0.176 rows=1 loops=1)
   Filter: (relkind = 'r'::"char")
   Rows Removed by Filter: 3
   CTE x
     ->  HashAggregate  (cost=18.79..18.83 rows=4 width=9) (actual time=0.171..0.172 rows=4 loops=1)
           Group Key: pg_class.relkind
           ->  Seq Scan on pg_class  (cost=0.00..16.86 rows=386 width=1) (actual time=0.005..0.042 rows=386 loops=1)
 Planning Time: 0.185 ms
 Execution Time: 0.249 ms
(9 rows)
```

PostgreSQL 12 版中为 CTE 新增了 `MATERIALIZED | NOT MATERIALIZED` 选项，这样用户就可以通过选项控制是否对 CTE 进行物化，而默认情况下是不对 CTE 进行物化。

## 总结

CTE 可以使我们编写的 SQL 查询更易于阅读且能通过物化的方式将结果缓存到起来从而提升查询性能；但是，CTE 的使用不当甚至有可能导致性能的降低，例如在查询中仅使用一次的情况。当我们使用 CTE 时，需要考虑以下几个问题:

1. 该 CTE 是否会被重复使用？
2. 查询中的条件是否能在 CTE 中应用?

## 参考

[1] [Allow user control of CTE materialization, and change the default behavior](https://www.depesz.com/2019/02/19/waiting-for-postgresql-12-allow-user-control-of-cte-materialization-and-change-the-default-behavior/#more-3491)
[2] [Be careful with CTE in PostgreSQL](https://medium.com/@hakibenita/be-careful-with-cte-in-postgresql-fca5e24d2119)
