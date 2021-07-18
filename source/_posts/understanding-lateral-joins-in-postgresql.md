---
title: "理解 PostgreSQL 中的 LATERAL 连接"
date: 2021-07-18 18:11:00 +0800
category: 数据库
tags:
  - PostgreSQL
  - 翻译
---

`LATERAL` 连接是 PostgreSQL 和其他关系型数据库（如 Oracle、DB2 和 MS SQL）中鲜为人知的功能之一。然而，`LATERAL` 连接是一个非常有用的功能，本文将带你看看用它们能完成什么有意义的事情。

<!-- more -->

## 深入理解 FROM

在我们深入研究 `LATERAL` 之前，有必要从哲学的家的角度来考虑一下 `SELECT` 和 `FROM` 子句。例如：

```sql
SELECT whatever FROM tab;
```

本质上，我们可以将这个语句看作是一个循环。用伪代码来编写此 SQL 语句看起来类似下面的代码段：

```
for x in tab
loop
     “do whatever”
end loop
```

对于表中的没一条记录，我们做 `SELECT` 子句所说的事情。通常情况下，数据只是按原样返回。一个 `SELECT` 语句可以被看作是一个循环。当时，如果我们需要一个“嵌套”的循环呢？这就是 `LATERAL` 的用处。

## LATERAL 连接：创建示例数据

让我们想象一个简单的例子。想象一下，我们有一系列产品，也有客户的愿望清单。现在的目标是为每个愿望清单找到最好的 3 种产品。下面的 SQL 代码段创建了一些样本数据。

```sql
CREATE TABLE t_product AS
    SELECT   id AS product_id,
             id * 10 * random() AS price,
             'product ' || id AS product
    FROM generate_series(1, 1000) AS id;

CREATE TABLE t_wishlist
(
    wishlist_id        int,
    username           text,
    desired_price      numeric
);

INSERT INTO t_wishlist VALUES
    (1, 'hans', '450'),
    (2, 'joe', '60'),
    (3, 'jane', '1500')
;
```

产品表填充了 1000 种产品。价格是随机的，我们用一个相当有创意的名字来命名产品。

```sql
test=# SELECT * FROM t_product LIMIT 10;
 product_id | price              | product
------------+--------------------+------------
          1 | 6.756567642432323  | product 1
          2 | 5.284467408540081  | product 2
          3 | 28.284196164210904 | product 3
          4 | 13.543868035690423 | product 4
          5 | 30.576923884383156 | product 5
          6 | 26.572431211361902 | product 6
          7 | 64.84599396020204  | product 7
          8 | 21.550701384168747 | product 8
          9 | 28.995584553969174 | product 9
         10 | 17.31335004787411  | product 10
(10 rows)
```

接下来，我们有一个愿望清单。

```sql
test=# SELECT * FROM t_wishlist;
 wishlist_id | username | desired_price
-------------+----------+---------------
           1 | hans     | 450
           2 | joe      | 60
           3 | jane     | 1500
(3 rows)
```

正如你所看到的，愿望清单属于一个用户，并且有一个我们想要建议的那三种产品的理想价格。

## 执行 LATERAL 连接

在提供了一些样本数据并将其加载到我们的 PostgreSQL 数据库后，我们可以接近并尝试提出解决方案。

假设我们想为每个愿望找到前三个产品，可以使用下面的伪代码：

```
for x in wishlist
loop
      for y in products order by price desc
      loop
           found++
           if found <= 3
           then
               return row
           else
               jump to next wish
           end
      end loop
end loop
```

重要的是，我们需要两个循环。首先，我们需要遍历愿望列表，然后我们看一下排序后的产品列表，挑选 3 个，然后进入下一个愿望列表。

让我们看看如何使用 `LATERAL` 连接来完成这个任务：

```sql
SELECT        *
FROM      t_wishlist AS w,
    LATERAL  (SELECT      *
        FROM       t_product AS p
        WHERE       p.price < w.desired_price
        ORDER BY p.price DESC
        LIMIT 3
       ) AS x
ORDER BY wishlist_id, price DESC;
```

我们将一步一步的解释这个查询。你在 `FROM` 子句中看到的第一件事是 `t_wishlist` 表。 `LATERAL` 现在可以做的是使用愿望清单中的记录来施展它的魔法。因此，对于愿望清单中的每条记录，我们都要挑选三个产品。为了弄清我们需要哪些产品，我们可以利用 `w.desired_price`。换句话说，这就像一个“带参数的连接”。`FROM` 子句可以看作我们伪代码中的“外循环”，`LATERAL` 可以被看作是“内循环”。

结果集看起来如下所示：

```
 wishlist_id | username | desired_price | product_id | price              | product
-------------+----------+---------------+------------+--------------------+-------------
           1 | hans     | 450           | 708        | 447.0511375753179  | product 708
           1 | hans     | 450           | 126        | 443.6560873146138  | product 126
           1 | hans     | 450           | 655        | 438.0566432022443  | product 655
           2 | joe      | 60            | 40         | 59.32252841190291  | product 40
           2 | joe      | 60            | 19         | 59.2142714048882   | product 19
           2 | joe      | 60            | 87         | 58.78014573804254  | product 87
           3 | jane     | 1500          | 687        | 1495.8794483743645 | product 687
           3 | jane     | 1500          | 297        | 1494.4586352980593 | product 297
           3 | jane     | 1500          | 520        | 1490.7849437550085 | product 520
(9 rows)
```

PostgreSQL 为每个愿望清单返回三条记录，这正是我们想要的。这里重要的部分是在 `SELECT` 内部的 `LIMIT` 子句，而不是 `LATERAL`。因此，它限制的是每个愿望清单的行数，而不是总的行数。

PostgreSQL 在优化 `LATERAL` 连接方面做的相当行。在我们的例子中，执行计划看起来很简单。

```sql
test=# explain SELECT    *
FROM    t_wishlist AS w,
        LATERAL (SELECT *
               FROM t_product AS p
               WHERE p.price < w.desired_price
               ORDER BY p.price DESC
               LIMIT 3
               ) AS x
ORDER BY wishlist_id, price DESC;
                                    QUERY PLAN
---------------------------------------------------------------------------------------
 Sort (cost=23428.53..23434.90 rows=2550 width=91)
   Sort Key: w.wishlist_id, p.price DESC
   -> Nested Loop (cost=27.30..23284.24 rows=2550 width=91)
      -> Seq Scan on t_wishlist w (cost=0.00..18.50 rows=850 width=68)
      -> Limit (cost=27.30..27.31 rows=3 width=23)
            -> Sort (cost=27.30..28.14 rows=333 width=23)
                  Sort Key: p.price DESC
                  -> Seq Scan on t_product p (cost=0.00..23.00 rows=333 width=23)
                        Filter: (price < (w.desired_price)::double precision)
(9 rows)
```

`LATERAL` 连接是非常有用的，在许多情况下可以利用它来加速操作，或使代码更容易理解。

## 写在最后

如果你想了解更多关于一般的连接，如如你现在想要阅读更多关于 PostgreSQL 的信息，可以考虑看看 Laurenz Albe 关于 [PostgreSQL 的连接策略的优秀文章](https://www.cybertec-postgresql.com/en/join-strategies-and-performance-in-postgresql/)。

如果你想了解更多关于 PostgreSQL 优化器的一般情况，如果你想要了解更多关于优化和其他与 PostgreSQL 查询优化相关的重要主题，请查看我关于[优化器的博文](https://www.cybertec-postgresql.com/en/how-the-postgresql-query-optimizer-works/)。

## 译者著

* 本文翻译自 Hans-Jürgen Schönig 的 [UNDERSTANDING LATERAL JOINS IN POSTGRESQL](https://www.cybertec-postgresql.com/en/understanding-lateral-joins-in-postgresql/)。


<div class="just-for-fun">
笑林广记 - 发利市

一官新到任，祭仪门前毕，有未烬纸钱在地，官即取一锡锭藏好。
门子禀曰：“老爷这是纸钱，要他何用？”
官曰：“我知道，且等我发个利市者。”
</div>
