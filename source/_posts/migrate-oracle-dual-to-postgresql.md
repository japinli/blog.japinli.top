---
title: "Oracle 迁移 PostgreSQL - DUAL 表"
date: 2021-09-23 21:28:28 +0800
categories: 数据库
tags:
  - Oracle
  - PostgreSQL
  - 迁移
---

Oracle 迁移到 PostgreSQL 中最常见的问题就是 `DUAL` 表的问题。在 Oracle 数据库中，每个查询都必须跟随一个 `FROM` 子句，这是强制性的。然而在 PostgreSQL 数据库中，`FROM` 子句是可选的。本文记录了如何将 Oracle 中的 `DUAL` 表迁移到 PostgreSQL 数据库中。

<!--more-->

## Oracle `DUAL` 表

Oracle 中的 `DUAL` 表包含一行一列数据，如下所示：

```sql
SQL> select * from dual;

D
-
X
```

## 迁移解决方案

针对 Oracle 中 `DUAL` 表的迁移，我们有两种解决方案。

1. 第一种是直接将 Oracle 中的 `FROM DUAL` 子句移除。这是最简单的迁移方式。
2. 第二种是通过创建一个视图来模拟 `DUAL` 表。这种情况通常用于不能更改应用程序的情况。
   ```sql
   CREATE VIEW public.dual AS SELECT 'X'::varchar AS D;
   REVOKE ALL ON public.dual FROM PUBLIC;
   GRANT SELECT, REFERENCES ON public.dual TO PUBLIC;
   ```

## 参考

[1] https://wiki.postgresql.org/wiki/Oracle_to_Postgres_Conversion
[2] https://github.com/orafce/orafce

<div class="just-for-fun">
笑林广记 - 避暑

官值暑月，欲觅避凉之地。同僚纷议。
或曰：“某山幽雅。”
或曰：“某寺清闲。”
一老人进曰：“山寺虽好，总不如此座公厅，最是凉快。”
官曰：“何以见得？”
答曰：“别处多有日头，独此处有天无日。”
</div>
