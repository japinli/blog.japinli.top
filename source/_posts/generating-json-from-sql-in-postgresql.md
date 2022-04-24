---
title: "【译】PostgreSQL 从 SQL 生产 JSON 数据"
date: 2022-04-24 21:06:30 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
---

在 PostgreSQL 中生成 JSON 的速度可能是将关系数据复制到应用程序，随后通过应用程序生成 JSON 的几倍。这对于返回 JSON 的 API 尤其有用。

<!--more-->

我们的示例是一个简单的书签应用。首先，我们创建一个 `users` 表。

```sql
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  email VARCHAR NOT NULL,
  name VARCHAR NOT NULL,
  password_digest VARCHAR NOT NULL
);
```

接着，我们新增一些用户。

```sql
INSERT INTO users VALUES
  (1, 'john@example.com', 'John', '0123456789abcdef'),
  (2, 'jane@example.com', 'Jane', 'abcdef0123456789');
```

通过下面的 SQL 查看 `users` 表中的信息（注意，`TABLE <table_name>` 是 PostgreSQL 对 SQL 的扩展）。

```sql
TABLE users;
```

```
 id |      email       | name | password_digest
----+------------------+------+------------------
  1 | john@example.com | John | 0123456789abcdef
  2 | jane@example.com | Jane | abcdef0123456789
(2 rows)
```

我们可以通过 `row_to_json` 函数将一个用户对象转换为 JSON 格式的数据。

```sql
SELECT row_to_json(users)
FROM users
WHERE id = 1;
```

```
                                      row_to_json
----------------------------------------------------------------------------------------
 {"id":1,"email":"john@example.com","name":"John","password_digest":"0123456789abcdef"}
(1 row)
```

上面的示例可以工作，但是它将 `users` 表的所有信息都返回了。实际上，我们并不想要暴露用户的密码信息。

我们可以使用 `row` 构造器来规避这个问题。

```sql
SELECT row_to_json(row(id, name, email))
FROM users
WHERE id = 1;
```

```
                 row_to_json
----------------------------------------------
 {"f1":1,"f2":"John","f3":"john@example.com"}
(1 row)
```

这几乎也能达到我们的预期，但是 `row` 构造器会丢弃字段的名称。我们可以通过子查询的方式来保留字段名称。

```sql
SELECT row_to_json(t)
FROM (
  SELECT id, name, email
  FROM users
  WHERE id = 1
) t;
```

```
                    row_to_json
---------------------------------------------------
 {"id":1,"name":"John","email":"john@example.com"}
(1 row)
```

值得一提的是，另一种解决方案是创建一个复合类型，并将行强制转换为该类型。然而，子查询方法对我来说效果更好。

现在，让我们看看如何创建具有嵌套值的JSON文档。我们将从创建 `bookmarks` 表开始。

```sql
CREATE TABLE bookmarks (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users,
  name VARCHAR NOT NULL,
  url VARCHAR NOT NULL
);
```

接着，插入一些示例书签。

```sql
INSERT INTO BOOKMARKS (user_id, name, url) VALUES
  (1, 'Hashrocket', 'https://www.hashrocket.com'),
  (1, 'PostgreSQL Docs', 'http://www.postgresql.org/docs/current/static/index.html'),
  (2, 'Google', 'https://www.google.com'),
  (2, 'Stack Overflow', 'http://stackoverflow.com/'),
  (2, 'YouTube', 'https://www.youtube.com');
```

让我们尝试一个嵌套的 JSON 查询。

```sql
SELECT row_to_json(t)
FROM (
  SELECT
    id, name, email,
    (
      SELECT json_agg(row_to_json(bookmarks))
      FROM bookmarks
      WHERE user_id = users.id
    ) AS bookmarks
  FROM users
  WHERE id=1
) t;
```

```
                                                                                                                         row_to_json

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 {"id":1,"name":"John","email":"john@example.com","bookmarks":[{"id":1,"user_id":1,"name":"Hashrocket","url":"https://www.hashrocket.com"}, {"id":2,"user_id":1,"name":"PostgreSQL Docs","url":"http://www.postgresql.org/docs/current/static/index.html"}]}
(1 row)
```

[`row_to_json`](https://www.postgresql.org/docs/current/functions-json.html#FUNCTIONS-JSON-CREATION-TABLE) 函数的第二个参数可用于格式化 JSON 数据的输出，使其更容易查看。

```sql
SELECT row_to_json(t, true)
FROM (
  SELECT
    id, name, email,
    (
      SELECT json_agg(row_to_json(bookmarks, true))
      FROM bookmarks
      WHERE user_id = users.id
    ) AS bookmarks
  FROM users
  WHERE id=1
) t;
```

```
                             row_to_json
----------------------------------------------------------------------
 {"id":1,                                                            +
  "name":"John",                                                     +
  "email":"john@example.com",                                        +
  "bookmarks":[{"id":1,                                              +
  "user_id":1,                                                       +
  "name":"Hashrocket",                                               +
  "url":"https://www.hashrocket.com"}, {"id":2,                      +
  "user_id":1,                                                       +
  "name":"PostgreSQL Docs",                                          +
  "url":"http://www.postgresql.org/docs/current/static/index.html"}]}
(1 row)
```

唯一的变化是我们使用带有 `json_agg` 函数的子查询为用户聚合所有书签。`json_agg` 将 JSON 对象聚合到 JSON 数组中。

如果我们想获取所有用户及其所有书签，我们只需删除 `WHERE` 子句，并将 `json_agg` 添加到最外层的查询中。

```sql
SELECT json_agg(row_to_json(t, true))
FROM (
  SELECT
    id, name, email,
    (
      SELECT json_agg(row_to_json(bookmarks, true))
      FROM bookmarks
      WHERE user_id = users.id
    ) AS bookmarks
  FROM users
) t;
```

```
                                    json_agg
--------------------------------------------------------------------------------
 [{"id":1,                                                                     +
  "name":"John",                                                               +
  "email":"john@example.com",                                                  +
  "bookmarks":[{"id":1,                                                        +
  "user_id":1,                                                                 +
  "name":"Hashrocket",                                                         +
  "url":"https://www.hashrocket.com"}, {"id":2,                                +
  "user_id":1,                                                                 +
  "name":"PostgreSQL Docs",                                                    +
  "url":"http://www.postgresql.org/docs/current/static/index.html"}]}, {"id":2,+
  "name":"Jane",                                                               +
  "email":"jane@example.com",                                                  +
  "bookmarks":[{"id":3,                                                        +
  "user_id":2,                                                                 +
  "name":"Google",                                                             +
  "url":"https://www.google.com"}, {"id":4,                                    +
  "user_id":2,                                                                 +
  "name":"Stack Overflow",                                                     +
  "url":"http://stackoverflow.com/"}, {"id":5,                                 +
  "user_id":2,                                                                 +
  "name":"YouTube",                                                            +
  "url":"https://www.youtube.com"}]}]
(1 row)
```

一开始使用它时可能有点尴尬，但在需要更高性能时，在 PostgreSQL 中生成 JSON 是一个有用的功能。

## 译者著

* 本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第一集 [Generating JSON from SQL](https://www.pgcasts.com/episodes/generating-json-from-sql)。
* 本文实验结果基于 PostgreSQL 15devel ([92e7a53752](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=92e7a537520927107742af654619e55f34072942))。

<div class="just-for-fun">
笑林广记 - 仿制字

一生见有投制生帖者，深叹制字新奇，偶致一远札，遂效之。
仆致书回，生问见书有何话说，仆曰：“当面启看，便问老相公无恙，又问老安人好否。予曰：‘俱安。’乃沉吟半晌，带笑而入，才发回书。”
生大喜曰：“人不可不学，只一字用着得当，便一家俱问到，添下许多殷勤。”
</div>
