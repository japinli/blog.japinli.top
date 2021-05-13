---
title: "PostgreSQL 类型转换时无效的类型输入"
date: 2021-05-12 18:35:21
category: 数据库
tags:
  - PostgreSQL
---

最近在做 Oracle 迁移的时候发现一个类型错误，如下所示：

```
ERROR:  invalid input syntax for type numeric: "null"
```

这个问题其实很简单，就是原始数据里面包含 `'null'` 的字符串导致的。解决这个问题的办法就是将数据中为 `'null'` 的异常数据转换为正常数据。

<!-- more -->

## 问题

这个问题是我们想要将 `varchar` 类型的字段转为 `numeric` 类型时出现的。原始数据有大约 60w 行记录，其中大部分都是可以之间通过 `cast` 转换为 `numeric` 类型的。通过下面的查询我们可以看到有 4 条记录存储了 `null` 字符串。

```
SELECT id, total_year FROM contract_export WHERE total_year !~ '[0-9.]+';
        id        | total_year
------------------+------------
 PG202006173J2995 | null
 PG202007074K5842 | null
 PG202005181L4194 | null
 PG202005186D1908 | null
(4 rows)
```

## 解决方案

既然是数据异常，那么我们就要想法将异常数据转换为正常数据，这个可能就需要根据业务来确定异常的数据该如何进行转换。不过可以确定的是，我们可以通过 `CASE WHEN` 语句来处理异常数据。那么如果异常的数据过多怎么办？我们是否需要提供很多的 `WHEN` 分支呢？

这里我们就需要查看异常数据是否有共性？如果有共性，那么我们可以通过正则表达式将其刷选出来。如果异常数据没有共性呢？那么我们是否可以方向思考呢？通过正常数据的共性来匹配正常数据，从而达到刷选异常数据的目的。

这个问题的解决方法其实在上面的 SQL 查询中已经给出了，我们可以使用下面的语句来进行处理。

```sql
SELECT
  id,
  (CASE
     WHEN total_year LIKE '%null%' THEN '0'
     ELSE total_year
   END)::numeric
FROM
  contract_export;

SELECT
  id,
  (CASE
     WHEN total_year !~ '[0-9.]+' THEN total_year
	 ELSE '0'
   END)::numeric
FROM
  contract_export;
```

为了防止其出现 `NULL` 值导致类型转换失败，我们可以使用 `COALESCE` 来处理 `NULL` 值。


<div class="just-for-fun">
笑林广记 - 狗父

陆某，善说话，有邻妇性不好笑，
其友谓之曰：“汝能说一字令彼妇笑，又说一字令彼妇骂，则吾愿以酒菜享汝。”
一日，妇立门前，适门前卧一犬，陆向之长跪曰：“爷！”
妇见之不觉好笑，陆复仰首向妇曰：“娘！”
妇闻之大骂。
</div>
