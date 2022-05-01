---
title: "【译】PostgreSQL 中使用不区分大小写的数据"
date: 2022-05-01 20:59:40 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
  - PG Casts
---

在本集中，我们将研究在处理不区分大小写的数据时需要考虑的事项。一个很好的例子是用户的电子邮件，我们可能希望不区分它的大小写。如果我们的用户尝试使用他们的电子邮件地址登录我们的应用程序，那么他们在输入电子邮件时使用全部大写还是全部小写并不重要。无论哪种方式，我们都应该认识它们。

<!--more-->

我们已经有一个包含一堆记录的用户表。

```sql
CREATE TABLE users (
  id serial primary key,
  email varchar not null unique
);

INSERT INTO users (email)
  SELECT 'person' || num || '@example.com'
  FROM generate_series(1, 10000) AS num;
```

我们看一下 `users` 表的结构：

```sql
\d users
```

```
                                 Table "public.users"
 Column |       Type        | Collation | Nullable |              Default
--------+-------------------+-----------+----------+-----------------------------------
 id     | integer           |           | not null | nextval('users_id_seq'::regclass)
 email  | character varying |           | not null |
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
    "users_email_key" UNIQUE CONSTRAINT, btree (email)
```

让我们看看我们的 `users` 表中的记录数以及部分用户：

```sql
SELECT count(*) FROM users;
```
```
 count
-------
 10000
(1 row)
```

```sql
SELECT * FROM users LIMIT 10;
```
```
 id |        email
----+----------------------
  1 | person1@example.com
  2 | person2@example.com
  3 | person3@example.com
  4 | person4@example.com
  5 | person5@example.com
  6 | person6@example.com
  7 | person7@example.com
  8 | person8@example.com
  9 | person9@example.com
 10 | person10@example.com
(10 rows)
```

回到为尝试登录的用户查找记录的场景。假设他们碰巧将电子邮件的第一个字母大写，所以我们不会找到他们的记录。

```sql
SELECT * FROM users WHERE email = 'Person5000@example.com';
```
```
 id | email
----+-------
(0 rows)
```

我们可以将所有内容包装在 `lower()` 函数中，以确保我们始终获得一致的电子邮件比较：

```sql
SELECT * FROM users WHERE lower(email) = lower('Person5000@example.com');
```
```
  id  |         email
------+------------------------
 5000 | person5000@example.com
(1 row)
```

看起来不错，但我们引入了一些问题。我们不再利用 `email` 列上的索引。我们可以通过 `EXPLAIN ANALYZE` 查看执行计划：

```sql
EXPLAIN ANALYZE
  SELECT * FROM users WHERE lower(email) = lower('Person5000@example.com');
```
```
                                            QUERY PLAN
---------------------------------------------------------------------------------------------------
 Seq Scan on users  (cost=0.00..224.00 rows=50 width=26) (actual time=4.906..9.377 rows=1 loops=1)
   Filter: (lower((email)::text) = 'person5000@example.com'::text)
   Rows Removed by Filter: 9999
 Planning Time: 0.143 ms
 Execution Time: 9.452 ms
(5 rows)
```

PostgreSQL 现在执行的是全表顺序扫描。这样做的原因是我们在 `email` 列上的一个索引仅用于 `email` 自身。如果我们要经常与 `lower()` 函数一起查询 `email` 列，我们需要一个不同的索引。

```sql
CREATE INDEX lower_email_idx ON users (lower(email));
```

我们可以通过查看表结构来查看索引：

```
\d users
```
```
                                 Table "public.users"
 Column |       Type        | Collation | Nullable |              Default
--------+-------------------+-----------+----------+-----------------------------------
 id     | integer           |           | not null | nextval('users_id_seq'::regclass)
 email  | character varying |           | not null |
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
    "lower_email_idx" btree (lower(email::text))
    "users_email_key" UNIQUE CONSTRAINT, btree (email)
```

让我们尝试之前的 `SELECT` 查询，看看我们现在再次获得了索引的好处：

```sql
EXPLAIN ANALYZE
  SELECT * FROM users WHERE lower(email) = lower('Person5000@example.com');
```
```
                                                       QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on users  (cost=4.67..75.73 rows=50 width=26) (actual time=0.128..0.142 rows=1 loops=1)
   Recheck Cond: (lower((email)::text) = 'person5000@example.com'::text)
   Heap Blocks: exact=1
   ->  Bitmap Index Scan on lower_email_idx  (cost=0.00..4.66 rows=50 width=0) (actual time=0.103..0.107 rows=1 loops=1)
         Index Cond: (lower((email)::text) = 'person5000@example.com'::text)
 Planning Time: 0.188 ms
 Execution Time: 0.202 ms
(7 rows)
```

如您所见，查询能够进行索引扫描，而不是顺序扫描。这将大大加快。当然，这会使写入该表的速度稍微慢一些，但这里的收益肯定超过了成本。

这里学到的教训是始终了解您最常访问数据的方式，以确保您不会错过索引带来的优势。

## 译者著

本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第九集 [Working With Case Insensitive Data](https://www.pgcasts.com/episodes/working-with-case-insensitive-data)。

<div class="just-for-fun">
笑林广记 - 薑字塔

一富翁问“薑”字如何写，对以草字头，次一字，次田字，又一字，又田字，又一字。
其人写草壹田壹田壹，写讫玩之，骂曰：“天杀的，如何诳我，分明作耍我造成一座塔了。”
</div>
