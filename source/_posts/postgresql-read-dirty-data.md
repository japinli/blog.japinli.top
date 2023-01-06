---
title: "PostgreSQL 扩展 - pg_dirtyread 读取未回收数据"
date: 2023-01-06 21:13:59 +0800
categories: 数据库
tags:
  - PostgreSQL
---

pg_dirtyread 扩展提供了从 PostgreSQL 数据库中读取未回收的数据的能力。它支持 PostgreSQL 9.2 及更高版本（在 9.2 上，至少需要 9.2.9）。

<!--more-->

## 编译安装

pg_dirtyread 编译需要使用到 pg_config 来获取 PostgreSQL 编译连接信息，使用下面的命令即可完成编译安装。

```bash
$ make
$ make install
```

如果您的 pg_config 不在 `PATH` 环境变量中，可以使用下面的命令编译安装。

```bash
$ make PG_CONFIG=/path/to/pg_config
$ make install PG_CONFIG=/path/to/pg_config
```

## 使用

当安装 pg_dirtyread 插件之后，我们需要在数据库中导入该插件方可使用，使用超级用户执行下面的 SQL 即可完成。

```sql
CREATE EXTENSION pg_dirtyread;
```

pg_dirtyread 的使用方法如下所示：

```sql
SELECT * FROM pg_dirtyread('tablename') AS t(col1 type1, col2 type2, ...);
```

`pg_dirtyread()` 函数返回的是 `RECORD` 类型，因此有必要附加一个描述表模式的表别名子句。列按名称匹配，因此可以在别名中省略某些列，或重新排列列。

## 示例

我们使用下面的 SQL 创建一个表，同时禁用该表上的 autovacuum 操作。

```sql
CREATE TABLE foo (bar bigint, baz text)
  WITH (autovacuum_enabled = false, toast.autovacuum_enabled = false);
```

接着在表中插入数据，随后在删除部分数据。

```sql
INSERT INTO foo SELECT id, md5(id::text) FROM generate_series(1, 10) id;
DELETE FROM foo WHERE bar % 3 = 0;
```

接下来，我们使用 pg_dirtyread 插件来读取已经删除的数据，先导入 pg_dirtyread 插件。

```sql
CREATE EXTENSION pg_dirtyread;
```

接着使用 `pg_dirtyread()` 函数读取数据。

```sql
SELECT * FROM pg_dirtyread('foo') AS t(bar bigint, baz text);
```
```text
 bar |               baz
-----+----------------------------------
   1 | c4ca4238a0b923820dcc509a6f75849b
   2 | c81e728d9d4c2f636f067f89cc14862c
   3 | eccbc87e4b5ce2fe28308fd9f2a7baf3
   4 | a87ff679a2f3e71d9181a67b7542122c
   5 | e4da3b7fbbce2345d7772b0674a318d5
   6 | 1679091c5a880faf6fb5e6087eb1b2dc
   7 | 8f14e45fceea167a5a36dedd4bea2543
   8 | c9f0f895fb98ab9159f51fd0297e236d
   9 | 45c48cce2e2d7fbdea1afc51c7c6ad26
  10 | d3d9446802a44259755d38e6d163e820
(10 rows)
```

pg_dirtyread 也支持系统列（如 `ctid`、`xmax` 等）的读取，除了 PostgreSQL 提供的系统列，pg_dirtyread 还提供了一个 `dead` 系统列，他用于标识该元组是否被删除。

```sql
SELECT * FROM pg_dirtyread('foo')
  AS t(tableoid oid, ctid tid, xmin xid, xmax xid, cmin cid, dead boolean, bar bigint, baz text);
```
```text
 tableoid |  ctid  | xmin | xmax | cmin | dead | bar |               baz
----------+--------+------+------+------+------+-----+----------------------------------
    16406 | (0,1)  |  761 |    0 |    0 | f    |   1 | c4ca4238a0b923820dcc509a6f75849b
    16406 | (0,2)  |  761 |    0 |    0 | f    |   2 | c81e728d9d4c2f636f067f89cc14862c
    16406 | (0,3)  |  761 |  762 |    0 | t    |   3 | eccbc87e4b5ce2fe28308fd9f2a7baf3
    16406 | (0,4)  |  761 |    0 |    0 | f    |   4 | a87ff679a2f3e71d9181a67b7542122c
    16406 | (0,5)  |  761 |    0 |    0 | f    |   5 | e4da3b7fbbce2345d7772b0674a318d5
    16406 | (0,6)  |  761 |  762 |    0 | t    |   6 | 1679091c5a880faf6fb5e6087eb1b2dc
    16406 | (0,7)  |  761 |    0 |    0 | f    |   7 | 8f14e45fceea167a5a36dedd4bea2543
    16406 | (0,8)  |  761 |    0 |    0 | f    |   8 | c9f0f895fb98ab9159f51fd0297e236d
    16406 | (0,9)  |  761 |  762 |    0 | t    |   9 | 45c48cce2e2d7fbdea1afc51c7c6ad26
    16406 | (0,10) |  761 |    0 |    0 | f    |  10 | d3d9446802a44259755d38e6d163e820
(10 rows)
```

__备注：__ 在 16devel 中，如果删除了立即去查询可能会发现已经被删除的元组其 `dead` 为 `f` 的情况。这是由于 `GlobalVisDataRels` 没有更新导致的，如果我们在 `foo` 上执行一个查询，结果就正确的。

如果表没有被重写（如 `VACUUM FULL` 和 `CLUSTER`），那么我们还可以读取已删除的列的数据。我们使用 `dropped_N` 访问第 `N` 列，它从 1 开始计数。PostgreSQL 删除了原始列的类型信息，因此如果在表别名中指定了正确的类型，则只能进行少量完整性检查；检查的是类型长度、类型对齐、类型修饰符和按值传递。

首先，我们删除 `baz` 列，随后再删除部分数据。

```sql
ALTER TABLE foo DROP COLUMN baz;
DELETE FROM foo WHERE bar % 4 = 0;
```

接着通过 `pg_dirtyread()` 函数来读取被删除的列数据。

```sql
SELECT * FROM pg_dirtyread('foo')
  AS t(tableoid oid, ctid tid, xmin xid, xmax xid, cmin cid, dead boolean, bar bigint, dropped_2 text);
```
```text
 tableoid |  ctid  | xmin | xmax | cmin | dead | bar |            dropped_2
----------+--------+------+------+------+------+-----+----------------------------------
    16406 | (0,1)  |  761 |    0 |    0 | f    |   1 | c4ca4238a0b923820dcc509a6f75849b
    16406 | (0,2)  |  761 |    0 |    0 | f    |   2 | c81e728d9d4c2f636f067f89cc14862c
    16406 | (0,3)  |  761 |  762 |    0 | t    |   3 | eccbc87e4b5ce2fe28308fd9f2a7baf3
    16406 | (0,4)  |  761 |  765 |    0 | t    |   4 | a87ff679a2f3e71d9181a67b7542122c
    16406 | (0,5)  |  761 |    0 |    0 | f    |   5 | e4da3b7fbbce2345d7772b0674a318d5
    16406 | (0,6)  |  761 |  762 |    0 | t    |   6 | 1679091c5a880faf6fb5e6087eb1b2dc
    16406 | (0,7)  |  761 |    0 |    0 | f    |   7 | 8f14e45fceea167a5a36dedd4bea2543
    16406 | (0,8)  |  761 |  765 |    0 | t    |   8 | c9f0f895fb98ab9159f51fd0297e236d
    16406 | (0,9)  |  761 |  762 |    0 | t    |   9 | 45c48cce2e2d7fbdea1afc51c7c6ad26
    16406 | (0,10) |  761 |    0 |    0 | f    |  10 | d3d9446802a44259755d38e6d163e820
(10 rows)
```

pg_dirtyread 插件可以帮助我们获取到被误删的数据，不过必须具有以下前提：

* 数据是通过 `DELETE` 方式删除的，`TRUNCATE` 或者 `DROP` 这种方式删除的数据无法通过 pg_dirtyread 读取。
* `DELETE` 删除的数据没有进行 `VACUUM` 回收。
* 如果表被重写，则无法通过 pg_dirtyread 获取已删除列的数据。

## 参考

[1] https://github.com/df7cb/pg_dirtyread

<div class="just-for-fun">
笑林广记 - 呵欠

一耳聋人探友。犬见之吠声不绝。其人茫然不觉。入见主人。
揖毕告曰：“府上尊犬，想是昨夜不曾睡来。”
主人问：“何以见得？”
答曰：“见了小弟，只是打呵欠。”
</div>
