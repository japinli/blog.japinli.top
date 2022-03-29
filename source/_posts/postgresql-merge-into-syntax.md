---
title: "PostgreSQL 15 特性 - MERGE INTO 语法"
date: 2022-03-29 20:39:52
categories: 数据库
tags:
  - PostgreSQL
  - PG15
---

`MERGE INTO` 语法很早之前就在 Oracle 数据库中实现了，最近 PostgreSQL 也实现了相应的语法，该语法符合 SQL2016 标准，与 Oracle 的 `MERGE INTO` 还是有一定区别的。本文简要介绍一下 PostgreSQL 中的 `MERGE INTO` 语法。

<!--more-->

## 语法

PostgreSQL 提供的 [`MERGER INTO` 语法](https://www.postgresql.org/docs/devel/sql-merge.html)如下所示。

```
[ WITH with_query [, ...] ]
MERGE INTO target_table_name [ [ AS ] target_alias ]
USING data_source ON join_condition
when_clause [...]
```

`data_source` 可以是表、视图或子查询，如下所示。

```
{ source_table_name | ( source_query ) } [ [ AS ] source_alias ]
```

`when_clause` 子句用于给出具体的执行动作。当匹配上时，可以执行 `UPDATE` 和 `DELETE` 操作；当未匹配上时，则可以执行 `INSERT` 操作。

```
{ WHEN MATCHED [ AND condition ] THEN { merge_update | merge_delete | DO NOTHING } |
  WHEN NOT MATCHED [ AND condition ] THEN { merge_insert | DO NOTHING } }
```

`merge_insert`、`merge_update` 和 `merge_delete` 的语法如下所示：

```
INSERT [( column_name [, ...] )]
[ OVERRIDING { SYSTEM | USER } VALUE ]
{ VALUES ( { expression | DEFAULT } [, ...] ) | DEFAULT VALUES }

UPDATE SET { column_name = { expression | DEFAULT } |
             ( column_name [, ...] ) = ( { expression | DEFAULT } [, ...] ) } [, ...]

DELETE
```

对比 Oracle 的 [`MERGE INTO`](https://docs.oracle.com/database/121/SQLRF/statements_9017.htm) 语法，还是可以发现它们存在很大的差异。

Oracle 中的 `merge_insert_clause`、`merge_delete_clause` 和 `merge_update_clause` 中是可以携带 `WHERE` 子句的，然而在 PostgreSQL 中则是将其放置在 `when_clause` 子句中了。

PostgreSQL 中的 `MERGE INTO` 执行步骤如下所示：

1. 无论 `WHEN` 子句匹配与否，为所有的操作执行 `BEFORE STATEMENT` 触发器。
2. 执行从源表到目标表的连接。生成的查询将正常优化并生成一组候选的更改行。对于每个候选更改行，执行下面的步骤：
   a. 评估每一行是 `MATCHED` 还是 `NOT MATCHED`。
   b. 按指定的顺序测试每个 `WHEN` 条件，直到返回 `true`。
   c. 当条件返回 true 时，执行以下操作：
      - 执行操作的事件类型触发的 `BEFORE ROW` 触发器。
      - 执行指定的操作，对目标表调用任何检查约束。
	  - 执行操作的事件类型触发的 `AFTER ROW` 触发器。
3. 为指定的操作执行 `AFTER STATEMENT` 触发器，无论它们是否实际发生。这类似于不修改任何行的 `UPDATE` 语句的行为。

## 示例

首先，我们创建 `target` 和 `source` 表，并向 `target` 表中插入三条记录，向 `source` 表插入一条记录，如下所示。

```sql
CREATE TABLE target (tid integer, balance integer);
CREATE TABLE source (sid integer, delta integer);
INSERT INTO target VALUES (1, 10);
INSERT INTO target VALUES (2, 20);
INSERT INTO target VALUES (3, 30);
INSERT INTO source VALUES (4, 40);
```

我们先来测试一下 `MATCHED ... UPDATE` 功能。

```sql
MERGE INTO target t
USING source AS s
ON t.tid = s.sid
WHEN MATCHED THEN
        UPDATE SET balance = 0;
```

```
MERGE 0
```

可以看到没有任何记录发生变化，符合预期。

接下来，我们测试一下 `NOT MATCHED ... INSERT` 功能。

```sql
MERGE INTO target t
USING source AS s
ON t.tid = s.sid
WHEN NOT MATCHED THEN
        INSERT VALUES (4, 45);
```

```
MERGE 1
```

查看 `target` 表，如下所示。

```sql
SELECT * FROM target;
```

```
 tid | balance
-----+---------
   1 |      10
   2 |      20
   3 |      30
   4 |      45
(4 rows)
```

这说明 `tid = 4` 的记录未匹配上，并正确插入到了 `target` 表中。

最后，我们来综合测试一下。

```
INSERT INTO source VALUES (5, 50), (2, 20);
MERGE INTO target t
USING source AS s
ON t.tid = s.sid
WHEN MATCHED AND s.sid < 3 THEN
    UPDATE SET balance = t.balance * 10
WHEN MATCHED THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT VALUES (s.sid, s.delta);
```

```
MERGE 3
```

可以看到有三条记录发生了变化。我们期望的是当匹配的时候，如果 `s.sid < 3` 时，那么就将 `target` 表中的 `balance` 扩大 10 倍，否则就删除它；当未匹配的时候就插入 `source` 表中的记录到 `target` 表中。

`source` 表的内容如下所示。

```
 sid | delta
-----+-------
   4 |    40
   5 |    50
   2 |    20
(3 rows)
```

因此，执行上述的 `MERGE INTO` 语句之后，`target` 表中 `tid = 4` 的记录应该被删除，`tid = 2` 的记录 `balance` 扩大 10 倍，而未匹配的 `5, 50` 则会插入到 `target` 表中。

```sql
SELECT * FROM target;
```

```
 tid | balance
-----+---------
   1 |      10
   3 |      30
   2 |     200
   5 |      50
(4 rows)
```

结果与预期一致。

需要注意的是，PostgreSQL 中的 `MERGE INTO` 语法没有提供特殊的权限管理，它依赖于底层 `INSERT`、`UPDATE` 和 `DELETE` 操作的权限控制。

## 参考

[1] https://www.postgresql.org/docs/devel/sql-merge.html
[2] https://docs.oracle.com/database/121/SQLRF/statements_9017.htm

<div class="just-for-fun">
笑林广记 - 斋戒库

一监生姓齐，家资甚富，但不识字。
一日府尊出票，取鸡二只，兔一只。
皂亦不识字，央齐监生看。
生曰：“讨鸡二只，免一只。”
皂只买一鸡回话。太守怒曰：“票上取鸡二只，兔一只，为何只缴一鸡？”
皂以监生事禀。太守遂拘监生来问，时太守适有公干，暂将监生收入斋戒库内候究。
生入库，见碑上斋戒二字，认做他父亲齐成姓名，张目惊诧呜咽不止。
人问何故，答曰：“先人灵座，何人设建在此，睹物伤情，焉得不哭。”
</div>
