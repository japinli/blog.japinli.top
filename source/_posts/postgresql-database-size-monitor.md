---
title: "PostgreSQL 数据库大小监控"
date: 2019-09-03 22:39:47 +0800
category: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

最近在客户那边了解到一个需求，想要监控 PostgreSQL 数据库每天的大小变化。其实这个功能挺简单的，PostgreSQL 可以通过函数 `pg_database_size()` 来获取数据库的大小，而客户需要做的就是每天去执行一下，并与上次的结果进行比较就可以得到了。当然，手动执行的效率不是很高，因此，我利用业余时间整理了一下，将这个需求通过 PostgreSQL 插件的形式提供出来。本文主要介绍一下如何实现这个功能。

<!-- more -->

## 思路

其实这个功能的思路挺简单的，首先记录数据库大小，然后定期获取数据库大小，并与上一次数据库的大小相减获取这个数据库的增量，就这么简单。那么，我们需要通过什么技术来实现这个功能呢？当然，我们需要一个定时器；其次，我们需要一个结构来维护数据库的大小历史变更。

当然我们可以通过 shell 来实现这个功能，利用 crontab 添加一个定时器，然后将数据库的大小保存下来，再次获取时数据库大小时减去保存下来的数据库大小值便能获取增量。这里有一个问题就是数据库的大小历史如何来维护？

如果是通过数据库插件来实现，我们可以直接将这些历史变更记录在数据表中，这样做也可以方便后续查询。那么定时器如何实现了？这个其实 PostgreSQL 已经为我们提供了。我们可以通过创建一个后台进程来定期获取数据库的大小，并维护数据库增量信息。

## 后台进程

PostgreSQL 扩展可以在单独的进程中运行用户提供的代码。这些进程由 postgres 启动、停止和监控，这使得它们的生命周期与服务器的状态紧密相关。这些进程可以选择附加到 PostgreSQL 的共享内存区域并在内部连接到数据库。PostgreSQL 后台工作进程由 `BackgroundWorker` 结构来定义（如下所示），它需要在 `_PG_init()` 函数中通过 `RegisterBackgroundWorker()` 来注册。

``` C
typedef void (*bgworker_main_type)(Datum main_arg);
typedef struct BackgroundWorker
{
    char        bgw_name[BGW_MAXLEN];
    char        bgw_type[BGW_MAXLEN];
    int         bgw_flags;
    BgWorkerStartTime bgw_start_time;
    int         bgw_restart_time;       /* in seconds, or BGW_NEVER_RESTART */
    char        bgw_library_name[BGW_MAXLEN];
    char        bgw_function_name[BGW_MAXLEN];
    Datum       bgw_main_arg;
    char        bgw_extra[BGW_EXTRALEN];
    int         bgw_notify_pid;
} BackgroundWorker;
```

__备注：__ 该结构在不同的版本之间可能有所不同，请以[官网文档](https://www.postgresql.org/docs/11/bgworker.html)为准，本文基于 PostgreSQL 11 版本。

* `bgw_name` 和 `bgw_type` 是在日志消息，进程列表和类似上下文中使用的字符串。
* `bgw_flags` 是一个按位或位掩码，表示模块想要的功能。目前该域有两个值：`BGWORKER_SHMEM_ACCESS` - 请求共享内存访问；`BGWORKER_BACKEND_DATABASE_CONNECTION` - 请求能够建立数据库连接，以便以后可以运行事务和查询(需要与 `BGWORKER_SHMEM_ACCESS` 联合使用)。
* `bgw_start_time` 是 postgres 启动进程的服务器状态。目前该域有三个值：`BgWorkerStart_PostmasterStart` - postgres 本身完成自己的初始化后立即开始，请求此进程的进程不符合数据库连接的条件；`BgWorkerStart_ConsistentState` - 在热备用数据库中达到一致状态后立即启动，允许进程以只读的方式连接到数据库；`BgWorkerStart_RecoveryFinished` - 系统进入正常读写状态后立即启动。最后两个值在不是热备用的服务器中是等效的。此设置仅指示何时启动进程；当达到不同的状态时，它们不会停止。
* `bgw_restart_time` 是 postgres 在重新启动进程之前应该等待的时间间隔（以秒为单位）。当设置为 `BGW_NEVER_RESTART` 则表示崩溃后不重新启动进程。
* `bgw_library_name` - 是库的名称，在该库中应该包含后台工作进程的入口点。如果是从核心代码中加载函数，需要将其设置为 "postgres"。
* `bgw_function_name` 是动态加载库中函数的名称，该函数是新后台工作进程的入口点。
* `bgw_main_arg` 是后台进程入口函数的参数，参数类型为 `Datum`。

更多关于该结构的介绍请看官方文档，任何时候您都应该以官方文档为主。

我们可以在后台进程中通过定时器来定时执行相应的 SQL 来查询数据库大小并计算数据库的增量。PostgreSQL 提供了 Latch 机制，我们可以利用它很方便地实现定时器功能。

## 扩展插件

关于如何编写 PostgreSQL 可以参考{% post_link write-postgresql-extension 这里%}，当然第一手资料还是[官方文档](https://www.postgresql.org/docs/11/extend-pgxs.html)。我们首先新建一个 `pg_dbsm` 目录用于存放该插件源码，其内容如下：

``` shell
➜  pg_dbsm ls -l
total 48
-rw-r--r--  1 japinli  staff   277 Sep  4 22:32 Makefile
-rw-r--r--  1 japinli  staff   244 Sep  4 22:29 README.md
-rw-r--r--  1 japinli  staff   402 Sep  4 22:24 pg_dbsm--0.0.1.sql
-rw-r--r--  1 japinli  staff  7785 Sep  4 22:38 pg_dbsm.c
-rw-r--r--  1 japinli  staff    98 Sep  4 22:23 pg_dbsm.control
```

为了方便配置定时器的时间，我们将定时器的值以参数的形式给出，与此同时，我们需要连接一个数据库用于创建需要存储数据库大小历史记录，为此，我们增加了一个数据库参数，我们将在该数据库中建立一个名为 `dbsm` 的数据表，其定义如下：

```
postgres=# \d+ dbsm
                                            Table "public.dbsm"
 Column  |           Type           | Collation | Nullable | Default | Storage | Stats target | Description
---------+--------------------------+-----------+----------+---------+---------+--------------+-------------
 datname | name                     |           | not null |         | plain   |              |
 created | timestamp with time zone |           |          | now()   | plain   |              |
 datsize | bigint                   |           | not null |         | plain   |              |
 incsize | bigint                   |           |          |         | plain   |              |
Indexes:
    "idx_datname_created" btree (datname, created)

```

后台进程的处理流程如下：

1. 设置信号处理函数；
2. 连接 `dbsm_database` 指定的数据库，默认为 `postgres`；
3. 初始化数据库表对象，即 `dbsm`，并建立索引；
4. 构建查询 SQL 语句；
5. 循环执行查询 SQL 语句并更新 `dbsm` 表。

上面的流程主要在函数 `dbsm_main()` 中体现，其代码如下所示：

``` C
void
dbsm_main()
{
    StringInfoData    buf;

    /* Establish signal handlers before unblocking signals. */
    pqsignal(SIGHUP, dbsm_sighup);
    pqsignal(SIGTERM, dbsm_sigterm);

    /* We're now ready to receive signals */
    BackgroundWorkerUnblockSignals();

    BackgroundWorkerInitializeConnection(dbsm_database, NULL, 0);

    initialize_dbsm_object();

    initStringInfo(&buf);
    appendStringInfo(&buf,
                     "WITH m AS (SELECT DISTINCT ON (datname) datname, "
                     "datsize FROM dbsm ORDER BY datname, created DESC) "
                     "INSERT INTO dbsm SELECT d.datname, now(), "
                     "pg_database_size(d.datname) AS datsize, "
                     "CASE WHEN m.datsize = NULL THEN 0 "
                     "ELSE pg_database_size(d.datname) - m.datsize END AS incsize "
                     "FROM pg_database d LEFT JOIN m ON m.datname = d.datname;");

    /*
     * Main loop: do this until the SIGTERM handler tells us to terminate
     */
    while (!got_sigterm)
    {
        int    ret;

        /*
         * Background workers mustn't call usleep() or any direct equivalent:
         * instead, they may wait on their process latch, which sleeps as
         * necessary, but is awakened if postmaster dies.  That way the
         * background process goes away immediately in an emergency.
         */
        (void) WaitLatch(MyLatch,
                         WL_LATCH_SET | WL_TIMEOUT | WL_POSTMASTER_DEATH,
                         dbsm_naptime * 1000L,
                         PG_WAIT_EXTENSION);
        ResetLatch(MyLatch);

        CHECK_FOR_INTERRUPTS();

        /*
         * In case of a SIGHUP, just reload the configuration.
         */
        if (got_sighup)
        {
            got_sighup = false;
            ProcessConfigFile(PGC_SIGHUP);
        }

        /*
         * Start a transaction on which we can run queries.  Note that each
         * StartTransactionCommand() call should be preceded by a
         * SetCurrentStatementStartTimestamp() call, which sets both the time
         * for the statement we're about the run, and also the transaction
         * start time.  Also, each other query sent to SPI should probably be
         * preceded by SetCurrentStatementStartTimestamp(), so that statement
         * start time is always up to date.
         *
         * The SPI_connect() call lets us run queries through the SPI manager,
         * and the PushActiveSnapshot() call creates an "active" snapshot
         * which is necessary for queries to have MVCC data to work on.
         *
         * The pgstat_report_activity() call makes our activity visible
         * through the pgstat views.
         */
        SetCurrentStatementStartTimestamp();
        StartTransactionCommand();
        SPI_connect();
        PushActiveSnapshot(GetTransactionSnapshot());
        pgstat_report_activity(STATE_RUNNING, buf.data);

        ret = SPI_execute(buf.data, false, 0);
        if (ret != SPI_OK_INSERT)
            elog(FATAL, "execute: \"%s\" failed", buf.data);

        SPI_finish();
        PopActiveSnapshot();
        CommitTransactionCommand();
        pgstat_report_stat(false);
        pgstat_report_activity(STATE_IDLE, NULL);
    }

    pfree(buf.data);
    proc_exit(0);
}
```

当启动数据库后，我们运行一段时间后查询表 `dbsm` 便可以看到如图所示的结果。

{% asset_img result.png 效果图 %}

完整代码在[这里](https://github.com/japinli/pg_dbsm)。当然，这个代码目前还不完善，可能存在一些问题。

## 参考

[1] https://www.postgresql.org/docs/11/bgworker.html
[2] https://www.postgresql.org/docs/11/extend-pgxs.html
[3] https://tapoueh.org/images/confs/extension-tutoriel.pdf
[4] https://github.com/postgres/postgres/blob/REL_11_STABLE/src/test/modules/worker_spi/worker_spi.c
