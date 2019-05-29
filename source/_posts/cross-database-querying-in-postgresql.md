---
title: PostgreSQL 数据库跨库查询
date: 2019-05-09 22:55:54 +0800
category: Database
tags:
  - PostgreSQL
  - dblink
---

PostgreSQL 数据库默认情况下是不支持跨数据库访问的。如果我们想要执行跨数据库的查询，我们需要借助 dblink 来实现，dblink 是 PostgreSQL 的一个模块，支持从数据库会话中连接到其他数据库。

<!-- more -->

## 安装 dblink

通过 `CREATE EXTENSION dblink;` 即可安装 dblink。

```
postgres=# CREATE EXTENSION dblink;
CREATE EXTENSION
```
dblink 提供了一系列函数用于访问远端数据库，具体的可以参看 [PostgreSQL dblink][] 文档。

## 本地跨库访问

为了演示本地跨库访问，我们首先在 `postgres` 中建立 `userinfo` 表，随后在本地新建一个 `localdb` 数据库，并在其中建立一个 `local_test` 数据表。

```
postgres=# CREATE TABLE userinfo (id int primary key, name text);
CREATE TABLE
postgres=# INSERT INTO userinfo VALUES (1, 'Eric'), (2, 'Tom');
INSERT 0 2
postgres=# SELECT * FROM userinfo;
 id | name
----+------
  1 | Eric
  2 | Tom
(2 rows)

postgres=# CREATE DATABASE localdb;
CREATE DATABASE
postgres=# \c localdb
You are now connected to database "localdb" as user "japin".
localdb=# CREATE TABLE local_test (id serial primary key, ival int default 0, create_time timestamptz not null default now());
CREATE TABLE
localdb=# INSERT INTO local_test(ival) VALUES (1), (2), (3), (4);
INSERT 0 4
localdb=# SELECT * FROM local_test;
 id | ival |          create_time
----+------+-------------------------------
  1 |    1 | 2019-05-09 15:03:44.701121+08
  2 |    2 | 2019-05-09 15:03:44.701121+08
  3 |    3 | 2019-05-09 15:03:44.701121+08
  4 |    4 | 2019-05-09 15:03:44.701121+08
(4 rows)

```

此时，如果我想在 `postgres` 数据库中查询 `local_test` 表，就需要使用到 dblink 来访问了。首先，我们通过 `dblink_connect` 创建一个连接。

```
postgres=# SELECT dblink_connect('local_dblink_test', 'dbname=localdb');
 dblink_connect
----------------
 OK
(1 row)

```

随后，我们就可以通过 dblink 执行查询了。

```
postgres=# SELECT * FROM dblink('local_dblink_test', 'SELECT * FROM local_test;') AS lt(id int, ival int, create_time timestamptz);
 id | ival |          create_time
----+------+-------------------------------
  1 |    1 | 2019-05-09 15:03:44.701121+08
  2 |    2 | 2019-05-09 15:03:44.701121+08
  3 |    3 | 2019-05-09 15:03:44.701121+08
  4 |    4 | 2019-05-09 15:03:44.701121+08
(4 rows)

```

当然，我们也可以将返回结果与本库中的表进行联合查询。

```
postgres=# SELECT u.id, name, create_time FROM userinfo u JOIN dblink('local_dblink_test', 'SELECT * FROM local_test;') AS lt(id int, ival int, create_time timestamptz) on u.id = lt.id;
 id | name |          create_time
----+------+-------------------------------
  1 | Eric | 2019-05-09 15:03:44.701121+08
  2 | Tom  | 2019-05-09 15:03:44.701121+08
(2 rows)

```

为了方便，我们可以为 `dblink` 的执行创建一个视图。

```
postgres=# CREATE VIEW v_localdb_test AS SELECT * FROM dblink('local_dblink_test', 'SELECT * FROM local_test;') AS lt(id int, ival int, create_time timestamptz);
CREATE VIEW
postgres=# SELECT * FROM v_localdb_test ;
 id | ival |          create_time
----+------+-------------------------------
  1 |    1 | 2019-05-09 15:03:44.701121+08
  2 |    2 | 2019-05-09 15:03:44.701121+08
  3 |    3 | 2019-05-09 15:03:44.701121+08
  4 |    4 | 2019-05-09 15:03:44.701121+08
(4 rows)

postgres=# SELECT u.id, name, create_time FROM userinfo u JOIN v_localdb_test v ON u.id = v.id;
 id | name |          create_time
----+------+-------------------------------
  1 | Eric | 2019-05-09 15:03:44.701121+08
  2 | Tom  | 2019-05-09 15:03:44.701121+08
(2 rows)

```

__备注：__ 在 `local_test` 表中 `id` 字段类型为 `serial`，但是在通过 `dblink` 查询时返回的结果类型不能使用 `serial` 类型。


## 远端跨库访问

上面我们介绍了 PostgreSQL 如何在本地进行跨库访问，其实远端跨库访问本质也是类似的，只不过在配置 `dblink_connect` 连接参数时需要指明远端数据库的地址、端口、用户名和密码等信息。

我们在远端创建一个 `remotedb` 数据库，并在该数据库中创建一个 `remote_test` 表。

```
postgres=# create database remotedb;
CREATE DATABASE
postgres=# \c remotedb
remotedb=# CREATE TABLE remote_test (id serial primary key, ival int not null default 0, create_time timestamptz default now());
CREATE TABLE
remotedb=# INSERT INTO remote_test(ival) values (1),(2),(3),(4),(5);
INSERT 0 5
remotedb=# SELECT * FROM remote_test;
 id | ival |          create_time
----+------+-------------------------------
  1 |    1 | 2019-05-09 07:34:42.599409+00
  2 |    2 | 2019-05-09 07:34:42.599409+00
  3 |    3 | 2019-05-09 07:34:42.599409+00
  4 |    4 | 2019-05-09 07:34:42.599409+00
  5 |    5 | 2019-05-09 07:34:42.599409+00
(5 rows)

```

接着，我们在本地通过 dblink 进行连接。

```
postgres=# SELECT dblink_connect('remote_dblink_test', 'dbname=remotedb hostaddr=10.9.10.24 port=5432 user=postgres password=postgres');
 dblink_connect
----------------
 OK
(1 row)

postgres=# SELECT * FROM dblink('remote_dblink_test', 'SELECT * FROM remote_test;') AS t(id int, ival int, create_time timestamptz);
 id | ival |          create_time
----+------+-------------------------------
  1 |    1 | 2019-05-09 15:34:42.599409+08
  2 |    2 | 2019-05-09 15:34:42.599409+08
  3 |    3 | 2019-05-09 15:34:42.599409+08
  4 |    4 | 2019-05-09 15:34:42.599409+08
  5 |    5 | 2019-05-09 15:34:42.599409+08
(5 rows)

postgres=# SELECT u.id, name, create_time FROM userinfo u JOIN dblink('remote_dblink_test', 'SELECT * FROM remote_test;') AS t(id int, ival int, create_time timestamptz) ON u.id = t.id;
 id | name |          create_time
----+------+-------------------------------
  1 | Eric | 2019-05-09 15:34:42.599409+08
  2 | Tom  | 2019-05-09 15:34:42.599409+08
(2 rows)

```

## 关闭 dblink

最后，当不需要在使用 dblink 访问外部数据库时，我们需要使用 `dblink_disconnect` 来关闭连接。首先，我们通过 `dblink_get_connections` 来查看现有的 dblink 连接，随后将其关闭。

```
postgres=# SELECT dblink_get_connections();
         dblink_get_connections
----------------------------------------
 {local_dblink_test,remote_dblink_test}
(1 row)

postgres=# SELECT dblink_disconnect('remote_dblink_test');
 dblink_disconnect
-------------------
 OK
(1 row)

postgres=# SELECT dblink_disconnect('local_dblink_test');
 dblink_disconnect
-------------------
 OK
(1 row)

```

## 参考

[1] https://www.postgresql.org/docs/11/dblink.html

[PostgreSQL dblink]: https://www.postgresql.org/docs/10/dblink.html
