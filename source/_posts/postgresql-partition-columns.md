---
title: "PostgreSQL 获取分区键信息"
date: 2023-03-06 22:18:21 +0800
categories: 数据库
tags:
  - PostgreSQL
---

PostgreSQL 从版本 10 开始便支持了声明式分区表，本文简要介绍如何获取分区表的分区键信息。

<!--more-->

## 示例

首先，我们先创建一个分区表示例。

```sql
CREATE TABLE log(log_time timestamp, info text) PARTITION BY RANGE (log_time);
CREATE TABLE log_2023 PARTITION OF log FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
```

## psql 方式查询分区键

我们可以通过 psql 提供的 `\d` 命令就可以看到分区键信息。

```
postgres=# \d log
                     Partitioned table "public.log"
  Column  |            Type             | Collation | Nullable | Default
----------+-----------------------------+-----------+----------+---------
 log_time | timestamp without time zone |           |          |
 info     | text                        |           |          |
Partition key: RANGE (log_time)
Number of partitions: 1 (Use \d+ to list them.)
```

从上面的 `Partitoin key` 我们可以得知表 `log` 的分区键为 `log_time`。

## SQL 方式查询分区键

有时我们可能需要通过 SQL 的方式查询表的分区键，这个时候就需要用到 `pg_get_partkeydef()` 函数了，如下所示，我们可以通过表的 OID 来获取分区键信息。

```sql
postgres=# SELECT pg_get_partkeydef('log'::regclass);
 pg_get_partkeydef
-------------------
 RANGE (log_time)
(1 row)
```

本质上，psql 的 `\d` 命令也是通过调用该函数获取的分区键信息，我们可以在 psql 中设置 `ECHO_HIDDEN` 来查看。

```
postgres=# \set ECHO_HIDDEN on
postgres=# \d log
[...]

********* QUERY **********
SELECT pg_catalog.pg_get_partkeydef('16404'::pg_catalog.oid);
**************************

[...]

                     Partitioned table "public.log"
  Column  |            Type             | Collation | Nullable | Default
----------+-----------------------------+-----------+----------+---------
 log_time | timestamp without time zone |           |          |
 info     | text                        |           |          |
Partition key: RANGE (log_time)
Number of partitions: 1 (Use \d+ to list them.)
```

## 分析

通过上面的内容，我们知道了 PostgreSQL 是通过 `pg_get_partkeydef()` 函数获取的分区键信息，那么这个分区键信息是存储在哪儿的呢？查看 `pg_get_partkeydef()` 函数的定义我们可以得知它是通过查询表 `pg_partitioned_table` 获取的信息。

```c
Datum
pg_get_partkeydef(PG_FUNCTION_ARGS)
{
    Oid         relid = PG_GETARG_OID(0);
    char       *res;

    res = pg_get_partkeydef_worker(relid, PRETTYFLAG_INDENT, false, true);

    if (res == NULL)
        PG_RETURN_NULL();

    PG_RETURN_TEXT_P(string_to_text(res));
}

static char *
pg_get_partkeydef_worker(Oid relid, int prettyFlags,
                         bool attrsOnly, bool missing_ok)
{
    Form_pg_partitioned_table form;
    HeapTuple   tuple;
    oidvector  *partclass;
    oidvector  *partcollation;
    List       *partexprs;
    ListCell   *partexpr_item;
    List       *context;
    Datum       datum;
    bool        isnull;
    StringInfoData buf;
    int         keyno;
    char       *str;
    char       *sep;

    /* 这里的 PARTRELID 对应的便是 pg_partitioned_table 的缓存 */
    tuple = SearchSysCache1(PARTRELID, ObjectIdGetDatum(relid));
    if (!HeapTupleIsValid(tuple))
    {
        if (missing_ok)
            return NULL;
        elog(ERROR, "cache lookup failed for partition key of %u", relid);
    }

    [...]
}
```

我可以在 `src/backend/utils/cache/syscache.c` 中找到。

```c
static const struct cachedesc cacheinfo[] = {
    [...]
    [PARTRELID] = {
        PartitionedRelationId,  /* 表 pg_partitioned_table 的 OID */
        PartitionedRelidIndexId,
        KEY(Anum_pg_partitioned_table_partrelid),
        32
    },
	[...]
}
```

关于 `pg_partitioned_table` 表的详细说明可以参考[官方文档](https://www.postgresql.org/docs/15/catalog-pg-partitioned-table.html)。

* `partrelid` - 分区表的 OID。
* `partstrat` - 分区策略；`h` - 哈希分区，`l` - 列表分区；`r` 范围分区。
* `partnatts` - 分区键的数量。
* `partdefid` - 默认分区表的 OID，如果没有则为 0。
* `partattrs` - 分区键的编号数组，如果表达式那么为 0。
* `partclass` - 每个分区键的操作符 OID（`pg_opclass`）。
* `partcollation` - 对于分区键中的每一列，这包含用于分区的排序规则的 OID，如果该列不是可排序的数据类型，则为 0。
* `partexprs` - 不是简单列引用的分区键的表达式树。这是一个列表，`partattrs` 中的每个零条目都有一个元素。如果所有分区键都是简单引用，则为空。

## 参考

[1] https://www.postgresql.org/docs/15/catalog-pg-partitioned-table.html

<div class="just-for-fun">
笑林广记 - 鼻影作枣

近视者拜客。主人留坐待茶。茶果吃完。
视茶内鼻影。以为橄榄也。捞摸不已，久之忿极，辄用指撮起，尽力一咬，指破血出。
近视乃仔细认之，曰：“啐，我只道是橄榄，却原来是一个红枣。”
</div>
