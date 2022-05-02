---
title: "【译】PostgreSQL 更多不区分大小写的数据"
date: 2022-05-02 21:34:53 +0800
categories: 数据库
tags:
  - PostgreSQL
  - PG Casts
  - 翻译
---

在{% post_link working-with-case-insensitive-data-in-postgresql 上一集 %}<sup>[1]</sup>中，我们探讨了查询被认为不区分大小写的数据时的一些注意事项。在本集中，我们将研究在处理不区分大小写的数据时可以使用的唯一索引。

<!--more-->

我们从一个如下所示的 `users` 表开始：

```sql
\d old.users
```
```
                                     Table "old.users"
 Column |       Type        | Collation | Nullable |                Default
--------+-------------------+-----------+----------+---------------------------------------
 id     | integer           |           | not null | nextval('old.users_id_seq'::regclass)
 email  | character varying |           | not null |
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
    "users_email_key" UNIQUE CONSTRAINT, btree (email)
```

我们在 `email` 字段上有一个唯一索引，但是因为我们希望大多数查询在 `email` 上使用 `lower()` 函数，所以我们决定添加另一个索引。我们可以在当前表上看到：

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
    "users_lower_email_idx" btree (lower(email::text))
```

使用此表，我们可以进行索引的不区分大小写的查询。不过，这两个表还有另一个主要问题。它们都将允许我们通过为这些电子邮件使用不同的大小写来插入具有重复电子邮件的记录。

要看看这是什么样子，让我们看看两个表中的第一条记录：

```sql
SELECT * FROM old.users, users limit 1;
```
```
 id |        email        | id |        email
----+---------------------+----+---------------------
  1 | person1@example.com |  1 | person1@example.com
(1 row)
```

现在让我们插入一些违反我们希望我们的表强制执行的唯一性的记录：

```sql
INSERT INTO old.users (email) VALUES ('PERSON1@EXAMPLE.COM');
INSERT INTO users (email) VALUES ('PERSON1@EXAMPLE.COM');
```

哎呀。我们在这里没有充分执行我们想要的唯一性约束（即唯一性检查时忽略大小写）。我们需要一个更好的索引。让我们关注 `users` 表，忽略 `old.users` 表。

如果我们再看一下表的描述，我们可能会注意到问题。

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
    "users_lower_email_idx" btree (lower(email::text))
```

`users_lower_email_idx` 并不是唯一性索引。如果我们更新它以强制 `email` 列的小写版本的唯一性，那么我们可以确定我们不会得到任何重复的记录。那么，如果我们只是尝试使用这个额外的约束添加另一个索引呢？

```sql
CREATE UNIQUE INDEX users_unique_lower_email_idx ON users (lower(email));
```
```
ERROR:  could not create unique index "users_unique_lower_email_idx"
DETAIL:  Key (lower(email::text))=(person1@example.com) is duplicated.
```

哦，对了，我们需要先清除所有重复项，这意味着我们需要删除我们之前插入的记录。

此外，我们应该替换现有索引以减少表上的开销。为此，我们需要启动一个事务以确保在交换索引时数据的一致性。

```sql
BEGIN;
DELETE FROM users WHERE email = 'PERSON1@EXAMPLE.COM';
DROP INDEX users_lower_email_idx;
CREATE UNIQUE INDEX users_unique_lower_email_idx ON users (lower(email));
COMMIT;
```

我们可以通过尝试现在无效的插入语句来查看我们的新索引：

```sql
INSERT INTO users (email) VALUES ('PERSON1@EXAMPLE.COM');
```
```
ERROR:  duplicate key value violates unique constraint "users_unique_lower_email_idx"
DETAIL:  Key (lower(email::text))=(person1@example.com) already exists.
```

我们不区分大小写的 `email` 列现在更加完善。

## 演示示例

```sql
CREATE SCHEMA old;
CREATE TABLE old.users (
  id serial primary key,
  email varchar not null unique
);

CREATE TABLE users (
  id serial primary key,
  email varchar not null unique
);
CREATE INDEX users_lower_email_idx ON users (lower(email));

INSERT INTO old.users (email)
  SELECT 'person' || num || '@example.com'
  FROM generate_series(1, 10000) AS num;

INSERT INTO users (email)
  SELECT 'person' || num || '@example.com'
  FROM generate_series(1, 10000) AS num;
```

## 译者著

[1] 这里应该是后一集（第九集），应该是上传顺序出错来。
[2] 本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第八集 [More Case Insensitive Data](https://www.pgcasts.com/episodes/more-case-insensitive-data)。

<div class="just-for-fun">
笑林广记 - 医银入肚

一富翁含银于口，误吞入，肚甚痛，延医治之。
医曰：“不难，先买纸牌一副，烧灰咽之，再用艾丸炙脐，其银自出。”
翁询其故，医曰：“外面用火烧，里面有强盗打劫，哪怕你的银子不出来。”
</div>
