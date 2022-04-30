---
title: "【译】PostgreSQL 9.5 中的 SKIP LOCKED 特性"
date: 2022-04-30 21:33:29 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
  - PG Casts
---

`SKIP LOCKED` 最明显的用途是多个工作者（worker）消费单一来源的作业（job）。因此，我们的示例将是一个简单的作业队列。

<!--more-->

我们将创建简单的 `jobs` 表，它包含 `id` 和 `payload` 两个属性列。

```sql
CREATE TABLE jobs (
  id serial primary key,
  payload json not null
);
```

接着，我们添加一些作业。

```sql
INSERT INTO jobs(payload) VALUES
  ('{"type": "send_welcome", "to": "john@example.com"}'),
  ('{"type": "send_password_reset", "to": "sally@example.com"}'),
  ('{"type": "send_welcome_email", "to": "jane@example.com"}'),
  ('{"type": "send_welcome_email", "to": "sam@example.com"}'),
  ('{"type": "send_password_reset", "to": "bill@example.com"}');
```

我们查看一下插入的数据。

```sql
TABLE jobs;
```
```
 id |                          payload
----+------------------------------------------------------------
  1 | {"type": "send_welcome", "to": "john@example.com"}
  2 | {"type": "send_password_reset", "to": "sally@example.com"}
  3 | {"type": "send_welcome_email", "to": "jane@example.com"}
  4 | {"type": "send_welcome_email", "to": "sam@example.com"}
  5 | {"type": "send_password_reset", "to": "bill@example.com"}
(5 rows)
```

一个工作者通常会做以下工作。首先，启动一个事务。

```sql
BEGIN;
```

PostgreSQL 中的行级锁只能在一个事务中才能工作。紧接着，我们选择一行记录并执行 `FOR UPDATE`。

```sql
SELECT * FROM jobs LIMIT 1 FOR UPDATE;
```

现在，工作程序将执行作业，在本例中是发送一封电子邮件。一旦完成，该作业就会被删除。

```sql
DELETE FROM jobs WHERE id = 1;
```

最后，提交该事务。

```sql
COMMIT;
```

对于当个工作者来说这可以很好的工作。但是，如果有多个工作者呢？

```sql
-- 在两个连接中同时执行以下语句
BEGIN;
SELECT * FROM jobs LIMIT 1 FOR UPDATE;
```

第二个工作者在试图读取被锁定的行时 hung 住了。只有在第一个工作者完成之后，第二个工作者才能开始。

```sql
-- 在第一个连接中执行下面的语句
DELETE FROM jobs WHERE id = 2;
COMMIT;
```

在这种行级锁的模式下，我们的工作者被串行序列化了，多个工作者就变得毫无意义。

```sql
-- 在第二个连接中执行下面的语句
DELETE FROM jobs WHERE id = 3;
COMMIT;
```

PostgreSQL 9.5 版本中的 `skip locked` 特性就是用于解决这个问题的。它故意绕过 PostgreSQL 提供的事务之间的隔离，跳过其它事务锁定的行。

我们再来试试这个。

```sql
-- 在两个连接中同时执行下面的语句
BEGIN;
SELECT * FROM jobs LIMIT 1 FOR UPDATE SKIP LOCKED;
```

两个连接都能够选择和锁定不同的行。现在我们可以让多个工作者同时从一个作业队列中取作业执行了。

第一个工作者获取的作业。

```
 id |                         payload
----+---------------------------------------------------------
  4 | {"type": "send_welcome_email", "to": "sam@example.com"}
(1 row)
```

第二个工作者获取的作业。

```
 id |                          payload
----+-----------------------------------------------------------
  5 | {"type": "send_password_reset", "to": "bill@example.com"}
(1 row)
```

## 延伸

除了 `SKIP LOCKED` 之外，我们也可以使用 `NOWAIT` 来达到类似的功能，有所不同的是，`NOWAIT` 在无法立即获取需要锁定的行时将会报错；而 `SKIP LOCKED` 将跳过任何无法获取锁的行。跳过锁定的行提供了不一致的数据视图，因此这不适用于通用工作，但可用于避免多个消费者访问类似队列的表时的锁争用。请注意，`NOWAIT` 和 `SKIP LOCKED` 仅适用于行级锁——所需的 `ROW SHARE` 表级锁仍以普通方式获取。

## 译者注

本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第七集 [The Skip Locked feature in Postgres 9.5](https://www.pgcasts.com/episodes/the-skip-locked-feature-in-postgres-9-5)。

## 参考

[1] https://www.postgresql.org/docs/current/sql-select.html

<div class="just-for-fun">
笑林广记 - 不愿富

一鬼托生时，冥王判作富人。
鬼曰：“不愿富也，但求一生衣食不缺，无是无非，烧清香，吃苦茶，安闲过日足矣。”
冥王曰：“要银子便再与你几万，这样安闲清福，却不许你享。”
</div>
