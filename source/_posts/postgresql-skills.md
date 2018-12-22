---
title: "PostgreSQL 常用命令集合"
date: 2018-12-04 22:30:42 +0800
category: Database
tags: PostgreSQL
---

本文主要收集日常工作中经常使用的 PostgreSQL 相关的命令；其中，主要包含相关的系统函数、使用技巧等。本文将持续更新！！！

<!-- more -->

### 常用函数

1. 查看数据库大小

   ``` psql
   SELECT pg_database_size('table_name');
   ```

2. 查看数据表大小

    ``` psql
    SELECT pg_relation_size('table_name');
    ```
3. 查看数据表大小

    ``` psql
    SELECT pg_table_size('table_name');
    ```

    __注意：__ `pg_relation_size` 与 `pg_table_size` 的区别在于 `pg_table_size` 将获取数据表的 TOAST 表、空闲空间映射表 (FSM) 和可见性表 (但不包括索引表) 的大小；而 `pg_relation_size` 可以跟一个 fork 类型的参数 (可取的值为 main, fsm, vm, init) 来获取关系表的部分数据大小，默认为 main 类型，此外 `pg_relation_size` 也可以用于获取索引表的大小。

4. 获取数据表大小 (包括索引和 TOAST 表)

    ``` psql
    SELECT pg_total_relation_size('table_name');
    ```

5. 将数据转为易于人们阅读的格式

    ``` psql
    SELECT pg_size_pretty(pg_relation_size('table_name'));
    ```

6. 查看对应的表空间的路径

    ``` psql
    SELECT pg_tablespace_location(oid);
    ```

    其中，`oid` 为表空间的对象 ID。我们可以通过 `SELECT oid FROM pg_tablespace;` 来查询获得。

### 参考

[1] https://www.postgresql.org/docs/current/functions-admin.html
