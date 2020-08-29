---
title: "PostgreSQL HASH 索引拾遗"
date: 2020-02-20 22:21:40 +0800
category: 数据库
tags:
  - PostgreSQL
---

PostgreSQL 的 HASH 索引在 9.6 和 10 版本中有所不同，主要的区别在于 HASH 索引在 9.6 及其之前的版本中不会记录在 WAL 日志中，然而在 10 及其之后的版本这个已经被修复了。

例如，下面是在 PostgreSQL 9.6.17 中创建 HASH 索引。

``` pgpsql
postgres=# CREATE INDEX id_hash_index ON hash_table USING hash(id);
WARNING:  hash indexes are not WAL-logged and their use is discouraged
CREATE INDEX
```

从警告中可以看到，PostgreSQL 已经给出了明确提示。然而在 PostgreSQL 12.2 中，创建 HASH 索引则没有上述提示：

``` pgpsql
postgres=# create index idx_hash_id on hash_table using hash(id);
CREATE INDEX
```

<!-- more -->

## 测试

首先我们通过 ruby 创建测试数据：

``` ruby
$ ruby -e '(1..1000).each { |i| puts i.to_s.rjust(20, "0") }' > data.txt
```

我们采用 PG9.6.17 搭建主从同步流复制，随后在主库上创建 `hash_table` 表，然后插入数据，并在从库查询，如下所示：

``` pgpsql
postgres=# create table hash_table(id varchar(256));
postgres=# copy hash_table from '/path/to/data.txt';
postgres=# create index idx_hash_table_id on hash_table using hash(id);
```

接着，我们分别在主库和从库上查看，如下所示：

``` pgpsql
postgres=# select count(*) from hash_table;  -- 主库
 count
-------
 10000
(1 row)

postgres=# select * from hash_table where id = '00000000000000000023';
          id
----------------------
 00000000000000000023
(1 row)

postgres=# select pg_size_pretty(pg_relation_size('idx_hash_table_id));
 pg_size_pretty
----------------
 528 kB
(1 row)

postgres=# select count(*) from hash_table;  -- 从库
 count
-------
 10000
(1 row)

postgres=# select * from hash_table where id = '00000000000000000023';
ERROR:  could not read block 0 in file "base/12407/24577": read only 0 of 8192 bytes

postgres=# select pg_size_pretty(pg_relation_size('idx_hash_table_id));
 pg_size_pretty
----------------
 0 bytes
(1 row)
```

从上面的输出结果也可以看到，HASH 索引并没有记录到 WAL 日志中，因此有关 HASH 索引的操作都不会在从节点进行重放。

同样地，我们也可以在 PG12.2 中进行测试。其结果如下所示：

``` pgpsql
postgres=# select count(*) from hash_table;  -- 主库
 count
-------
 10000
(1 row)

postgres=# select * from hash_table where id = '00000000000000000023';
          id
----------------------
 00000000000000000023
(1 row)

postgres=# select pg_size_pretty(pg_relation_size('idx_hash_table_id'));
 pg_size_pretty
----------------
 592 kB
(1 row)

postgres=# select count(*) from hash_table;  -- 从库
 count
-------
 10000
(1 row)

postgres=# select * from hash_table where id = '00000000000000000023';
          id
----------------------
 00000000000000000023
(1 row)

postgres=# select pg_size_pretty(pg_relation_size('idx_hash_table_id'));
 pg_size_pretty
----------------
 592 kB
(1 row)
```

## 参考

[1] https://postgrespro.com/blog/pgsql/4161321
[2] https://www.postgresql.org/docs/9.6/continuous-archiving.html
[3] https://www.postgresql.org/docs/10/continuous-archiving.html
[4] https://blog.andrebarbosa.co/hash-indexes-on-postgres/
