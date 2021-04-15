---
title: "Oracle wm_concat 函数说明"
date: 2021-03-07 15:13:35 +0800
category: 数据库
tags:
  - PostgreSQL
  - Oracle
---

Oracle 数据库的 `wm_concat` 函数用于将多行数据聚合为单行，从而提供与特定值关联的数据列表，它将以逗号来分割列表。
本文主要介绍 `wm_concat` 函数的功能以及其在 PostgreSQL 数据库中的替换方法。

<!-- more -->

## 测试用例

本文将使用下面的测试用例来测试 `wm_concat` 函数以及其替代方法。

```SQL
CREATE TABLE tbl (col1 int, col2 VARCHAR(20));
INSERT INTO tbl VALUES (1, 'Hello');
INSERT INTO tbl VALUES (1, 'world');
INSERT INTO tbl VALUES (1, 'this');
INSERT INTO tbl VALUES (1, 'is');
INSERT INTO tbl VALUES (1, 'a');
INSERT INTO tbl VALUES (1, 'test');
INSERT INTO tbl VALUES (2, 'wm_concat test');
```

## Oracle

在 Oracle 数据库中 `wm_concat` 没有相关的文档记录的，其输出如下所示。

```SQL

SQL> SELECT col1, wm_concat(col2) FROM tbl GROUP BY (col1);

      COL1 WM_CONCAT(COL2)
---------- --------------------------------------------------------------------------------
         1 Hello,test,a,is,this,world
         2 wm_concat test

```

由于 `wm_concat` 没有相关的文档记录，因此不建议使用该函数。其次，在 Oracle 12c 中 `wm_concat` 已经被移除了。更好的写法是通过 `listagg` 函数对其进行替换。

```SQL
SQL> SELECT col1, listagg(col2, ',') WITHIN GROUP (ORDER BY col2) AS agg FROM tbl GROUP BY col1;

      COL1 AGG
---------- --------------------------------------------------------------------------------
         1 Hello,test,a,is,this,world
         2 wm_concat test

```

## PostgreSQL

当我们将其迁移到 PostgreSQL 时，我们可以使用 `string_agg` 函数来替换 Oracle 中的 `wm_concat` 和 `listagg` 函数。

```
postgres=# SELECT col1, string_agg(col2, ',') FROM tbl GROUP BY col1;
 col1 |         string_agg
------+----------------------------
    2 | wm_concat test
    1 | Hello,world,this,is,a,test
(2 rows)

postgres# SELECT col1, string_agg(col2, ',' ORDER BY col2) FROM tbl GROUP BY col1;
 col1 |         string_agg
------+----------------------------
    1 | a,Hello,is,test,this,world
    2 | wm_concat test
(2 rows)
```

默认情况下，`wm_concat` 函数是根据其聚合的列进行排序的，但是其排序的结果和 PostgreSQL 中不太一样，目前尚不清楚具体原因。

## 参考

[1] http://psoug.org/definition/WM_CONCAT.htm
[1] https://asktom.oracle.com/pls/apex/f?p=100:11:::NO:RP:P11_QUESTION_ID:9529613900346315631
