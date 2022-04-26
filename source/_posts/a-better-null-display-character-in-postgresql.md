---
title: "【译】PostgreSQL 更直观的 NULL 值显示"
date: 2022-04-25 21:23:45 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
  - PG Casts
---

在这一集中，我将向您展示如何为 `NULL` 值提供更好的显示字符。但是在我们开始之前，让我们看一个例子来帮助我们理解为什么我们甚至需要一个显示字符来表示 `NULL` 值。

<!--more-->

假设我们有一张 `users` 表：

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR NOT NULL UNIQUE,
  first VARCHAR,
  last VARCHAR
);
```

该表包含一些用户：

```sql
INSERT INTO users (email, first, last)
  VALUES ('lizlemon@nbc.com', 'Liz', 'Lemon');

INSERT INTO users (email)
  VALUES ('jack.donaghy@nbc.com');

INSERT INTO users (email, first)
  VALUES ('kenneth.parcell@nbc.com', 'Kenneth');

INSERT INTO users (email, first, last)
  VALUES ('grizz@nbc.com', 'Grizz', '');
```

现在让我们看看`users` 表中的所有记录：

```sql
TABLE users;
```

```
 id |          email          |  first  | last
----+-------------------------+---------+-------
  1 | lizlemon@nbc.com        | Liz     | Lemon
  2 | jack.donaghy@nbc.com    |         |
  3 | kenneth.parcell@nbc.com | Kenneth |
  4 | grizz@nbc.com           | Grizz   |
(4 rows)
```

一些 `first` 和 `last` 列被保留为空，其中有一个 `last` 的值为空字符串。但我们无法区分它们。问题在于，psql 显示的 `NULL` 值带有一个空白字符串，这与实际的空白字符串无法区分。

在 psql 中浏览这样的数据很快就会令人沮丧。我们需要一个更好的、真正突出的 `NULL` 值显示字符。我倾向于使用空集合符号 `Ø`。这可以通过 [`\pset meta`](https://www.postgresql.org/docs/current/app-psql.html) 命令进行设置。

```
\pset null 'Ø'
```

我们可以再看看我们的 `users` 表记录，注意看看其中的区别。

```sql
TABLE users;
```

```
 id |          email          |  first  | last
----+-------------------------+---------+-------
  1 | lizlemon@nbc.com        | Liz     | Lemon
  2 | jack.donaghy@nbc.com    | Ø       | Ø
  3 | kenneth.parcell@nbc.com | Kenneth | Ø
  4 | grizz@nbc.com           | Grizz   |
(4 rows)
```

这样好多了。现在我们可以很容易的区分 `NULL` 值和空字符串。

我总是希望在启动 psql 会话的时候自动设置该选项，因此我将其添加到了 `.psqlrc` 文件中。

您可能想知道空白字符串和 `NULL` 值之间是否有任何有意义的区别，或者为什么我们允许空值。这都是另一集的问题。

## 译者著

* 本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第二集 [A Better Null Display Characterd](https://www.pgcasts.com/episodes/a-better-null-display-character)。

* `\pset meta` 命令用于设置查询结果输出的样式，您可以使用不带选项的 `\pset` 查看所有选项的当前值。

<div class="just-for-fun">
笑林广记 - 春生帖

一财主不通文墨，谓友曰：“某人甚是欠通，清早来拜我，就写晚生帖。”
傍一监生曰：“这倒还差不远，好像这两日秋天拜客，竟有写春生帖子的哩。”
</div>
