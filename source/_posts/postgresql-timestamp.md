---
title: "PostgreSQL 中 timestamp 与 timestamptz 的区别"
date: 2023-03-10 11:29:30 +0800
categories: 数据库
tags:
  - PostgreSQL
---

PostgreSQL 数据库提供了 `timestamp` 和 `timestamptz` 两种时间戳，它们的区别在于后者是带了时区信息，而前者没有时区信息。本文将对两种类型的时间戳进行分析。

<!--more-->

## 示例

我们先来看一个简单的示例。创建一个名为 `test` 的测试表，该表包含两个字段，分别为 `timestamp` 类型和 `timestamptz` 类型。

```sql
postgres=# CREATE TABLE test (t1 timestamp, t2 timestamptz);
CREATE TABLE
postgres=# \d test
                          Table "public.test"
 Column |            Type             | Collation | Nullable | Default
--------+-----------------------------+-----------+----------+---------
 t1     | timestamp without time zone |           |          |
 t2     | timestamp with time zone    |           |          |
```

接着我们在当前时区下插入一条记录。

```sql
postgres=# show timezone;
   TimeZone
---------------
 Asia/Shanghai
(1 row)

postgres=# INSERT INTO test SELECT t, t FROM now() t;
INSERT 0 1
postgres=# SELECT * FROM test;
             t1             |              t2
----------------------------+-------------------------------
 2023-03-10 10:38:33.718548 | 2023-03-10 10:38:33.718548+08
(1 row)
```

目前看来一切都正常，那么我们切换一个时区会发生什么情况呢？

```sql
postgres=# SET timezone TO 'Europe/Dublin';
SET
postgres=# SHOW timezone;
   TimeZone
---------------
 Europe/Dublin
(1 row)

postgres=# SELECT * FROM test;
             t1             |              t2
----------------------------+-------------------------------
 2023-03-10 10:38:33.718548 | 2023-03-10 02:38:33.718548+00
(1 row)
```

从上面可以看到，不带时区的时间戳在不同时区读取出来的时间是一样的，而带时区的时间戳则会在不同的时区下有不同的时间。

## 分析

Unix 时间戳是从 1970 年 1 月 1 日 UTC 的 Unix 纪元开始，我们可以通过 `extract` 函数查看 Unix 时间戳。

```bash
postgres=# SELECT extract(epoch from t1) ts1, extract(epoch from t2) ts2 FROM test;
        ts1        |        ts2
-------------------+-------------------
 1678444713.718548 | 1678415913.718548
(1 row)
```

PostgreSQL 对于时间戳类型是按值存储的，即它是以一个 8 字节的整数类型存储在磁盘上的。您可以使用下面的命令查看 `test` 表的物理存储（我已经切换到了 `PGDATA` 所在目录）。

```
postgres=# SELECT pg_relation_filepath('test'::regclass);
 pg_relation_filepath
----------------------
 base/5/16428
(1 row)

postgres=# \! hexdump -C base/5/16428
00000000  00 00 00 00 60 32 5d 01  00 00 00 00 1c 00 d8 1f  |....`2].........|
00000010  00 20 04 20 00 00 00 00  d8 9f 50 00 00 00 00 00  |. . ......P.....|
00000020  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00001fd0  00 00 00 00 00 00 00 00  fa 02 00 00 00 00 00 00  |................|
00001fe0  00 00 00 00 00 00 00 00  01 00 02 00 00 09 18 00  |................|
00001ff0  14 d3 b7 21 88 99 02 00  14 b3 1a 6d 81 99 02 00  |...!.......m....|
00002000
```

我们将最后两个 8 字节转换为整数分别为 `0x0002998821b7d314 = 731759913718548`，`0x000299816d1ab314 = 731731113718548`（小端序），这里看到的值与我们获取到的时间戳不一致。这是因为 PostgreSQL 在存储时间戳时对其进行了转换，PostgreSQL 将 Unix 时间戳转换为了 PostgreSQL 的时间戳（基于 2000 年 1 月 1 日），同时保存到微秒级别，您可以在 `GetCurrentTimestap()` 函数中看到。

```c
/*
 * GetCurrentTimestamp -- get the current operating system time
 *
 * Result is in the form of a TimestampTz value, and is expressed to the
 * full precision of the gettimeofday() syscall
 */
TimestampTz
GetCurrentTimestamp(void)
{
    TimestampTz result;
    struct timeval tp;

    gettimeofday(&tp, NULL);

    result = (TimestampTz) tp.tv_sec -
        ((POSTGRES_EPOCH_JDATE - UNIX_EPOCH_JDATE) * SECS_PER_DAY);
    result = (result * USECS_PER_SEC) + tp.tv_usec;

    return result;
}
```

其中使用到的宏定义如下所示：

```c
/* Julian-date equivalents of Day 0 in Unix and Postgres reckoning */
#define UNIX_EPOCH_JDATE        2440588 /* == date2j(1970, 1, 1) */
#define POSTGRES_EPOCH_JDATE    2451545 /* == date2j(2000, 1, 1) */

#define SECS_PER_DAY    86400

#define USECS_PER_SEC   INT64CONST(1000000)
```

有了这些内容，我们便可以通过物理存储的 PostgreSQL 时间戳信息推算出 Unix 时间戳。

```
731759913718548 / 1000000.0 + (2451545 - 2440588) * 86400 = 1678444713.718548
731731113718548 / 1000000.0 + (2451545 - 2440588) * 86400 = 1678415913.718548
```

这与我们通过 SQL 计算的结果完全吻合。这里解释了物理存储，还有一个问题是我们插入的是相同的时间戳，为什么在底层存储的时候却变成了两个不同的时间戳呢？

这里我们可以肯定是和 `timestamp` 和 `timestamptz` 的类型有关了。那么 PostgreSQL 是什么时候做的转换呢？
timestamp2tm

通过调试分析，我注意到在 `ExecProject()` 函数在根据投影信息生成一个元组时调用了 `timestamptz_timestamp()` 函数将一个带时区的时间戳转换为了**不带**时区的时间戳。在上面的示例中即将带时区的 PostgreSQL 时间戳 `731731113718548` 转换为了**不带**时区的 PostgreSQL 时间戳 `731759913718548`，由于我在东八取，因此要比 GMT 时区快 8 个小时 `(731759913718548 - 731731113718548) / (60 * 60 * 1000000) = 8` 正好是 8 个小时（时间戳是基于 UTC 的，它与 GMT 时区重合，因此需要获取会话的时区对其进行调整）。我们在来看看 `timestamptz_timestamp()` 函数的实现。

```c
/* timestamptz_timestamp()
 * Convert timestamp at GMT to local timestamp
 */
Datum
timestamptz_timestamp(PG_FUNCTION_ARGS)
{
    TimestampTz timestamp = PG_GETARG_TIMESTAMPTZ(0);

    PG_RETURN_TIMESTAMP(timestamptz2timestamp(timestamp));
}

static Timestamp
timestamptz2timestamp(TimestampTz timestamp)
{
    Timestamp   result;
    struct pg_tm tt,
               *tm = &tt;
    fsec_t      fsec;
    int         tz;

    if (TIMESTAMP_NOT_FINITE(timestamp))
        result = timestamp;
    else
    {
        if (timestamp2tm(timestamp, &tz, tm, &fsec, NULL, NULL) != 0)
            ereport(ERROR,
                    (errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
                     errmsg("timestamp out of range")));
        if (tm2timestamp(tm, fsec, NULL, &result) != 0)
            ereport(ERROR,
                    (errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
                     errmsg("timestamp out of range")));
    }
    return result;
}
```

其中核心的函数是 `timestamp2tm()` 和 `tm2timestamp()` 这两个函数。`timestamp2tm()` 函数将 PostgreSQL 时间戳转换为 POSIX 时间结构，它会根据会话级别的 `timezone` 来转换时间，随后在通过 `tm2timestamp()` 将 POSIX 时间结构转换为 PostgreSQL 时间戳。

## 参考

[1] https://www.unixtimestamp.com/
[2] https://www.timeanddate.com/time/gmt-utc-time.html
[3] https://www.postgresql.org/docs/current/datatype-datetime.html

<div class="just-for-fun">
笑林广记 - 问路

一近视眼迷路，见道旁石上栖歇一鸦，疑是人也，遂再三诘之。
少顷，鸦飞去，其人曰：“我问你不答应，你的帽子被风吹去了，我也不对你说。”
</div>
