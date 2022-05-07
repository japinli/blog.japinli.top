---
title: "PostgreSQL TOAST 索引读取失败"
date: 2021-12-29 22:19:14 +0800
categories: 数据库
tags:
  - PostgreSQL
---

最近，应用开发报来一个问题，错误信息如下：

```
ERROR:  could not read block 0 in file "base/16385/2294016": read only 0 of 8192 bytes
CONTEXT:  SQL function "obj_description" during startup
```

这个错误信息和之前遇到的 {% post_link postgresql-hash-index PostgreSQL HASH 索引拾遗%}一文的情况很像。但是这里的数据库是 10.4，且是单节点模式，因此排除 HASH 索引的问题。

<!--more-->

## 分析

首先，我们需要确定 `2294016` 这个文件是对应的数据库对象：

```sql
postgres=# SELECT oid, relname, relkind FROM pg_class WHERE relfilenode = 2294016;
 oid  |       relname       | relkind
------+---------------------+---------
 2841 | pg_toast_2619_index | i
(1 row)
```

从上面的结果我们可以推测出 `2294016` 是索引 `pg_toast_2619_index` 的物理存储文件，而该索引是 TOAST 表的索引，并且这个 TOAST 表对应的基表的 OID 为 2619。

```sql
postgres=# SELECT
postgres-#     a.oid     AS table_oid,
postgres-#     a.relname AS table_name,
postgres-#     b.relname AS toast_name,
postgres-#     c.relname AS index_name
postgres-# FROM
postgres-#     pg_class c
postgres-#         LEFT JOIN pg_index i ON c.oid = i.indexrelid
postgres-#         LEFT JOIN pg_class b ON i.indrelid = b.oid
postgres-#         LEFT JOIN pg_class a ON b.oid = a.reltoastrelid
postgres-# WHERE
postgres-#     c.relfilenode = 2841;
 table_oid |  table_name  |  toast_name   |     index_name
-----------+--------------+---------------+---------------------
      2619 | pg_statistic | pg_toast_2619 | pg_toast_2619_index
(1 row)

```

既然是索引问题，那么是否能通过重建索引来解决这个问题呢？

```sql
postgres=# REINDEX INDEX pg_toast_2619_index;
ERROR:  relation "pg_toast_2619_index" does not exist
```

索引不存在？这是我忽略了 schema，事后才想起 TOAST 相关的数据存储在 `pg_toast` schema 下面。实际中，由于数据库本身数据有可能被损坏了，我选择了对 `pg_statistic` 整个表重建索引。

```sql
postgres=# REINDEX TABLE pg_statistic;
ERROR:  could not create unique index "pg_statistic_relid_att_inh_index"
DETAIL:  Key (starelid, staattnum, stainherit)=(16558, 9, f) is duplicated.
```

这里在去查询 OID 为 `16558` 的表时，发现其已经不存在，因此这里将其删除掉。

```sql
postgres=# DELETE FROM pg_catalog.pg_statistic WHERE starelid = 16558 AND staattnum = 9 AND stainherit = false;
DELETE 2
```

至此，已经可以正常访问用户数据了。当然，这里的用户数据也可能存在一些损坏。


<div class="just-for-fun">
笑林广记 - 及第

一举子往京赴试，仆挑行李随后。
行到旷野，忽狂风大作，将担上头巾吹下。
仆大叫曰：“落地了。”
主人心下不悦，嘱曰：“今后莫说落地，只说及第。”
仆颔之。
将行李拴好，曰：“如今恁你走上天去，再也不会及第了。”
</div>
