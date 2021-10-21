---
title: "PostgreSQL 发布者与订阅者不同的 datestyle 导致失败"
date: 2021-10-17 11:15:59 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

最近在浏览 PostgreSQL 邮件列表时发现一个 bug：逻辑复制时，如果发布者和订阅者的 `datestyle` 不一致可能导致逻辑复制失败。本文简要记录这个问题的分析与修复方法。

<!--more-->

## 现象

逻辑复制的环境搭建就不赘述了。我们直接来看看如何重现这个问题。首先我们在发布者上执行下面的命令修改日期格式为 `SQL, MDY`。

```sql
postgres[6789]=# ALTER SYSTEM SET datestyle TO 'SQL, MDY';
```

接着在订阅者上使用相同的命令修改日志格式为 `SQL, DMY`。

```sql
postgres[9876]=# ALTER SYSTEM SET datestyle TO 'SQL, DMY';
```

执行完上述命令之后，重启发布者和订阅者。接着使用下面的命令重现问题。

```
-- publisher
postgres[6789]=# CREATE TABLE tbl (a date);
CREATE TABLE
postgres[6789]=# INSERT INTO tbl values ('10-17-2021'), ('10-18-2021');
INSERT 0 2
postgres[6789]=# CREATE PUBLICATION pub FOR TABLE tbl ;
CREATE PUBLICATION
postgres[6789]=# table tbl;
     a
------------
 10/17/2021
 10/18/2021
(2 rows)

-- subscriber
postgres[9876]=# CREATE TABLE tbl (a date);
CREATE TABLE
postgres[9876]=# CREATE SUBSCRIPTION sub CONNECTION 'dbname=postgres port=6789' PUBLICATION pub;
NOTICE:  created replication slot "sub" on publisher
CREATE SUBSCRIPTION
postgres[9876]=# table tbl ;
 a
---
(0 rows)
```

从上面可以看到，订阅者并没有获取到发布者的数据。查看订阅者的日志，可以发现如下内容：

```
2021-10-17 11:40:41.082 CST [1138050] LOG:  logical replication table synchronization worker for subscription "sub", table "tbl" has started
2021-10-17 11:40:41.106 CST [1138050] ERROR:  date/time field value out of range: "10/17/2021"
2021-10-17 11:40:41.106 CST [1138050] HINT:  Perhaps you need a different "datestyle" setting.
2021-10-17 11:40:41.106 CST [1138050] CONTEXT:  COPY tbl, line 1, column a: "10/17/2021"
2021-10-17 11:40:41.109 CST [1135717] LOG:  background worker "logical replication worker" (PID 1138050) exited with exit code 1
```

以上就是整个问题的复现过程。

## 分析

这个问题是由于 [`datestyle`][datestyle] 这个参数导致的，那么我们先看看它有什么作用。

> **DateStyle (string)**
> Sets the display format for date and time values, as well as the rules for interpreting ambiguous date input values. For historical reasons, this variable contains two independent components: the output format specification (ISO, Postgres, SQL, or German) and the input/output specification for year/month/day ordering (DMY, MDY, or YMD). These can be set separately or together. The keywords Euro and European are synonyms for DMY; the keywords US, NonEuro, and NonEuropean are synonyms for MDY. See [Section 8.5](https://www.postgresql.org/docs/13/datatype-datetime.html) for more information. The built-in default is ISO, MDY, but initdb will initialize the configuration file with a setting that corresponds to the behavior of the chosen lc_time locale.

从文档说明来看，它用于显示日期格式。该参数分为两个独立的部分：输出格式规范和年月日排序的输入输出规范。

输出格式规范包含 `ISO`，`Postgres`，`SQL` 和 `German`。年月日排序的输入输出规范包含 `DMY`，`MDY` 和 `YMD`。

结合日志我们可以发现，发布者的采用的是 `SQL, MDY`，而订阅者采用的是 `SQL, DMY`，因此，发布端的 `10/17/2021` 表示 2021 年 10 月 17 日，然而，在订阅端却被识别为 2021 年 17 月 10 日，从而导致日期越界。

了解了问题的原因，那么我们就可以对其进行修复了。当我们在连接到发布者的时候通过指定 `datestyle` 即可解决这个问题。

通过查看代码我们发现，逻辑复制是通过 `walrcv_connect()` 函数来建立连接的，它被定义为：

```C
#define walrcv_connect(conninfo, logical, appname, err) \
    WalReceiverFunctions->walrcv_connect(conninfo, logical, appname, err)
```

为此，我们需要知道 `WalReceiverFunctions->walrcv_connect()` 函数的实现。`WalReceiverFunctions` 则是在 `libpqwalreceiver.c` 文件中声明定义的一个静态变量，如下所示。

```C
static WalReceiverFunctionsType PQWalReceiverFunctions = {
    libpqrcv_connect,
    libpqrcv_check_conninfo,
    libpqrcv_get_conninfo,
    libpqrcv_get_senderinfo,
    libpqrcv_identify_system,
    libpqrcv_server_version,
    libpqrcv_readtimelinehistoryfile,
    libpqrcv_startstreaming,
    libpqrcv_endstreaming,
    libpqrcv_receive,
    libpqrcv_send,
    libpqrcv_create_slot,
    libpqrcv_get_backend_pid,
    libpqrcv_exec,
    libpqrcv_disconnect
};
```

结合 `WalReceiverFunctionsType` 类型的声明，我们可以得知流复制是通过 `libpqrcv_connect()` 函数来完成的。通过如下修改即可修复上述问题：

```diff
diff --git a/src/backend/replication/libpqwalreceiver/libpqwalreceiver.c b/src/backend/replication/libpqwalreceiver/libpqwalreceiver.c
index 5c6e56a5b2..81cf9e30d7 100644
--- a/src/backend/replication/libpqwalreceiver/libpqwalreceiver.c
+++ b/src/backend/replication/libpqwalreceiver/libpqwalreceiver.c
@@ -30,6 +30,7 @@
 #include "pqexpbuffer.h"
 #include "replication/walreceiver.h"
 #include "utils/builtins.h"
+#include "utils/guc.h"
 #include "utils/memutils.h"
 #include "utils/pg_lsn.h"
 #include "utils/tuplestore.h"
@@ -218,6 +219,7 @@ libpqrcv_connect(const char *conninfo, bool logical, const char *appname,
 	if (logical)
 	{
 		PGresult   *res;
+		const char *datestyle;

 		res = libpqrcv_PQexec(conn->streamConn,
 							  ALWAYS_SECURE_SEARCH_PATH_SQL);
@@ -229,6 +231,23 @@ libpqrcv_connect(const char *conninfo, bool logical, const char *appname,
 							pchomp(PQerrorMessage(conn->streamConn)))));
 		}
 		PQclear(res);
+
+		datestyle = GetConfigOption("datestyle", true, true);
+		if (datestyle != NULL) {
+			char *sql;
+
+			sql = psprintf("SELECT pg_catalog.set_config('datestyle', '%s', false);", datestyle);
+			res = libpqrcv_PQexec(conn->streamConn, sql);
+			if (PQresultStatus(res) != PGRES_TUPLES_OK)
+			{
+				PQclear(res);
+				ereport(ERROR,
+						(errmsg("could not set datestyle: %s",
+								pchomp(PQerrorMessage(conn->streamConn)))));
+			}
+			PQclear(res);
+			pfree(sql);
+		}
 	}

 	conn->logical = logical;
```

需要注意的是物理复制也是通过 `libpqrcv_connect()` 函数来建立连接的。理论上 `datestyle` 仅会影响到逻辑复制，为此，我将设置 `datestyle` 的代码放到了逻辑复制部分中。

最后，附带上测试用例。

```diff
diff --git a/src/test/subscription/t/100_bugs.pl b/src/test/subscription/t/100_bugs.pl
index baa4a90771..a88a61df41 100644
--- a/src/test/subscription/t/100_bugs.pl
+++ b/src/test/subscription/t/100_bugs.pl
@@ -6,7 +6,7 @@ use strict;
 use warnings;
 use PostgresNode;
 use TestLib;
-use Test::More tests => 5;
+use Test::More tests => 6;

 # Bug #15114

@@ -224,3 +224,44 @@ $node_sub->safe_psql('postgres', "DROP TABLE tab1");
 $node_pub->stop('fast');
 $node_pub_sub->stop('fast');
 $node_sub->stop('fast');
+
+# Verify different datestyle between publisher and subscriber.
+$node_publisher = PostgresNode->new('datestyle_publisher');
+$node_publisher->init(allows_streaming => 'logical');
+$node_publisher->append_conf('postgresql.conf',
+	"datestyle = 'SQL, MDY'");
+$node_publisher->start;
+
+$node_subscriber = PostgresNode->new('datestyle_subscriber');
+$node_subscriber->init(allows_streaming => 'logical');
+$node_subscriber->append_conf('postgresql.conf',
+	"datestyle = 'SQL, DMY'");
+$node_subscriber->start;
+
+$node_publisher->safe_psql('postgres',
+	"CREATE TABLE tab_rep(a date)");
+$node_publisher->safe_psql('postgres',
+	"INSERT INTO tab_rep VALUES ('07-18-2021'), ('05-15-2018')");
+
+$node_subscriber->safe_psql('postgres',
+	"CREATE TABLE tab_rep(a date)");
+
+# Setup logical replication
+my $node_publisher_connstr = $node_publisher->connstr . ' dbname=postgres';
+$node_publisher->safe_psql('postgres',
+	"CREATE PUBLICATION tab_pub FOR ALL TABLES");
+$node_subscriber->safe_psql('postgres',
+	"CREATE SUBSCRIPTION tab_sub CONNECTION '$node_publisher_connstr' PUBLICATION tab_pub");
+
+$node_publisher->wait_for_catchup('tab_sub');
+
+my $result = $node_subscriber->safe_psql('postgres',
+	"SELECT count(*) FROM tab_rep");
+is($result, qq(2), 'failed to replication date from different datestyle');
+
+# Clean up the tables on both publisher and subscriber as we don't need them
+$node_publisher->safe_psql('postgres', 'DROP TABLE tab_rep');
+$node_subscriber->safe_psql('postgres', 'DROP TABLE tab_rep');
+
+$node_publisher->stop('fast');
+$node_subscriber->stop('fast');
```

## 参考

[1] https://www.postgresql.org/message-id/CAFF0-CF=D7pc6st-3A9f1JnOt0qmc+BcBPVzD6fLYisKyAjkGA@mail.gmail.com
[2] https://www.postgresql.org/docs/13/runtime-config-client.html#GUC-DATESTYLE


<div class="just-for-fun">
笑林广记 - 同僚

有妻、妾各居者。
一日，妾欲谒妻，谋之于夫：“当如何写帖？”
夫曰：“该用‘寅弟’二字。”
妾问其义如何，夫曰：“同僚写帖，皆用此称呼，做官府之例耳。”
妾曰：“我辈并无官职，如何亦写此帖？”
夫曰：“官职虽无，同僚总是一样。”
</div>

[datestyle]: https://www.postgresql.org/docs/13/runtime-config-client.html#GUC-DATESTYLE
