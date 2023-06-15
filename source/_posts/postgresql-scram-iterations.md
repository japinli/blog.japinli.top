---
title: PostgreSQL SCRAM 认证密码迭代次数
date: 2023-06-07 23:58:45
categories: 数据库
tags:
  - PostgreSQL
---

在{% post_link postgresql-password 上一篇 %}文章中，我们聊到了 PostgreSQL 的认证机制，其中提到了 SCRAM-SHA-256 认证，在我写那篇文章的前两天，[PostgreSQL 支持了 SCRAM 迭代次数的修改](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=b577743000cd0974052af3a71770a23760423102)，它引入了一个 [`scram_iterations`][] 参数来定义 SCRAM 的迭代次数。

<!--

	commit b577743000cd0974052af3a71770a23760423102
	Author: Daniel Gustafsson <dgustafsson@postgresql.org>
	Date:   Mon Mar 27 09:46:29 2023 +0200

	    Make SCRAM iteration count configurable

	    Replace the hardcoded value with a GUC such that the iteration
	    count can be raised in order to increase protection against
	    brute-force attacks.  The hardcoded value for SCRAM iteration
	    count was defined to be 4096, which is taken from RFC 7677, so
	    set the default for the GUC to 4096 to match.  In RFC 7677 the
	    recommendation is at least 15000 iterations but 4096 is listed
	    as a SHOULD requirement given that it's estimated to yield a
	    0.5s processing time on a mobile handset of the time of RFC
	    writing (late 2015).

	    Raising the iteration count of SCRAM will make stored passwords
	    more resilient to brute-force attacks at a higher computational
	    cost during connection establishment.  Lowering the count will
	    reduce computational overhead during connections at the tradeoff
	    of reducing strength against brute-force attacks.

	    There are however platforms where even a modest iteration count
	    yields a too high computational overhead, with weaker password
	    encryption schemes chosen as a result.  In these situations,
	    SCRAM with a very low iteration count still gives benefits over
	    weaker schemes like md5, so we allow the iteration count to be
	    set to one at the low end.

	    The new GUC is intentionally generically named such that it can
	    be made to support future SCRAM standards should they emerge.
	    At that point the value can be made into key:value pairs with
	    an undefined key as a default which will be backwards compatible
	    with this.

	    Reviewed-by: Michael Paquier <michael@paquier.xyz>
	    Reviewed-by: Jonathan S. Katz <jkatz@postgresql.org>
	    Discussion: https://postgr.es/m/F72E7BC7-189F-4B17-BF47-9735EB72C364@yesql.se

-->

<!--more-->

## 用法

参数 [`scram_iterations`][] 的默认值为 4096，这与 PostgreSQL 之前的硬编码值相同（同时也是 [RFC 7677][] 里面定义的最小迭代次数）。如下所示，我们创建了三个用户，它们使用了不同的迭代次数。

```
[local]:889416 postgres=# \timing
Timing is on.
[local]:889416 postgres=# SET scram_iterations TO 1;
SET
Time: 0.533 ms
[local]:889416 postgres=# CREATE USER scram_1 WITH password 'hello';
CREATE ROLE
Time: 1.055 ms
[local]:889416 postgres=# SET scram_iterations TO 100000;
SET
Time: 0.320 ms
[local]:889416 postgres=# CREATE USER scram_4096 WITH password 'hello';
CREATE ROLE
Time: 9.182 ms
[local]:889416 postgres=# SET scram_iterations TO 100000;
SET
Time: 0.430 ms
[local]:889416 postgres=# CREATE USER scram_100000 WITH password 'hello';
CREATE ROLE
Time: 214.233 ms
```

从创建用户语句的执行时间上我们可以看到迭代次数越小、执行的速度越快。接着我们看看 `pg_authid` 表中 `rolpassword` 的存储。

```
SELECT rolname,
       regexp_replace(rolpassword,
                      '(SCRAM-SHA-256)\$(\d+):([a-zA-Z0-9+/=]+)\$([a-zA-Z0-9+/=]+):([a-zA-Z0-9+/=]+)',
                      '\1$\2:<slat>$<storeKey>:<serverKey>') AS rolpassword
FROM pg_authid WHERE rolname ~ 'scram*';
   rolname    |                    rolpassword
--------------+----------------------------------------------------
 scram_1      | SCRAM-SHA-256$1:<slat>$<storeKey>:<serverKey>
 scram_4096   | SCRAM-SHA-256$4096:<slat>$<storeKey>:<serverKey>
 scram_100000 | SCRAM-SHA-256$100000:<slat>$<storeKey>:<serverKey>
(3 rows)

Time: 4.046 ms
```

可以看到 `rolpassword` 里面记录了 SCRAM 的迭代次数。

## 性能

SCRAM 的迭代次数越大，对抗暴力攻击的能力就越强，但是任何事情都是有两面性的；迭代次数越大，带来的问题就是连接的时候认证的时间越长（从上面创建用户的执行时间就可以看出端倪）。这里我们使用 pgbench 对不同的迭代次数进行连接测试。

首先创建一个测试文件用于 pgbench 执行，如下所示：

```bash
$ cat pgbench-empty.sql
\set a 10
```

接着我们需要修改 `pg_hba.conf`，确保其使用 SCRAM-SHA-256 认证方式，修改之后的结果如下所示（这里我使用的是本地连接）：

```
[local]:914251 postgres=# select * from pg_hba_file_rules ;
 rule_number |                        file_name                         | line_number | type  |   database    | user_name |  address  |                 netmask                 |  auth_method  | options | error
-------------+----------------------------------------------------------+-------------+-------+---------------+-----------+-----------+-----------------------------------------+---------------+---------+-------
           1 | /home/japin/Codes/postgresql/Debug/pg/pgdata/pg_hba.conf |         117 | local | {all}         | {all}     |           |                                         | scram-sha-256 |         |
           2 | /home/japin/Codes/postgresql/Debug/pg/pgdata/pg_hba.conf |         119 | host  | {all}         | {all}     | 127.0.0.1 | 255.255.255.255                         | scram-sha-256 |         |
           3 | /home/japin/Codes/postgresql/Debug/pg/pgdata/pg_hba.conf |         121 | host  | {all}         | {all}     | ::1       | ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff | scram-sha-256 |         |
           4 | /home/japin/Codes/postgresql/Debug/pg/pgdata/pg_hba.conf |         124 | local | {replication} | {all}     |           |                                         | trust         |         |
           5 | /home/japin/Codes/postgresql/Debug/pg/pgdata/pg_hba.conf |         125 | host  | {replication} | {all}     | 127.0.0.1 | 255.255.255.255                         | trust         |         |
           6 | /home/japin/Codes/postgresql/Debug/pg/pgdata/pg_hba.conf |         126 | host  | {replication} | {all}     | ::1       | ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff | trust         |         |
(6 rows)
```

接着我们需要配置用户的密码，您可以使用 `~/.pgpass` 进行配置，这里为了简便，我们在创建用户的时候使用了相同的密码，因此使用 `PGPASSWORD` 环境变量。

```bash
$ export PGPASSWORD=hello
```

测试结果如下所示：

```
$ pgbench -n -T 30 -f pgbench-empty.sql -C -U scram_1 postgres
pgbench (16beta1)
transaction type: pgbench-empty.sql
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 30 s
number of transactions actually processed: 4088
number of failed transactions: 0 (0.000%)
latency average = 7.340 ms
average connection time = 7.335 ms
tps = 136.248832 (including reconnection times)

$ pgbench -n -T 30 -f pgbench-empty.sql -C -U scram_4096 postgres
pgbench (16beta1)
transaction type: pgbench-empty.sql
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 30 s
number of transactions actually processed: 2106
number of failed transactions: 0 (0.000%)
latency average = 14.247 ms
average connection time = 14.241 ms
tps = 70.191579 (including reconnection times)

$ pgbench -n -T 30 -f pgbench-empty.sql -C -U scram_100000 postgres
pgbench (16beta1)
transaction type: pgbench-empty.sql
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 30 s
number of transactions actually processed: 153
number of failed transactions: 0 (0.000%)
latency average = 196.268 ms
average connection time = 196.258 ms
tps = 5.095077 (including reconnection times)
```

{% asset_img scram.png scram auth comprasion %}

虽然这只是一个默认的数据库实例，但是不同迭代次数对数据库的性能影响还是比较大的，因此在使用的时候我们需要在安全性与性能之间做好权衡。

## 参考

[1] https://www.postgresql.org/docs/16/runtime-config-connection.html#GUC-SCRAM-ITERATIONS
[2] https://paquier.xyz/postgresql-2/postgres-16-scram-iterations/

<div class="just-for-fun">
笑林广记 - 臭辣梨

北地产梨甚佳，北人至南，索梨食，不得。
南人因进萝卜，曰：“此敝乡土产之梨也。”
北人曰：“此物吃下，转气就臭，味又带辣，只该唤他做臭辣梨。”
</div>

[`scram_iterations`]: https://www.postgresql.org/docs/16/runtime-config-connection.html#GUC-SCRAM-ITERATIONS
[RFC 7677]: https://www.rfc-editor.org/rfc/rfc7677
