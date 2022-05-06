---
title: "【译】PostgreSQL 视图介绍"
date: 2022-05-06 20:22:42 +0800
categories: 数据库
tags:
  - PostgreSQL
  - PG Casts
  - 翻译
---

在这一集中，我们将了解 PostgreSQL 数据库视图、它们是什么以及您可能使用它们的原因。

<!--more-->

当前我们的数据库中有 `employees` 和 `cities` 两个表：

```sql
TABLE employees;
```
```
    hometown    | first_name | last_name |                                 title
----------------+------------+-----------+------------------------------------------------------------------------
 White Haven    | Liz        | Lemon     | Head Writer
 Stone Mountain | Kenneth    | Parcell   | Page
 Sadchester     | Jack       | Donaghy   | Vice President of East Coast Television and Microwave Oven Programming
(3 rows)
```

```sql
TABLE cities;
```
```
      name      | state
----------------+-------
 White Haven    | PA
 Stone Mountain | GA
 Sadchester     | MA
(3 rows)
```

`employees` 表和 `cities` 表分别有 3 条记录。随着时间的推移，我们已经改进了一个查询，以一种有用的方式连接这些表。假设它可以帮助 CEO 记住每个人的家乡：

```sql
SELECT
  (first_name || ' ' || last_name) as full_name,
  title,
  hometown,
  state
FROM
  employees, cities
WHERE
  hometown = name;
```
```
    full_name    |                                 title                                  |    hometown    | state
-----------------+------------------------------------------------------------------------+----------------+-------
 Liz Lemon       | Head Writer                                                            | White Haven    | PA
 Kenneth Parcell | Page                                                                   | Stone Mountain | GA
 Jack Donaghy    | Vice President of East Coast Television and Microwave Oven Programming | Sadchester     | MA
(3 rows)
```

我们在这里做了几件事；将名字和姓氏连接成一个“全名”字符串，从 `employees` 表中获取一些数据，并从 `cities` 表中获取状态。所有这些都是为了制作一份有用的报告。

我们在代码中重复这个查询几次，我们喜欢 SQL 的 CEO 每天在 psql 中输入几次。如果我们能给它一个名字，那就太好了。

现在是时候讨论数据库的视图了。

视图为查询提供了一个友好的名称，让我们可以像引用任何表一样引用它。这真的很容易：

```sql
CREATE VIEW employee_hometowns AS
  SELECT
    (first_name || ' ' || last_name) as full_name,
    title,
    hometown,
    state
  FROM
    employees, cities
  WHERE
    hometown = name;
```

现在我们的大查询已简化为以下内容：

```sql
SELECT * FROM employee_hometowns;
```
```
    full_name    |                                 title                                  |    hometown    | state
-----------------+------------------------------------------------------------------------+----------------+-------
 Liz Lemon       | Head Writer                                                            | White Haven    | PA
 Kenneth Parcell | Page                                                                   | Stone Mountain | GA
 Jack Donaghy    | Vice President of East Coast Television and Microwave Oven Programming | Sadchester     | MA
(3 rows)
```

如果它不是真正的表，那么 `TABLE` 关键字是否还有效呢？

```sql
TABLE employee_hometowns;
```
```
    full_name    |                                 title                                  |    hometown    | state
-----------------+------------------------------------------------------------------------+----------------+-------
 Liz Lemon       | Head Writer                                                            | White Haven    | PA
 Kenneth Parcell | Page                                                                   | Stone Mountain | GA
 Jack Donaghy    | Vice President of East Coast Television and Microwave Oven Programming | Sadchester     | MA
(3 rows)
```

事实上，任何可以在表上工作的查询都可以在这个视图上工作：

```sql
SELECT state FROM employee_hometowns;
```
```
 state
-------
 PA
 GA
 MA
(3 rows)
```

正如 PostgreSQL 文档中所指出的，视图是一种数据库精心设计的、有用的抽象。它们将表的逻辑封装在一个简单的界面后面，减少重复并使每个人的生活更轻松。

这就是概述；最后，我想展示一些生产代码。

我们运营的网站之一，[Today I Learned](https://til.hashrocket.com/statistics)，有一个统计页面；该页面的一部分是“最热门帖子”图表，它使用 Reddit 风格的算法来计算不可知的热度质量。

这是它 SQL：

```sql
WITH posts_with_age AS (
  SELECT
    *,
    greatest(extract(epoch from (current_timestamp - published_at)) / 3600, 0.1) AS hour_age
  FROM
    posts
  WHERE
    published_at is not null)
SELECT
  (likes / hour_age ^ 0.8) as score,
  *
FROM
  posts_with_age
ORDER BY
  1 desc;
```

此代码是视图的绝佳候选者。它足够复杂；这是我们需要一次又一次地使用的东西；有趣的是，我们希望通过 psql 访问它。

幸运的是，这段代码的作者 Josh Davey 同意了，并将其分配给一个名为 `hot_posts` 的视图。让我们看看它的实际效果：

```sql
SELECT title FROM hot_posts LIMIT 5;
```

您有了符合条件的热度标题。

视图很强大。我们可以从视图中生成视图。我们可以与 ActiveRecord 集成。我们可以物化我们的视图，它将视图的结果存储在数据库中。所有这些主题都值得在未来的一集中进行更详细的探索。

## 演示示例

```sql
-- create employees table
CREATE TABLE employees (
  hometown varchar(80),
  first_name varchar,
  last_name varchar,
  title varchar
);

-- create cities table
CREATE TABLE cities (
  name varchar(80),
  state varchar(2)
);

-- populate data
INSERT INTO employees VALUES
  ('White Haven', 'Liz', 'Lemon', 'Head Writer'),
  ('Stone Mountain', 'Kenneth', 'Parcell', 'Page'),
  ('Sadchester', 'Jack', 'Donaghy', 'Vice President of East Coast Television and Microwave Oven Programming');

INSERT INTO cities VALUES
  ('White Haven', 'PA'),
  ('Stone Mountain', 'GA'),
  ('Sadchester', 'MA');
```
## 译者著

本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第十二集 [Intro to Views](https://www.pgcasts.com/episodes/intro-to-views)。


<div class="just-for-fun">
笑林广记 - 训子

富翁子不识字，人劝以延师训子。
先学一字是一画，次二字是二画，次三字三画。
其子便欣然投笔告父曰：“儿已都晓字义，何用师为？”
父喜之乃谢去。
一日父欲招万姓者饮，命子晨起治状，至午不见写成。
父往询之，子恚曰：“姓亦多矣，如何偏姓万，自早至今才得五百画哩！”
</div>
