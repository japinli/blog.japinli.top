---
title: "PostgreSQL 临时表"
date: 2019-08-07 22:04:14 +0800
category: 数据库
tags:
  - PostgreSQL
---

本文主要介绍 PostgreSQL 数据库中的临时表 (Temporary Table)。临时表将在会话结束或者当前事务结束时被删除。PostgreSQL 支持临时表和永久存储表 (Permanent Table) 具有相同的名称，如果出现这种情况，那么只有在临时表被删除之后才能看到永久表或者你可以指定 schema 来明确需要查询的是永久表。此外，在临时表上建立的索引同样也是临时的。

<!-- more -->

## 创建临时表

在 PostgreSQL 中，我们可以通过下面的语法来创建临时表：

``` psql
CREATE TEMPORARY TABLE temp_table_name (
    ...
);
```

或者，我们可以将 `TEMPORARY` 替换为 `TEMP`

``` psql
CREATE TEMP TABLE temp_table_name (
    ...
);
```

所有的临时表只能在他所在的会话中可见。我们来看一个示列，首先创建一个 `test` 的数据库，随后在里面创建一个 `temp_test` 的临时表。

``` psql
postgres=# CREATE DATABASE test;
CREATE DATABASE
postgres=# \c test
You are now connected to database "test" as user "japin".
test=# CREATE TEMP TABLE temp_test (id INT, name VARCHAR(10), age INT);
CREATE TABLE
test=# SELECT * FROM temp_test;
 id | name | age
----+------+-----
(0 rows)

test=#
```

接着，我们重新开启一个会话连接到到 `test` 数据库并查询 `temp_test` 临时表中的数据。

``` psql
postgres=# \c test
You are now connected to database "test" as user "japin".
test=# SELECT * FROM temp_test;
ERROR:  relation "temp_test" does not exist
LINE 1: SELECT * FROM temp_test;
                      ^
test=#
```
正如你看到的，第二个会话中没有 `temp_test` 这个关系表，因此可以说明临时表只在当前会话可见。现在我们尝试断开第一个会话连接并重新连接到 `test` 数据库查看一下该临时表是否还存在。

``` psql
test=# \q
japin@ww-it:~/Codes/tinydb$ psql -d test
psql (10.4)
Type "help" for help.

test=# SELECT * FROM temp_test;
ERROR:  relation "temp_test" does not exist
LINE 1: SELECT * FROM temp_test;
                      ^
test=#
```

从上面可以看到临时表 `temp_test` 以及不存在了，这说明它在会话结束之后就被数据库回收了。

## 临时表表名

PostgreSQL 支持临时表与永久表具有相同的表名，虽然通常不推荐这样做，但是难免出现抽风的情况 :(。如果数据库中包含相同名字的临时表和永久表，那么执行查询时将会在临时表中取数据而不是在永久表中取数据。当然，我们通过指定 schema 来显示的指明从永久表中取数据。考虑如下情况：

首先，我们在 `test` 数据库中创建一个 `customers` 的永久表:

``` psql
test=# CREATE TABLE customers (id INT, name VARCHAR(10), age INT);
CREATE TABLE
test=# INSERT INTO customers VALUES (1, 'japin', 20), (2, 'tom', 20);
INSERT 0 2
test=# SELECT * FROM customers;
 id | name  | age
----+-------+-----
  1 | japin |  20
  2 | tom   |  20
(2 rows)

test=#
```

接着，我们在创建一个相同名字的临时表：

``` psql
test=# CREATE TEMP TABLE customers (id INT, name VARCHAR(10), age INT);
CREATE TABLE
test=# SELECT * FROM customers;
 id | name | age
----+------+-----
(0 rows)

test=#
```

此时，我们在从 `customers` 表中查询时便没有数据记录了，这说明临时表 `customers` 将永久表 `customers` 覆盖了。我们通过 `\d+` 命令查看数据库中的关系表，它同样不包含永久表 `customers` 的信息，其内容如下：

``` psql
test=# \d+
                       List of relations
  Schema   |   Name    | Type  | Owner |  Size   | Description
-----------+-----------+-------+-------+---------+-------------
 pg_temp_3 | customers | table | japin | 0 bytes |
(1 row)

test=#
```

由上述结果可知，临时表是存放在 `pg_temp_3` 的 sechma 中，而我们创建的永久表则是存放在 `public` schema 中，因此，我们可以通过指定 schema 来查看永久表 `customers` 中的内容：

``` psql
test=# SELECT * FROM public.customers;
 id | name  | age
----+-------+-----
  1 | japin |  20
  2 | tom   |  20
(2 rows)

test=#
```

## 删除临时表

临时表的删除与永久表没有区别，它们都是通过 `DROP TABLE` 语句实现的。例如，我们要删除 `customers` 临时表可以使用如下的命令：

``` psql
DROP TABLE customers;
```

此时，我们便可以看到永久表 `customers` 了。

``` psql
test=# \d+
                       List of relations
 Schema |   Name    | Type  | Owner |    Size    | Description
--------+-----------+-------+-------+------------+-------------
 public | customers | table | japin | 8192 bytes |
(1 row)

test=#
```

## 参考

[1] https://www.postgresql.org/docs/10/sql-createtable.html
[2] http://www.postgresqltutorial.com/postgresql-temporary-table/
