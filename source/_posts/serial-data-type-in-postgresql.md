---
title: "【译】PostgreSQL 中的 serial 数据类型"
date: 2022-05-03 21:58:35 +0800
categories: 数据库
tags:
  - PostgreSQL
  - PG Casts
  - 翻译
---

如果您曾经想知道在声明具有 `seria l`数据类型的列时幕后发生了什么，那么这一集就是为您准备的。现在，如果您已经使用 PostgreSQL 有一段时间了，您可能已经习惯了使用 `id` 为 `serial` 类型创建的表。

类似于下面的表：

```sql
CREATE TABLE users (id serial primary key);
```

我们经常看到它带有一个 `id` 列。在这一集中，我想看看 `serial` 数据类型，并探讨当我们将列定义为 `serial` 时会发生什么。

<!--more-->

让我们删除主键部分，以便我们可以专注于 `serial` 类型数据。我们还将添加一个常规 `counter` 整数列进行比较：

```sql
CREATE TABLE users (id serial, counter integer);
```

上面的语句创建了我们的 `users` 表，其中包含一个 `id` 列和一个 `counter` 列。让我们看一下：

```sql
\d users
```
```
                             Table "public.users"
 Column  |  Type   | Collation | Nullable |              Default
---------+---------+-----------+----------+-----------------------------------
 id      | integer |           | not null | nextval('users_id_seq'::regclass)
 counter | integer |           |          |
```

The first thing we'll notice is that our id column gets a type of integer just like the counter column. Whereas we explicitly declared counter as an integer, serial implicitly sets id as an integer. This is because the serial data type is an auto-incrementing integer.

我们注意到的第一件事是 `id` 列获得了与 `counter` 列相同的整型数据类型。虽然我们将 `counter` 显式声明为整型，但 `serial` 隐式将 `id` 设置为整型。这是因为 `serial` 数据类型是自增整数。

接下来我们会注意到 `serial` 给 `id` 列提供了一堆 `counter` 列没有的修饰符。我们还可以看到，它获取了一个默认值。这是自增的一部分。默认值是在 `users_id_seq` 上调用的 `nextval()` 函数。这确保了我们的 `id` 列具有唯一的、单调递增的值。每次我们插入 `users` 表时，`id` 的默认值将是序列中的下一个值。当然，这假设我们总是让 `id` 设置为其默认值。

好的，所以我们的默认值是基于一个序列的，但是这个序列是从哪里来的呢？我不记得创建一个。

```sql
\d
```
```
            List of relations
 Schema |     Name     |   Type   |  Owner
--------+--------------+----------+---------
 public | users        | table    | pgcasts
 public | users_id_seq | sequence | pgcasts
(2 rows)
```

当我们将 `id` 列声明为 `serial` 时，PostgreSQL 将为我们创建了一个序列。PostgreSQL 根据表名和列名命名序列，因此这里的序列名为 `users_id_seq`。

如果我们对表进行几次插入，我们可以看到调用 `nextval` 对这个序列的影响。

```sql
INSERT INTO users (counter) VALUES (23), (42), (101);
```

现在，让我们看一下 `users` 表的内容：

```sql
TABLE users;
```
```
 id | counter
----+---------
  1 |      23
  2 |      42
  3 |     101
(3 rows)
```

序列从 1 开始，然后从 1 开始对每条记录进行计数。现在，我们应该更好地了解将列声明为 `serial` 时会发生什么。

## 拓展

`serial` 是 PostgreSQL 中创建自增列的一种方法，除了 `serial` 之外，还有 `smallserial` 和 `bigserial`，它们本质上不是真正的类型，而只是用于更方便创建唯一标识符列的符号。这有点类似于其它数据库中的 `AUTO_INCREMENT`。

| 类型        | 别名    | 整型     |
|-------------|---------|----------|
| smallserial | serial2 | smallint |
| serial      | serial4 | integer  |
| bigserial   | serial8 | bigint   |

在当前实现中，指定：

```sql
CREATE TABLE tablename (
    colname SERIAL
);
```

等价于

```
CREATE SEQUENCE tablename_colname_seq AS integer;
CREATE TABLE tablename (
    colname integer NOT NULL DEFAULT nextval('tablename_colname_seq')
);
ALTER SEQUENCE tablename_colname_seq OWNED BY tablename.colname;
```

因为 `smallserial`、`serial` 和 `bigserial` 是使用序列实现的，所以即使没有删除任何行，列中出现的值序列也可能存在“漏洞”或间隙。即使包含该值的行从未成功插入到表列中，从序列分配的值仍然被使用。

我们可以通过下面的示例来验证，首先开启一个事务，然后插入一条记录。
```sql
BEGIN;
INSERT INTO users (counter) VALUES (300);
TABLE users;
```
```
 id | counter
----+---------
  1 |      23
  2 |      42
  3 |     101
  4 |     300
(4 rows)
```

随后，我们回滚事务，并重新插入一条记录。

```sql
ROLLBACK;
INSERT INTO users (counter) VALUES (205);
TABLE users;
```
```
 id | counter
----+---------
  1 |      23
  2 |      42
  3 |     101
  5 |     205
(4 rows)
```

可以看到此时序列 `4` 已经被使用了，这个序列没有因为事务回滚而被释放出来。

## 译者著

[1] 本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第十集 [Serial Data Type](https://www.pgcasts.com/episodes/serial-data-type)。
[2] 本文的输出结果可能与原文存在部分差异，本文基于 pg15 devel 翻译结果。
[3] 拓展部分为译者自己根据官方文档进行整理。

## 参考

[1] https://www.postgresql.org/docs/current/datatype-numeric.html#DATATYPE-SERIAL


<div class="just-for-fun">
笑林广记 - 田主见鸡

一富人有余田数亩，租与张三者种，每亩索鸡一只。
张三将鸡藏于背后，田主遂作吟哦之声曰：“此田不与张三种。”
张三忙将鸡献出，田主又吟曰：“不与张三却与谁？”
张三曰：“初问不与我，后又与我何也？”
田主曰：“初乃无稽（鸡）之谈，后乃见机（鸡）而作也。”
</div>
