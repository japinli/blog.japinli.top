---
title: "【译】PostgreSQL 为列添加非空约束"
date: 2022-05-05 21:22:21 +0800
categories: 数据库
tags:
  - PostgreSQL
  - PG Casts
  - 翻译
---

在这一集中，我将向现有的 PostgreSQL 列添加一个非空约束。

<!--more-->

首先，我们看看 `users` 表的定义：

```sql
\d users
```
```
                      Table "public.users"
  Column   |       Type        | Collation | Nullable | Default
-----------+-------------------+-----------+----------+---------
 full_name | character varying |           | not null |
 admin     | boolean           |           |          |
```

我们有两列：用户的全名 `full_name` 和管理员标志 `admin`。

使用这个数据库的 Rails 应用程序总是期望这两个值永远不会为空。如果是这样，世界各地的计算机就会起火。

我们的 Rails 开发人员通过在用户模型上添加 ActiveRecord 存在验证来完成这一壮举。所以，这些值永远不能为空，对吧？不，您错了。

当我们在谈论时，一个流氓开发人员已经登录到 psql，并且正在进行黑客攻击。

```sql
TABLE users;
```
```
    full_name    | admin
-----------------+-------
 Kenneth Parcell | t
 Liz Lemon       | 💀
 Tracy Jordan    | 💀
(3 rows)
```

在这个 psql 会话中，我的空值是一个骷髅头（💀）。如果管理员标志为空，这意味着什么？这是否意味着他们不是管理员？

在这里我们可以看到为什么 `NOT NULL` 的数据库约束很重要。即使我们可以阻止人们直接从 SQL 插入空数据，数据库仍然允许这样做。有一天，其他应用程序也将与该数据库进行交互。我们必须告诉这些应用程序中的每一个约束，否则它们将不会遵守它。

数据库应该是关于它将允许和不允许什么样的数据的单一事实来源。不幸的是，如果我们尝试只添加约束，我们有现有的数据会得到这个错误：

```sql
ALTER TABLE users ALTER COLUMN admin SET NOT NULL;
```
```
ERROR:  column "admin" of relation "users" contains null values
```

是的，`users` 表里面存在空值。我们首先需要做的是执行 `UPDATE` 语句。我选择了默认的 `false`。通常您可以想出比 `NULL` 更好的东西。

```sql
UPDATE users SET admin = false WHERE admin IS NULL;
```
```
UPDATE 2
```

现在，`users` 表不存在空值了。

```sql
TABLE users;
```
```
    full_name    | admin
-----------------+-------
 Kenneth Parcell | t
 Liz Lemon       | f
 Tracy Jordan    | f
(3 rows)
```

是时候添加我们的迁移了。我们还将添加一个与我们的更新语句匹配的默认值。这将保护我们免受不良数据的影响。

```sql
ALTER TABLE users ALTER COLUMN admin SET NOT NULL;
ALTER TABLE users ALTER COLUMN admin SET DEFAULT FALSE;
```

现在情况看起来好多了：

```sql
\d users
```
```
                      Table "public.users"
  Column   |       Type        | Collation | Nullable | Default
-----------+-------------------+-----------+----------+---------
 full_name | character varying |           | not null |
 admin     | boolean           |           | not null | false
```

Rails 开发人员可能想知道如何使用 ActiveRecord 对现有数据实施这种类型的约束。有几种方法可以实现这一点。在 Hashrocket，我们用普通的旧 SQL 编写了很多 ActiveRecord 迁移。这是我们计划在未来一集中介绍的内容。

总而言之，尽早保护您的数据库免受空值的影响，您将拥有更好的数据。

## 演示示例

```sql
-- Set nulls to skulls
\pset null 💀

-- Create users table
CREATE TABLE users (
  full_name varchar not null,
  admin boolean
);

-- Create users with null values
INSERT INTO users (full_name, admin) VALUES ('Kenneth Parcell', true);
INSERT INTO users (full_name) VALUES ('Liz Lemon');
INSERT INTO users (full_name) VALUES ('Tracy Jordan');
```

## 译者著

本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第十一集 [Adding Not Null to an Existing Column](https://www.pgcasts.com/episodes/adding-not-null-to-an-existing-column)。

<div class="just-for-fun">
笑林广记 - 讲解

有姓李者暴富而骄，或嘲之云：“一童读百家姓首句，求师解释，师曰：‘赵是精赵的赵字（吴俗谓人呆为赵），钱是有铜钱的钱字，孙是小猢狲的孙字，李是姓张姓李的李字。’童又问：‘倒转亦可讲得否？’师曰：‘也讲得。’童曰：‘如何讲？’师曰：‘不过姓李的小猢狲，有了几个臭铜钱，一时就精赵起来。’”
</div>
