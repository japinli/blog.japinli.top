---
title: "PostgreSQL 大对象"
date: 2020-04-04 12:30:04 +0800
category: 数据库
tags:
  - PostgreSQL
---

我们知道在 Oracle 数据库中，大对象有三种类型，分别是 CLOB，BLOB 和 BFILE。在 Oracle 数据库中大对象最大存储根据配置可以达到 8TB 到 128TB。然而在 PostgreSQL 数据库中并没有提供这三种数据类型。因此在进行迁移的时候，我们需要做类型的映射。在参考文献 [2] 中提到可以将 CLOB 和 BLOB 分别映射到 text 和 bytea 数据类型上。此外，PostgreSQL 的插件 pg_largeobject 也提供了一种大对象的支持。本文简要介绍这两种大对象的使用。

<!-- more -->

## text & bytea

CLOB 和 BLOB 分别用于存储字符大对象和二进制大对象，这与 PostgreSQL 中的 text 和 bytea 很类似，因此在迁移 Oracle 数据库的时候也就将他们分别对应起来。在 PostgreSQL 源码（c.h）中我们可以看到如下的定义：

``` c
struct varlena
{
    char        vl_len_[4];     /* Do not touch this field directly! */
    char        vl_dat[FLEXIBLE_ARRAY_MEMBER];  /* Data content is here */
};

#define VARHDRSZ        ((int32) sizeof(int32))

/*
 * These widely-used datatypes are just a varlena header and the data bytes.
 * There is no terminating null or anything like that --- the data length is
 * always VARSIZE_ANY_EXHDR(ptr).
 */
typedef struct varlena bytea;
typedef struct varlena text;
```

从上面的定义，我们可以发现，text 和 bytea 的定义都是 varlena 类型，即变长数据类型，所不同的是，text 用于存储可打印字符，而 bytea 用于存储二进制字符，这与 Oracle 的 CLOB 和 BLOB 是一致的。
varlena 类型在 PostgreSQL 的存储可能触发 [TOAST 机制](https://www.postgresql.org/docs/12/storage-toast.html)，而采用 TOAST 机制存储的数据最大支持 1GB 的存储空间，因此这导致其存储空间和 Oracle 中的大对象不一致。

此外，Oracle 中的大对象支持随机读写，但是采用 text 和 bytea 类型的大对象对随机读写的支持不是很好，对于随机读可以使用如下的方式进行替代：

``` plpgsql
postgres=# select name, substring(name from 1 for 2) from people ;
 name | substring
------+-----------
 Jon  | Jo
 Jane | Ja
(2 rows)
```

然而，对于随机写貌似没有很好的替代方案。

## pg_largeobject

pg_largeobject 是 PostgreSQL 插件提供的一个大对象解决方案。在 pg_largeobject 中，所有的大对象都存储在系统表 `pg_largeobject` 中；此外，每个大对象在系统表 `pg_largeobject_metadata` 中也会有一条记录大对象的相关元信息，他们的定义如下所示：

```
postgres=# \d pg_largeobject
         Table "pg_catalog.pg_largeobject"
 Column |  Type   | Collation | Nullable | Default
--------+---------+-----------+----------+---------
 loid   | oid     |           | not null |
 pageno | integer |           | not null |
 data   | bytea   |           | not null |
Indexes:
    "pg_largeobject_loid_pn_index" UNIQUE, btree (loid, pageno)

postgres=# \d pg_largeobject_metadata
      Table "pg_catalog.pg_largeobject_metadata"
  Column  |   Type    | Collation | Nullable | Default
----------+-----------+-----------+----------+---------
 oid      | oid       |           | not null |
 lomowner | oid       |           | not null |
 lomacl   | aclitem[] |           |          |
Indexes:
    "pg_largeobject_metadata_oid_index" UNIQUE, btree (oid)
```

采用 pg_largeobject 所存储的大对象最大可以达到 4TB 的存储空间，并且__支持随机读写__。pg_largeobject 采用 OID 的方式来引用 `pg_largeobject` 表中的大对象。例如，我们创建一个表来存储图片数据，如下所示：

``` plpgsql
CREATE TABLE image(name text, raster oid);
```

pg_largeobject 提供了一系列函数用于创建、导入和导出大对象，见官方文档[服务端函数](https://www.postgresql.org/docs/12/lo-funcs.html)。下图是简单的大对象插入导出的测试输出：

{% asset_img lo-test.jpg Large Object Test %}

需要注意的是，在使用 pg_largeobject 来管理大对象时，我们需要额外的操作来管理大对象。例如，上面的示例中，如果我们想要删除表 `image` 中名称为 `image1` 的记录，我们还需在 `pg_largeobject` 中删除 `loid = 24598` 的记录。如下图所示：

{% asset_image lo-delete.jpg Large Object Deletion Test %}

通常，我们会创建一个触发器来进行 OID 的删除。此外，pg_largeobject 提供了 lo_put 和 lo_get 函数来随机读写大对象。需要注意的是，我们在使用 libpq 对大对象进行读写时必须在事务中。

## 总结

通过上面的说明，我们可以发现在 PostgreSQL 中的大对象处理各自存在优缺点：

|          | text & bytea | pg_largeobject |
|----------|--------------|----------------|
| 随机读   | YES          | YES            |
| 随机写   | NO           | YES            |
| 存储限制 | 1GB          | 4TB            |
| 需要事务 | NO           | YES            |
| 跟踪 OID | NO           | YES            |

## 参考

[1] https://docs.oracle.com/cd/B28359_01/appdev.111/b28393/adlob_intro.htm#ADLOB001
[2] https://wiki.postgresql.org/wiki/Oracle_to_Postgres_Conversion
[3] https://wiki.postgresql.org/wiki/Largeobject_Enhancement
[4] https://www.postgresql.org/docs/12/largeobjects.html
