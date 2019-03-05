---
title: "PostgreSQL 常用命令集合"
date: 2018-12-04 22:30:42 +0800
category: Database
tags: PostgreSQL
---

本文主要收集日常工作中经常使用的 PostgreSQL 相关的命令；其中，主要包含相关的系统函数、使用技巧等。本文将持续更新！！！

__备注：__ 主要基于 PostgreSQL 10 及其后续版本。

<!-- more -->

### 常用函数

- 查看数据库大小

   ``` psql
   SELECT pg_database_size('table_name');
   ```

- 查看数据表大小

    ``` psql
    SELECT pg_relation_size('table_name');
    ```
- 查看数据表大小

    ``` psql
    SELECT pg_table_size('table_name');
    ```

    __注意：__ `pg_relation_size` 与 `pg_table_size` 的区别在于 `pg_table_size` 将获取数据表的 TOAST 表、空闲空间映射表 (FSM) 和可见性表 (但不包括索引表) 的大小；而 `pg_relation_size` 可以跟一个 fork 类型的参数 (可取的值为 main, fsm, vm, init) 来获取关系表的部分数据大小，默认为 main 类型，此外 `pg_relation_size` 也可以用于获取索引表的大小。

- 获取数据表大小 (包括索引和 TOAST 表)

    ``` psql
    SELECT pg_total_relation_size('table_name');
    ```

- 将数据转为易于人们阅读的格式

    ``` psql
    SELECT pg_size_pretty(pg_relation_size('table_name'));
    ```

- 查看对应的表空间的路径

    ``` psql
    SELECT pg_tablespace_location(oid);
    ```

    其中，`oid` 为表空间的对象 ID。我们可以通过 `SELECT oid FROM pg_tablespace;` 来查询获得。

- 查看表对应的文件路径

    ``` psql
    SELECT pg_relation_filepath(oid);
    ```
- 获取当前事务 ID 编号

    ```psql
    SELECT txid_current();
    ```

- 获取当前 WAL 日志的写入位置

    ``` psql
    SELECT pg_current_wal_lsn();          -- version 10 or later
    SELECT pg_current_xlog_location();    -- before version 10
    ```

- 获取当前 WAL 日志的插入位置

    ``` psql
    SELECT pg_current_wal_insert_lsn();          -- version 10 or later
    SELECT pg_current_xlog_insert_location();    -- before version 10
    ```

- 获取日志所在的 WAL 日志文件

    ```psql
    SELECT pg_walfile_name(lsn);     -- version 10 or later
    SELECT pg_xlogfile_name(lsn);    -- before version 10
    ```

### 常用参数

- `max_wal_size (integer)`

    该参数指定 WAL 日志做 CHECKPOINT 时的最大的 WAL 日志大小。该参数不是强制性的限制，在某些特殊情况下可能会超过该值，例如 `archive_command` 命令失败或者过高的 `wal_keep_segments`。若该参数设置过高会影响系统崩溃时的恢复时间。

- `min_wal_size (integer)`

    主要 WAL 日志的磁盘使用率低于此设置，那么旧的 WAL 日志文件将被回收用于后续的 CHECKPOINT 使用。它可以确保有足够的磁盘空间来存放 WAL 日志记录。

- `checkpoint_completion_target (floating point)`

    该参数指定 CHECKPOINT 完成的目标，作为 CHECKPOINT 之间的总时间的一部分。该参数可以用于缓解两个 CHECKPOINT 之间的 I/O 负载。

### psql 使用

- 查看 `\d` 以及其他反斜杠命令对应的 SQL 语句

  ```
  $ psql -E
  -----------------------------
  postgres=# \set ECHO_HIDDEN on
  ```


### 参考

[1] https://www.postgresql.org/docs/current/functions-admin.html
[2] https://www.postgresql.org/docs/current/app-psql.html
