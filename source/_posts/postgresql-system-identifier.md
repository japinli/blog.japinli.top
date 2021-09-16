---
title: "PostgreSQL 数据库系统标识符"
date: 2020-06-07 18:07:36 +0800
category: 数据库
tags:
  - PostgreSQL
---

我们都知道 PostgreSQL 针对每个数据库集群实例，都会有一个唯一的标识符 - **system identifier**。那么这个标识符是如何生成的呢？本文将对其进行简要的分析。

<!-- more -->

通过分析 initdb 的源码，我们并不能找到相关的信息，但是我们发现 initdb 是通过 postgres 来进行数据库相关的初始化工作的，在函数 `bootstrap_template1()` 中有如下代码：

``` c
/*
 * run the BKI script in bootstrap mode to create template1
 */
static void
bootstrap_template1(void)
{
    ...

    /* Also ensure backend isn't confused by this environment var: */
    unsetenv("PGCLIENTENCODING");

    snprintf(cmd, sizeof(cmd),
             "\"%s\" --boot -x1 -X %u %s %s %s",
             backend_exec,
             wal_segment_size_mb * (1024 * 1024),
             data_checksums ? "-k" : "",
             boot_options,
             debug ? "-d 5" : "");


    PG_CMD_OPEN;

    for (line = bki_lines; *line != NULL; line++)
    {
        PG_CMD_PUTS(*line);
        free(*line);
    }

    PG_CMD_CLOSE;

    free(bki_lines);

    check_ok();
}
```

如果我们仅使用 `initdb -D pgdata` 来初始化数据库实例，那么它实际上会调用 `postgres --boot -x1 -X 16777216  -F` 来进行初始化。

接下来我们对 postgres 进行分析发现，它将在 `BootStrapXLOG()` 函数中初始化数据库标识符，如下所示：

``` C
void
BootStrapXLOG(void)
{
    CheckPoint  checkPoint;
    char       *buffer;
    XLogPageHeader page;
    XLogLongPageHeader longpage;
    XLogRecord *record;
    char       *recptr;
    bool        use_existent;
    uint64      sysidentifier;
    struct timeval tv;
    pg_crc32c   crc;

    /*
     * Select a hopefully-unique system identifier code for this installation.
     * We use the result of gettimeofday(), including the fractional seconds
     * field, as being about as unique as we can easily get.  (Think not to
     * use random(), since it hasn't been seeded and there's no portable way
     * to seed it other than the system clock value...)  The upper half of the
     * uint64 value is just the tv_sec part, while the lower half contains the
     * tv_usec part (which must fit in 20 bits), plus 12 bits from our current
     * PID for a little extra uniqueness.  A person knowing this encoding can
     * determine the initialization time of the installation, which could
     * perhaps be useful sometimes.
     */
    gettimeofday(&tv, NULL);
    sysidentifier = ((uint64) tv.tv_sec) << 32;
    sysidentifier |= ((uint64) tv.tv_usec) << 12;
    sysidentifier |= getpid() & 0xFFF;

    ...
}
```

从上面的代码中可以看到，PostgreSQL 通过 `gettimeofday()` 函数来获取当前的时间，随后将 `tv.tv_sec`
作为标识符的高 32 位，将 `tv.tv_usec` 作为标识符的低 32 位中的高 20 位，最后将当前进程的 ID 作为标识符的低 12 位，从而构造一个唯一的数据库实例标识符。这样我们就可以通过下面的方式获取到实例的初始化时间。

``` psql
postgres=# select to_timestamp(system_identifier >> 32) from pg_control_system();
      to_timestamp
------------------------
 2019-12-12 22:20:59+08
(1 row)
```
