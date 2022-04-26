---
title: "【译】PostgreSQL 数据库中的注释"
date: 2022-04-26 20:12:25 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
  - PG Casts
---

注释存储了数据库对象的相关信息。这就好比是代码中的注释，可以谨慎的使用注释向未来的开发人员传达意图。SQL 标准没有对注释作出规范，所以尽情享受使用 PostgreSQL 的另一优势！

<!--more-->

首先，我们创建一张表来作演示：

```sql
-- create cmbr table
CREATE TABLE cmbr (
  id SERIAL PRIMARY KEY,
  name VARCHAR
);
```

您可能会问 `cmbr` 是什么？它是这个数据库帮助管理电视节目的演员信息表。由于这是一个遗留数据库，它的名称不够直观，且被过个租户使用。在本练习中，我们假设无法重命名该表。但是，我们可以为它添加注释。

```sql
-- add comment
COMMENT ON TABLE cmbr IS 'Cast members of The Girly Show';
```

我们可以使用下面的命令来查看注释信息。

```
-- show table with comment
\dt+ cmbr
```

```
                                             List of relations
 Schema | Name | Type  | Owner | Persistence | Access method |    Size    |          Description
--------+------+-------+-------+-------------+---------------+------------+--------------------------------
 public | cmbr | table | japin | permanent   | heap          | 8192 bytes | Cast members of The Girly Show
(1 row)
```

这个命令告诉 psql 显示带有磁盘大小和描述的表相关信息。我们可以在 PostgreSQL 中对几乎所有的对象进行注释，包括表、列和模式。在我编写这个文章的时候 PostgreSQL 可以对 36 个数据库对象进行注释。

每个对象仅允许包含一条注释，因此要修改注释，您只需要向同一对象再次注释一次即可。

```sql
-- replace comment
COMMENT ON TABLE cmbr IS 'Cast members of TGS with Tracy Jordan';
```

```
\dt+ cmdr
```

```
                                                List of relations
 Schema | Name | Type  | Owner | Persistence | Access method |    Size    |              Description
--------+------+-------+-------+-------------+---------------+------------+---------------------------------------
 public | cmbr | table | japin | permanent   | heap          | 8192 bytes | Cast members of TGS with Tracy Jordan
(1 row)
```

如果您想要删除注释，只需要将注释文本替换为 `NULL` 即可。此外，删除注释的对象时，注释将自动删除。

```sql
-- remove comment
COMMENT ON TABLE cmbr IS NULL;
```

```
\dt+ cmdr
```

```
                                   List of relations
 Schema | Name | Type  | Owner | Persistence | Access method |    Size    | Description
--------+------+-------+-------+-------------+---------------+------------+-------------
 public | cmbr | table | japin | permanent   | heap          | 8192 bytes |
(1 row)
```

我最近在一次数据迁移中使用了这种技术。我们希望保留一个遗留表作为 `hstore` 列，但也要明确新列不是要写入的。该注释使我们能够将这些信息传达给未来的开发者。

我们在 Hashrocket 上尽量避免使用注释，因为注释可能会偏离它们所属的代码或数据对象。在使用此功能时，请结合实际情况进行判断。

## 参考

[1] https://www.postgresql.org/docs/current/sql-comment.html

## 译者著

本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第三集 [Comments](https://www.pgcasts.com/episodes/comments)。

<div class="just-for-fun">
笑林广记 - 借牛

有走柬借牛于富翁者，翁方对客，讳不识字，伪启缄视之，对来使曰：“知道了，少刻我自来也。”
</div>
