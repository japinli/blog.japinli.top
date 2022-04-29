---
title: "PostgreSQL 中的 Lateral Joins"
date: 2022-04-29 20:29:51 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
  - PG Casts
---

在本期的 PG Casts 中，我们将使用 Lateral Joins 来更有效的聚合列。准备好了吗？让我们开始吧。

<!--more-->

假设我们有一张 `developers` 表。

```sql
\d developers
```
```
              Table "public.developers"
  Column  |  Type   | Collation | Nullable | Default
----------+---------+-----------+----------+---------
 id       | integer |           | not null |
 username | text    |           | not null |
Indexes:
    "developers_pkey" PRIMARY KEY, btree (id)
Referenced by:
    TABLE "activities" CONSTRAINT "activities_developer_id_fkey" FOREIGN KEY (developer_id) REFERENCES developers(id)
```

每一位开发者都有一个 `id`（主键）和 `username`。我们还有一个开发人员活动表。

```sql
\d activities
```
```
                               Table "public.activities"
    Column    |  Type   | Collation | Nullable |                Default
--------------+---------+-----------+----------+----------------------------------------
 id           | integer |           | not null | nextval('activities_id_seq'::regclass)
 developer_id | integer |           | not null |
 event_type   | text    |           | not null |
Indexes:
    "activities_pkey" PRIMARY KEY, btree (id)
Foreign-key constraints:
    "activities_developer_id_fkey" FOREIGN KEY (developer_id) REFERENCES developers(id)
    "activities_event_type_fkey" FOREIGN KEY (event_type) REFERENCES event_types(name)
```

在这里查看它的结构和一些虚拟数据，我们将看到每个活动同时引用一个开发人员和一个事件类型。

```sql
TABLE activities;
```
```
 id | developer_id | event_type
----+--------------+------------
  1 |            7 | pull
  2 |            8 | push
  3 |            8 | push
  4 |            9 | pull
[...]
 47 |            2 | fork
 48 |            6 | fork
 49 |            8 | pull
 50 |            1 | push
(50 rows)
```

所有的开发者都会很快意识到这是一个可以在 Github 上执行的操作的简短列表。您可以在下面的演示示例中找到关于我如何设置数据的详细信息，但现在，我们将深入剖析它们。

假设对于每个开发人员，您需要一个大小不超过 5 的活动事件类型数组。正如你所料，一个简单的连接，再加上一个 `GROUP BY` 和一个 `array_agg` 便可以达到我们的目的，让我们来看看。

```sql
SELECT
  d.id,
  array_agg(da.event_type) activities
FROM
  developers d
    JOIN (
	  SELECT event_type, developer_id
	  FROM activities) da ON d.id = da.developer_id
GROUP BY d.id
ORDER BY d.id;
```
```
 id |                     activities
----+-----------------------------------------------------
  1 | {pull,fork,push,fork,fork,pull,pull,push}
  2 | {push,pull,push,fork,fork,push,pull,fork,push,fork}
  3 | {fork,push,push,pull}
  4 | {fork,fork,fork,push}
  5 | {fork,push,push}
  6 | {fork}
  7 | {fork,pull,fork,pull}
  8 | {push,fork,pull,push,fork,pull,push,pull,pull}
  9 | {push,fork,pull,pull,pull,pull,pull}
(9 rows)
```

这是一个良好的开始，但正如我们所说，我们希望获取最多有五个活动的开发人员。那我们该怎么做呢？

现在，您可能认为可以在 `JOIN` 子查询中给出一个 `LIMIT 5` 子句，到此为止，然后给自己倒一杯柠檬水。但您错了！

让我们看看如果您尝试一下会发生什么。

```sql
SELECT
  d.id,
  array_agg(da.event_type) activities
FROM
  developers d
    JOIN (
      SELECT event_type, developer_id
	  FROM activities
	  LIMIT 5) da ON d.id = da.developer_id
GROUP BY d.id
ORDER BY d.id;
```
```
 id | activities
----+-------------
  3 | {push}
  7 | {pull}
  8 | {push,push}
  9 | {pull}
(4 rows)
```

您注意到可疑的东西了吗？您的 PostgreSQL 感受到了吗？应该是的。如果您仔细观察，您会注意到一些事情。首先，我们没有得到第一次查询中返回活动数组的所有开发人员。其次，在返回的开发人员中，我们没有达到预期的活动数量。

导致这种情况的原因是 `LIMIT` 字句。当 PostgreSQL 迭代每个开发人员时，它*只*查询*所有*活动中的前 5 个，并且*仅*当开发人员的 `id` 恰好与这 5 个活动中的一个活动的 `developer_id` 匹配时，才返回一行。

我们真正希望 PostgreSQL 做的不是限制所有的活动，而是限制那些活动的 `developer_id` 与当前开发人员 `id` 相同的活动。例如，如果我们只关心一个开发人员，我们可以像如下所示在 `JOIN` 子查询中添加一个 `WHERE` 条件：

```sql
SELECT
  d.id,
  array_agg(da.event_type) activities
FROM
  developers d
    JOIN (
      SELECT event_type, developer_id
	  FROM activities
	  WHERE developer_id = 1
      LIMIT 5) da on d.id = da.developer_id
GROUP BY d.id
ORDER BY d.id;
```
```
 id |         activities
----+----------------------------
  1 | {pull,fork,pull,push,pull}
(1 row)
```

对于一个开发人员来说，就是这样，但是我们现在只有一条记录。我们如何为每个开发人员做到这一点呢？

也许我们可以将 `WHERE` 语句中的 `developer_id = 1` 修改为 `developer_id = d.id`。让我们看看这会发生什么。

```sql
SELECT
  d.id,
  array_agg(da.event_type) activities
FROM developers d
  JOIN (
    SELECT event_type, developer_id
	FROM activities
	WHERE developer_id = d.id
	LIMIT 5) da ON d.id = da.developer_id
GROUP BY d.id
ORDER BY d.id;
```
```
ERROR:  invalid reference to FROM-clause entry for table "d"
LINE 8:     WHERE developer_id = d.id
                                 ^
HINT:  There is an entry for table "d", but it cannot be referenced from this part of the query.
```

嗯...它并不能工作。PostgreSQL 抱怨说在子查询中无法访问 `d` 别名。

这就是 `LATERAL` 关键字的用武之地了。看看我们将其放在子查询 `JOIN` 的右边会发生什么。

```sql
SELECT
  d.id,
  to_json(array_agg(da.event_type)) activities
FROM developers d
  JOIN LATERAL (
    SELECT event_type, developer_id
    FROM activities
    WHERE developer_id = d.id
    LIMIT 5) da ON d.id = da.developer_id
GROUP BY d.id
ORDER BY d.id;
```
```
 id |              activities
----+--------------------------------------
  1 | ["pull","fork","pull","push","pull"]
  2 | ["push","push","fork","pull","fork"]
  3 | ["push","push","pull","fork"]
  4 | ["push","fork","fork","fork"]
  5 | ["push","push","fork"]
  6 | ["fork"]
  7 | ["pull","fork","fork","pull"]
  8 | ["push","push","pull","pull","pull"]
  9 | ["pull","pull","fork","pull","pull"]
(9 rows)
```

耶！！我们得到我们想要的了。我们看到了所有有活动的开发人员列表，并且得到了最多有 5 个活动的开发人员！等等，这其中发生了什么呢？

事实证明，`LATERAL` 关键字使我们能够访问前面 `FROM` 中提供的列，在本例中，它是当前开发人员。在尝试连接两个表之前，我们获取开发人员的 `id` 并使用它来限制活动。

还有其他一些聪明的方法可以在不使用 `LATERAL` 关键字的情况下实现这一点。它们可能会使用常见的表表达式（Table Expressions）或窗口函数（Window Functions），但我们将在本集中不介绍它们。如果你能使用这些工具达到同样的效果，请联系我们，我们可能会在未来的一集中介绍。

## 演示示例

```sql
-- Create developers table
CREATE TABLE developers (
  id integer primary key,
  username text not null
);

-- Generate developers
INSERT INTO developers (id, username)
  SELECT dev_id, 'dev' || dev_id
  FROM generate_series(1, 10) as dev_id;

-- Create event_types table
CREATE TABLE event_types (
  name text primary key
);

-- Generate event types
INSERT INTO event_types (name)
  VALUES ('push'), ('pull'), ('fork');

-- Create developer activities table
CREATE TABLE activities (
  id serial primary key,
  developer_id integer not null references developers(id),
  event_type text not null references event_types(name)
);

-- Generate developer activities
WITH RECURSIVE random_activities (row_num, developer_id, event_type) AS (
  (
    SELECT 1, d.id, et.name
    FROM developers d
      CROSS JOIN event_types et
    ORDER BY random() limit 1
  )
  UNION (
    SELECT row_num+1, d.id, et.name
    FROM random_activities
      CROSS JOIN developers d
      CROSS JOIN event_types et
    WHERE row_num < 50
    ORDER BY random() limit 1
  )
)
INSERT INTO activities (developer_id, event_type)
  SELECT random_activities.developer_id,
         random_activities.event_type
  FROM random_activities;
```

## 译者著

本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第六集 [Generating JSON from SQL](https://www.pgcasts.com/episodes/lateral-joins)。

<div class="just-for-fun">
笑林广记 - 吃乳饼

富翁与人论及童子多肖乳母，为吃其乳，气相感也。
其人谓富翁曰：“若是如此，想来足下从幼是吃乳饼长大的。”
</div>
