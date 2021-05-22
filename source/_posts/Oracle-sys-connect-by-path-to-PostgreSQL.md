---
title: "Oracle sys_connect_by_path 函数迁移到 PostgreSQL 数据库"
date: 2021-05-21 16:29:27 +0800
category: 数据库
tags:
  - Oracle
  - PostgreSQL
---

本文简要记录一下如何将 Oracle 数据库中的 `sys_connect_by_path()` 函数迁移到 PostgreSQL 数据库中。

函数 `sys_connect_by_path()` 通常是与 Oracle 中的 `connect by` 子句一起使用的，而 `connect by` 子句转换到 PostgreSQL 中时通常是使用 `WITH RECUSIVE` 来实现。



## 最小示例

为了演示，本文提供了一个最小可执行示例。Oracle 中的示例表如下所示。

```sql
CREATE TABLE tbl(id int, pid int, path varchar(100));
INSERT INTO tbl VALUES (1, 0, 'home');
INSERT INTO tbl VALUES (2, 1, 'ubuntu');
INSERT INTO tbl VALUES (3, 2, 'codes');
INSERT INTO tbl VALUES (4, 1, 'centos');
INSERT INTO tbl VALUES (5, 4, 'videos');
```

由于 PostgreSQL 与 Oracle 数据类型有所不同，这里需要对表结构进行简单的修改，如下所示。

```sql
CREATE TABLE tbl(id int, pid int, path text);
INSERT INTO tbl VALUES (1, 0, 'home');
INSERT INTO tbl VALUES (2, 1, 'ubuntu');
INSERT INTO tbl VALUES (3, 2, 'codes');
INSERT INTO tbl VALUES (4, 1, 'centos');
INSERT INTO tbl VALUES (5, 4, 'videos');
```

## Oracle sys_connect_by_path 示例

函数 `sys_connect_by_path` 仅在分层查询中有效。它返回从根到节点的列值的路径，对于 `CONNECT BY` 条件返回的每一行，列值用指定分隔符进行分隔。

```sql
SELECT
  id,
  pid,
  path,
  sys_connect_by_path(path, '/') AS full_path
FROM
  tbl t
START WITH
  t.pid = 0
CONNECT BY
  PRIOR t.id = t.pid;
 ID | PID |  PATH  |     FULL_PATH
----+-----+--------+---------------------
 1  |  0  | home   | /home
 2  |  1  | ubuntu | /home/ubuntu
 3  |  2  | codes  | /home/ubuntu/codes
 4  |  1  | centos | /home/centos
 5  |  4  | videos | /home/centos/videos
```

## PostgreSQL 迁移 sys_connect_by_path

下面我们使用递归 CTE 来实现 Oracle 中的 `sys_connect_by_path` 函数的功能。

```sql
WITH RECURSIVE cte AS (
  SELECT
    id,
    pid,
    path,
    '/' || path AS full_path
  FROM
    tbl
  WHERE
    pid = 0   -- START WITH
  UNION ALL
  SELECT
    t.id,
    t.pid,
    t.path,
    cte.full_path || '/' || t.path AS full_path
  FROM
    tbl t JOIN cte
      ON cte.id = t.pid -- CONNECT BY
)
SELECT * FROM cte;
 id | pid |  path  |      full_path
----+-----+--------+---------------------
  1 |   0 | home   | /home
  2 |   1 | ubuntu | /home/ubuntu
  4 |   1 | centos | /home/centos
  3 |   2 | codes  | /home/ubuntu/codes
  5 |   4 | videos | /home/centos/videos
(5 rows)
```

这里需要注意，我们需要在开始的时候在需要连接的字段前加上分隔符，这样才能与 Oracle 保持一致。

## 参考

[1] https://docs.oracle.com/cd/B19306_01/server.102/b14200/functions164.htm


<div class="just-for-fun">
笑林广记 - 应先备酒

妻好吃酒，屡索夫不与，叱之曰：“开门七件事：柴、米、油、盐、酱、醋、茶，何曾见个酒字？”
妻曰：“酒是不曾开门就要用的，须是隔夜先买，如何放得在开门里面？”
</div>
