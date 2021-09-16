---
title: "PostgreSQL 逻辑复制"
date: 2020-12-13 17:37:55
category: 数据库
tags:
  - PostgreSQL
---

PostgreSQL 数据库在 9.0 中引入了物理复制，之前的文章中也有介绍。物理复制将主库中所有的更改都通过 WAL 日志流式地传输到备库中，备库通过重放 WAL 日志来实现同步。但是，物理复制也有其自身的局限性。

* 不能执行有选择性的复制，或者说不支持复制部分数据库对象；
* 不能在不同的数据大版本之间进行复制，例如，pg10 -> pg12 是无法通过物理复制来实现同步的；
* 不能在不同平台之间进行复制，例如，Linux 和 Windows 之间不能使用物理复制来实现同步；
* 备库无法提供写入操作。

PostgreSQL 在版本 10 中引入了逻辑复制，它用于解决上述物理复制的局限性，同时业务复制开辟了一个新的方向。逻辑复制使用发布和订阅模式，一个或多个订阅者可以订阅一个发布者上的一个或多个发布。订阅者最初会从发布者那里收到复制的数据库对象的副本，并在同一对象上实时进行后续更改。

<!-- more -->

## 原理

正如上面所说，PostgreSQL 的逻辑复制采用的是发布-订阅模型，因此，在发布者（publisher）节点上，它将创建一个发布（publication），它是一个表或一组表的更改集合；在订阅者（subscriber）节点上，它将创建一个订阅（subscription），它可以订阅来自同一个发布者的一个或多个发布。

逻辑复制通常从获取发布者数据库上的数据快照并将其复制到订阅者开始，这被称为表同步阶段（table synchronization phase）。在表同步阶段，如果存在多个表需要同步，那么 PostgreSQL 将创建多个进程来进行同步，但是每个表只能有一个同步进程。一旦复制完成后，发布者节点中的后续更改将实时发送给订阅者节点。订阅者以与发布者相同的顺序应用数据，从而确保单个订阅中的发布具有事务一致性。这种数据复制方法有时称为事务复制。

## 语法

在使用逻辑复制之前，我们需要在发布者将 `wal_level` 参数修改为 `logical`。这将指示服务器在 WAL 中存储其他信息，以将二进制更改转换为逻辑更改。接下来，我们就可以使用命令创建 `CREATE PUBLICATION` 创建发布了，其语法如下所示。

```
CREATE PUBLICATION name
    [ FOR TABLE [ ONLY ] table_name [ * ] [, ...]
      | FOR ALL TABLES ]
    [ WITH ( publication_parameter [= value] [, ... ] ) ]
```

* __name__ - 表示发布的名称，该名称在当前数据库中必须唯一。
* __FOR TABLE__ - 指定需要添加到该发布中的表。如果指定了 __ONLY__，那么仅该表纳入发布中，反之，其后代表也被纳入到发布中。您也可以在表名后加上 `*` 来显示地将后代表纳入发布中。分区表总是纳入到发布中的，因此我们不需要显示地将分区表的子表加入到发布中。
  只有持久话的基表和分区表可以做个发布的内容。临时表、无日志表、外表、物化视图和常规视图都不能作为发布的内容。分区表被加入到发布中后，其后续的字表将自动加入到发布中。
* __FOR ALL TABLES__ - 将发布标记为可复制数据库中所有的表，包括将来创建的表。
* __WITH__ - 指定发布可选的参数，目前支持两个参数。
  - __publish (string)__ - 此参数确定新发布将向订阅者发布哪些 DML 操作。这些操作包括 `insert`、`update`、`delete` 和 `truncate`。默认是所有操作。
  - __publish\_via\_partition\_root (boolean)__ - 此参数决定是否使用分区表（或其分区上）的身份和模式，而不是实际更改的各个分区的身份和模式来发布发布发布中包含的分区表（或其分区上）的更改；后者是默认值。启用此功能可以将更改复制到非分区表或由不同分区集组成的分区表中。
    如果启用此功能，直接在分区上执行的TRUNCATE操作将不会被复制。

这里有几点我们需要注意：

1. 逻辑复制不支持 DDL 操作。
2. `COPY ... FROM` 命令是由 `INSERT` 操作来发布的。
3. `INSERT ... ON CONFLICT` 命令是根据其最终结果来决定发布的命令。如果其不是 `INSERT` 或 `UPDATE`，它甚至可能不会发布。
4. 添加到发布中以发布 `UPDATE ` 和/或 `DELETE` 操作的表必须定义 `REPLICA IDENTITY`。
5. 用户需要有足够的权限才可以将表加入到发布中。对于 `FOR ALL TABLES` 必须是超级用户。
6. 用户必须具有 `CREATE` 权限才可以创建发布（超级用户除外）。
7. 发布创建完成之后并没有开始复制流程，它仅仅是为订阅者定义了分组和过滤逻辑。
8. 如果没有指定 `FOR TABLE` 和 `FOR ALL TABLES`，则发表一组空表，这对于后续添加表非常有用。

有了发布者之后，我们就需要创建订阅者了，其语法如下所示。

```
CREATE SUBSCRIPTION subscription_name
    CONNECTION 'conninfo'
    PUBLICATION publication_name [, ...]
    [ WITH ( subscription_parameter [= value] [, ... ] ) ]
```

* __subscription\_name__ - 订阅者名称，当前数据库必须唯一。
* __conninfo__ - 连接到发布者的连接字符串。
* __publication\_name__ - 发布者上的发布名。
* __WITH__ - 指定订阅的可选参数。目前支持以下参数。
  - __copy\_data (boolean)__ - 指定复制开始后是否应复制正在订阅的发布中的现有数据，默认 `true`。
  - __create\_slot (boolean)__ - 指定命令是否应在发布者上创建复制槽，默认 `true`。
  - __enabled (boolean)__ - 指定订阅是应该主动复制，还是应该仅设置但尚未启动，默认值为 `true`。
  - __slot\_name (string)__ - 指定复制槽的名称。如果指定为 `NONE`，那么这个复制上将不会使用复制槽，这种情况下需要 `enabled` 和 `create_slot` 设置为 `false`。
  - __syncronous\_commit (enum)__ - 该参数将重写订阅重放进程的 `syncronous_commit` 参数。默认值为 `off`。
    对于逻辑复制来说，该参数设置为 `off` 是安全的，如果订阅者由于缺少同步而丢失了事务，那么数据将再次从发布者发送。
  - __binary (boolean)__ - 指定订阅是否将请求发布者以二进制格式（而不是文本）发送数据，默认值为 `false`。
    当跨版本复制时，发布者可能对某种数据类型具有二进制发送功能，而订阅者却缺乏该类型的二进制接收功能。在这种情况下，数据传输将失败，因此不能使用 `binary` 选项。
  - __connect (boolean)__ - 指定 `CREATE SUBSCRIPTION` 是否连接到发布者。若将该参数设置为 `false`,那么 `enabled`、`create_slot` 和 `copy_data` 的默认值将被设置为 `false`。
  - __streaming (boolean)__ - 指定是否将正在进行的事务进行发布。默认情况下，所有的事务将在发布者进行完全编码，然后作为一个整体发送给订阅者。

## 示例

接下来，我们将展示如何使用逻辑复制。首先我创建一个简单的表，并插入一条记录。

```
postgres[5432]=# CREATE TABLE t1 (a integer PRIMARY KEY, b integer);
CREATE TABLE
postgres[5432]=# INSERT INTO t1 VALUES (1, 1);
INSERT 0 1
```

接下来，我们为这个表创建一个发布。

```
postgres[5432]=# CREATE PUBLICATION my_pub FOR TABLE t1;
CREATE PUBLICATION
```

现在，发布已经创建完了，现在我们需要创建订阅。注意，我们在同一机器上的不通端口运行两个 PostgreSQL 数据库实例。

```
postgres[8765]=# CREATE TABLE t1(a integer PRIMARY KEY, b integer);
CREATE TABLE
postgres[8765]=# CREATE SUBSCRIPTION my_sub CONNECTION 'host=localhost port=5432 dbname=postgres' PUBLICATION my_pub;
NOTICE:  created replication slot "my_sub" on publisher
CREATE SUBSCRIPTION
```

现在，我们可以验证数据是否被复制过来。

```
postgres[8765]=# TABLE t1;
 a | b
---+---
 1 | 1
(1 row)
```

接下来，我在验证数据更改之后是否被复制。首先，我们在发布者上插入一条记录，随后在订阅者上查看该记录是否被复制。

```
postgres[5432]=# INSERT INTO t1 VALUES (2, 2);
INSERT 0 1

postgres[8765]=# TABLE t1;
 a | b
---+---
 1 | 1
 2 | 2
(2 rows)
```

从上面可以看到，数据被正确复制到订阅者。


## 分区表的流复制

这里对分区表的流复制特别说明一下，在 PostgreSQL 13 中，对于分区表流复制引入了一个新的参数 `publish_via_partition_root`，默认为 `false`。文档说明如下。

> This parameter determines whether changes in a partitioned table (or on its partitions)
> contained in the publication will be published using the identity and schema of the
> partitioned table rather than that of the individual partitions that are actually changed;
> the latter is the default. Enabling this allows the changes to be replicated into a
> non-partitioned table or a partitioned table consisting of a different set of partitions.
>
> If this is enabled, TRUNCATE operations performed directly on partitions are not replicated.

### publish_via_partition_root (false)

我们先来看看默认情况下，逻辑复制的分区表表现形式。

```
postgres[5432]=# CREATE TABLE parted_parent (a integer, b integer) PARTITION BY RANGE(a);
CREATE TABLE
postgres[5432]=# CREATE TABLE parted_child01 PARTITION OF parted_parent FOR VALUES FROM (1) TO (10);
CREATE TABLE
postgres[5432]=# CREATE TABLE parted_child02 PARTITION OF parted_parent FOR VALUES FROM (10) TO (20);
CREATE TABLE
postgres[5432]=# INSERT INTO parted_parent VALUES (1, 1), (11, 11);
INSERT 0 2
postgres[5432]=# CREATE PUBLICATION my_parted_pub FOR TABLE parted_parent;
CREATE PUBLICATION

postgres[8765]=# CREATE TABLE parted_parent (a integer, b integer) PARTITION BY RANGE(a);
CREATE TABLE
postgres[8765]=# CREATE TABLE parted_child01 PARTITION OF parted_parent FOR VALUES FROM (1) TO (10);
CREATE TABLE
postgres[8765]=# CREATE TABLE parted_child02 PARTITION OF parted_parent FOR VALUES FROM (10) TO (20);
CREATE TABLE
postgres[8765]=# CREATE SUBSCRIPTION my_parted_sub CONNECTION 'host=localhost port=5432 dbname=postgres' PUBLICATION my_parted_pub;
NOTICE:  created replication slot "my_parted_sub" on publisher
CREATE SUBSCRIPTION
postgres[8765]=# TABLE parted_parent;
 a  | b
----+----
  1 |  1
 11 | 11
(2 rows)
```

从上面可以看到，数据从发布者复制到了订阅者上。我们在插入数据看后续的更改是否可以复制。

```
postgres[5432]=# INSERT INTO parted_parent VALUES (2, 2);
INSERT 0 1

postgres[8765]=# TABLE parted_parent;
 a  | b
----+----
  1 |  1
  2 |  2
 11 | 11
(3 rows)
```

一切正常，如果此时我们在发布者上新加一个分区表会如何呢？

```
postgres[5432]=# CREATE TABLE parted_child03 PARTITION OF parted_parent FOR VALUES FROM (20) TO (30);
CREATE TABLE
postgres[5432]=# INSERT INTO parted_parent VALUES (25, 25);
INSERT 0 1
postgres[5432]=# TABLE parted_parent ;
 a  | b
----+----
  1 |  1
  2 |  2
 11 | 11
 25 | 25
(4 rows)

postgres[8765]=# CREATE TABLE parted_child03 PARTITION OF parted_parent FOR VALUES FROM (20) TO (30);
CREATE TABLE
postgres[8765]=# TABLE parted_parent ;
 a  | b
----+----
  1 |  1
  2 |  2
 11 | 11
(3 rows)
```

从上面可以看到新加入的分区子表没能将数据复制到订阅者上。我们在 `parted_child01` 上执行 `TRUNCATE` 看会发生什么情况。

```
postgres[5432]=# TRUNCATE parted_child01;
TRUNCATE TABLE
postgres[5432]=# TABLE parted_parent;
 a  | b
----+----
 11 | 11
 25 | 25
(2 rows)

postgres[8765]=# TABLE parted_parent;
postgres[8765]=# TABLE parted_parent;
 a  | b
----+----
 11 | 11
(1 row)
```

可以看到在分区子表上执行 `TRUNCATE`，其将复制到订阅者上进行相应的操作。那我们可以在订阅者上面不定义分区表，而是采用普通表来存储上游分区表的数据吗？

```
postgres[8765]=# DROP SUBSCRIPTION my_parted_sub;
NOTICE:  dropped replication slot "my_parted_sub" on publisher
DROP SUBSCRIPTION
postgres[8765]=# DROP TABLE parted_parent;
DROP TABLE
postgres[8765]=# \d
Did not find any relations.
postgres[8765]=# CREATE TABLE parted_parent (a integer, b integer);
CREATE TABLE
postgres[8765]=# CREATE SUBSCRIPTION my_parted_sub CONNECTION 'host=localhost port=5432 dbname=postgres' PUBLICATION my_parted_pub;
ERROR:  relation "public.parted_child03" does not exist
```

在这种情况下，分区表不能通过逻辑复制汇总到一个普通表中，但我们仍然可以对其进行复制。

```
postgres[8765]=# CREATE TABLE parted_child01 (a integer, b integer);
CREATE TABLE
postgres[8765]=# CREATE TABLE parted_child02 (a integer, b integer);
CREATE TABLE
postgres[8765]=# CREATE TABLE parted_child03 (a integer, b integer);
CREATE TABLE
postgres[8765]=# CREATE SUBSCRIPTION my_parted_sub CONNECTION 'host=localhost port=5432 dbname=postgres' PUBLICATION my_parted_pub01;
NOTICE:  created replication slot "my_parted_sub" on publisher
CREATE SUBSCRIPTION
postgres[8765]=# table parted_parent ;
 a | b
---+---
(0 rows)

postgres[8765]=# table parted_child01 ;
 a | b
---+---
(0 rows)

postgres[8765]=# table parted_child02 ;
 a  | b
----+----
 11 | 11
(1 row)

postgres[8765]=# table parted_child03 ;
 a  | b
----+----
 25 | 25
(1 row)
```

我们通过建立与分区表对于的表来进行复制，这样是可以到达复制的效果的，但是就丢失了分区表的关系。

我们可以通过对订阅进行刷新来获取新加入的发布表的信息，如下所示。

```
ALTER SUBSCRIPTION my_parted_sub REFRESH PUBLICATION;
```

### publish_via_partition_root (true)

现在，我们来看看当设置了 `publish_via_partition_root`，逻辑复制时分区表是怎样表现的。首先，我们清理一下环境。

```
postgres[8765]=# drop subscription my_parted_sub;
NOTICE:  dropped replication slot "my_parted_sub" on publisher
DROP SUBSCRIPTION
postgres[8765]=# drop table parted_parent, parted_child01, parted_child02, parted_child03;
DROP TABLE

postgres[5432]=# DROP PUBLICATION my_parted_pub;
DROP PUBLICATION
postgres[5432]=# drop table parted_parent;
DROP TABLE
```

接着，我们重复上面的操作。

```
postgres[5432]=# CREATE TABLE parted_parent (a integer, b integer) PARTITION BY RANGE(a);
CREATE TABLE
postgres[5432]=# CREATE TABLE parted_child01 PARTITION OF parted_parent FOR VALUES FROM (1) TO (10);
CREATE TABLE
postgres[5432]=# CREATE TABLE parted_child02 PARTITION OF parted_parent FOR VALUES FROM (10) TO (20);
CREATE TABLE
postgres[5432]=# INSERT INTO parted_parent VALUES (1, 1), (11, 11);
INSERT 0 2
postgres[5432]=# CREATE PUBLICATION my_parted_pub FOR TABLE parted_parent WITH (publish_via_partition_root);
CREATE PUBLICATION

postgres[8765]=# CREATE TABLE parted_parent (a integer, b integer) PARTITION BY RANGE(a);
CREATE TABLE
postgres[8765]=# CREATE TABLE parted_child01 PARTITION OF parted_parent FOR VALUES FROM (1) TO (10);
CREATE TABLE
postgres[8765]=# CREATE TABLE parted_child02 PARTITION OF parted_parent FOR VALUES FROM (10) TO (20);
CREATE TABLE
postgres[8765]=# CREATE SUBSCRIPTION my_parted_sub CONNECTION 'host=localhost port=5432 dbname=postgres' PUBLICATION my_parted_pub;
NOTICE:  created replication slot "my_parted_sub" on publisher
CREATE SUBSCRIPTION
postgres[8765]=# TABLE parted_parent;
 a  | b
----+----
  1 |  1
 11 | 11
(2 rows)
```

接着测试后续更改是否可以复制。

```
postgres[5432]=# INSERT INTO parted_parent VALUES (2, 2);
INSERT 0 1

postgres[8765]=# TABLE parted_parent;
 a  | b
----+----
  1 |  1
  2 |  2
 11 | 11
(3 rows)
```

好像没有什么不同嘛！那新建的分区子表呢？

```
postgres[5432]=# CREATE TABLE parted_child03 PARTITION OF parted_parent FOR VALUES FROM (20) TO (30);
CREATE TABLE
postgres[5432]=# INSERT INTO parted_parent VALUES (25, 25);
INSERT 0 1

postgres[8765]=# CREATE TABLE parted_child03 PARTITION OF parted_parent FOR VALUES FROM (20) TO (30);
CREATE TABLE
postgres[8765]=# TABLE parted_parent;
 a  | b
----+----
  1 |  1
  2 |  2
 11 | 11
 25 | 25
(4 rows)
```

可以看到，这里与上面表现不一致了，新加的分区子表的数据被复制过去了。这只是其中的一个不同，接着我们看看在分区子表上执行 `TRUNCATE`。

```
postgres[5432]=# TRUNCATE parted_child01;
TRUNCATE TABLE
postgres[5432]=# TABLE parted_parent;
 a  | b
----+----
 11 | 11
 25 | 25
(2 rows)

postgres[8765]=# TABLE parted_parent;
 a  | b
----+----
  1 |  1
  2 |  2
 11 | 11
 25 | 25
(4 rows)
```

可以看到，发布者的 `parted_child01` 表被清空了，然而订阅者上的 `parted_child01` 并没有发生变化。这就完了么？当然没有，最后我们来看看订阅者上采用普通表是否可以汇总分区表数据。

```
postgres[8765]=# CREATE TABLE parted_parent (a integer, b integer);
CREATE TABLE
postgres[8765]=# CREATE SUBSCRIPTION my_parted_sub CONNECTION 'host=localhost port=5432 dbname=postgres' PUBLICATION my_parted_pub;
NOTICE:  created replication slot "my_parted_sub" on publisher
CREATE SUBSCRIPTION
postgres[8765]=# TABLE parted_parent ;
 a  | b
----+----
 11 | 11
 25 | 25
(2 rows)
```

这次成功了，说明这种模式下，可以对上游的分区表进行数据汇总，当然我们在下游也可以采用不同的分区策略，一切都是 OK 的。

```
postgres[5432]=# INSERT INTO parted_parent VALUES (1, 1);
INSERT 0 1
postgres[5432]=# INSERT INTO parted_child01 VALUES (2, 2);
INSERT 0 1

postgres[8765]=# TABLE parted_parent ;
 a  | b
----+----
 11 | 11
 25 | 25
  1 |  1
  2 |  2
(4 rows)
```

无论是对分区表或分区子表的数据更新同样被复制到订阅者上了。

## Tips

上面的 psql 提示符是通过命令 `\set PROMPT1 '%/[%>]=%# '` 进行更改的，其中 `%/` 表示当前数据库，`%>` 表示监听的端口，`%#` 表示用户权限，您可以[参考 psql 文档获取更多的信息](https://www.postgresql.org/docs/12/app-psql.html)。

## 更新

* 2021-08-23 - 感谢熊灿灿指出本文中的 BUG，在 `publish_via_partition_root (false)` 中第一个代码段中第 16 行端口错误，原为 `5432`，应更正为 `8765`。

## 参考

[1] https://www.postgresql.org/docs/13/sql-createpublication.html
[2] https://www.postgresql.org/docs/13/sql-createsubscription.html
[3] https://www.enterprisedb.com/postgres-tutorials/logical-replication-postgresql-explained
[4] https://www.postgresql.org/docs/13/sql-altersubscription.html


<div class="just-for-fun">
笑林广记 - 惯撞席

一乡人做巡捕官，值按院门，太守来见，跪报云：“太老官人进。”
按君怒，责之十下。
次日太守来，报云：“太公祖进。”
按君又责之。
至第三日，太守又来，自念乡语不可，通文又不可，乃报云：“前日来的，昨日来的，今日又来了。”
</div>
