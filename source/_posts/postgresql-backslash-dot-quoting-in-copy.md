---
title: "PostgreSQL COPY CSV 中的 \\. 引用问题"
date: 2022-09-25 19:18:48
categories: 数据库
tags:
  - PostgreSQL
  - BUG
---

本文简要记录一个由 psql 提供的 `\copy` 元命令引发的错误，如下所示：

```sql
postgres=# \copy tbl FROM '/tmp/tbl.csv' WITH csv;
ERROR:  unterminated CSV quoted field
CONTEXT:  COPY tbl, line 1: ""
\.
"
```

<!--more-->

## 引子

当我们通过 `COPY` 命令导入数据是，PostgreSQL 默认使用 `\.` 作为数据的分隔符。

```sql
CREATE TABLE tbl (info text);
COPY tbl FROM stdin WITH csv;
>> hello world
>> \.
COPY 1
```

现在让我们来看看下面的示例。首先我们将表清空，然后在插入一条记录。

```sql
TRUNCATE tbl;
INSERT INTO tbl VALUES ('
\.
');
SELECT * FROM tbl;
```
```
 info
------
     +
 \.  +

(1 row)
```

接着我们将其导出到文件中。

```sql
COPY tbl TO '/tmp/tbl.csv' WITH csv;
```

查看 `/tmp/tbl.csv`，数据成功导出。

```bash
$ cat /tmp/tbl.csv
"
\.
"
```

PostgreSQL 支持 `COPY` 和 `\copy` 两种方式。`COPY` 的方式是在服务器端执行，而 `\copy` 是 psql 提供的命令，它是在客户端执行的。

```sql
COPY tbl FROM '/tmp/tbl.csv' WITH csv;
SELECT ctid, * FROM tbl;
```
```
 ctid  | info
-------+------
 (0,1) |     +
       | \.  +
       |
 (0,2) |     +
       | \.  +
       |
(2 rows)
```

当我们使用 `\copy` 导入时，数据将无法导入。

```sql
\copy tbl FROM '/tmp/tbl.csv' WITH csv;
```
```
ERROR:  unterminated CSV quoted field
CONTEXT:  COPY tbl, line 1: ""
\.
"
```

## 分析

通过调试，我们可以看到无论是 `COPY` 还是 `\copy`，最后都是执行 `CopyGetData()` 函数，其堆栈如下所示。

```gdb
(gdb) bt
#0  CopyGetData (cstate=0x555743f07418, databuf=0x555743faaf50, minread=1, maxread=65536)
    at /mnt/workspace/postgresql/build/../src/backend/commands/copyfromparse.c:247
#1  0x00005557425c18da in CopyLoadRawBuf (cstate=0x555743f07418)
    at /mnt/workspace/postgresql/build/../src/backend/commands/copyfromparse.c:627
#2  0x00005557425c1a95 in CopyLoadInputBuf (cstate=0x555743f07418)
    at /mnt/workspace/postgresql/build/../src/backend/commands/copyfromparse.c:689
#3  0x00005557425c2df2 in CopyReadLineText (cstate=0x555743f07418)
    at /mnt/workspace/postgresql/build/../src/backend/commands/copyfromparse.c:1186
#4  0x00005557425c29cf in CopyReadLine (cstate=0x555743f07418)
    at /mnt/workspace/postgresql/build/../src/backend/commands/copyfromparse.c:1044
#5  0x00005557425c1f20 in NextCopyFromRawFields (cstate=0x555743f07418,
    fields=0x7ffd4b9f0d88, nfields=0x7ffd4b9f0d64)
    at /mnt/workspace/postgresql/build/../src/backend/commands/copyfromparse.c:820
#6  0x00005557425c21f3 in NextCopyFrom (cstate=0x555743f07418, econtext=0x555743fbb298,
    values=0x555743fa69f8, nulls=0x555743fa6a00)
    at /mnt/workspace/postgresql/build/../src/backend/commands/copyfromparse.c:882
#7  0x00005557425bebfc in CopyFrom (cstate=0x555743f07418)
    at /mnt/workspace/postgresql/build/../src/backend/commands/copyfrom.c:859
#8  0x00005557425bb88d in DoCopy (pstate=0x555743f01840, stmt=0x555743ee1518,
    stmt_location=0, stmt_len=29, processed=0x7ffd4b9f11a0)
    at /mnt/workspace/postgresql/build/../src/backend/commands/copy.c:298
#9  0x0000555742905c21 in standard_ProcessUtility (pstmt=0x555743ee18e0,
    queryString=0x555743ee09d0 "COPY  tbl FROM STDIN WITH csv;", readOnlyTree=false,
    context=PROCESS_UTILITY_TOPLEVEL, params=0x0, queryEnv=0x0, dest=0x555743ee19d0,
    qc=0x7ffd4b9f1510)
    at /mnt/workspace/postgresql/build/../src/backend/tcop/utility.c:742
#10 0x00005557429055b9 in ProcessUtility (pstmt=0x555743ee18e0,
    queryString=0x555743ee09d0 "COPY  tbl FROM STDIN WITH csv;", readOnlyTree=false,
    context=PROCESS_UTILITY_TOPLEVEL, params=0x0, queryEnv=0x0, dest=0x555743ee19d0,
    qc=0x7ffd4b9f1510)
    at /mnt/workspace/postgresql/build/../src/backend/tcop/utility.c:530
```

函数 `CopyGetData()` 将根据数据的来源不同获取数据，具体来说，上面的 `COPY` 和 `\copy` 两条语句的数据来源分别为 `COPY_FILE` 和 `COPY_FRONTEND`。`COPY_FILE` 的方式是读本地文件（服务器端的），而 `COPY_FRONTEND` 则是读取客户端的数据（由 `pq_getmessage()` 函数完成）。

现在，我们可以将问题范围的缩小到 psql 端了。那么我们看看 psql 端是如何处理 `\copy` 命令。其执行的堆栈信息如下所示。

```gdb
#0  handleCopyIn (conn=0x5618b20ac2b0, copystream=0x5618b20b5390, isbinary=false,
    res=0x7ffcd76cf5b0) at /mnt/workspace/postgresql/build/../src/bin/psql/copy.c:514
#1  0x00005618b053aa9d in HandleCopyResult (resultp=0x7ffcd76cf608)
    at /mnt/workspace/postgresql/build/../src/bin/psql/common.c:939
#2  0x00005618b053bc79 in ExecQueryAndProcessResults (
    query=0x5618b20da760 "COPY  tbl FROM STDIN WITH csv;", elapsed_msec=0x7ffcd76cf698,
    svpt_gone_p=0x7ffcd76cf68c, is_watch=false, opt=0x0, printQueryFout=0x0)
    at /mnt/workspace/postgresql/build/../src/bin/psql/common.c:1565
#3  0x00005618b053b19f in SendQuery (
    query=0x5618b20da760 "COPY  tbl FROM STDIN WITH csv;")
    at /mnt/workspace/postgresql/build/../src/bin/psql/common.c:1172
#4  0x00005618b053e4e0 in do_copy (
    args=0x5618b20da4c0 "tbl FROM '/tmp/tbl.csv' WITH csv;")
```

从上面的信息我们可以得知，`\copy` 命令被转换成 `COPY ... FROM STDIN WITH csv;`，随后在 `handleCopyIn()` 函数中读取文件内容并发送到服务器端。

```c
bool
handleCopyIn(PGconn *conn, FILE *copystream, bool isbinary, PGresult **res)
{
    [...]
            fgresult = fgets(&buf[buflen], COPYBUFSIZ - buflen, copystream);

            sigint_interrupt_enabled = false;

            if (!fgresult)
                copydone = true;
            else
            {
                int         linelen;

                linelen = strlen(fgresult);
                buflen += linelen;

                /* current line is done? */
                if (buf[buflen - 1] == '\n')
                {
                    /* check for EOF marker, but not on a partial line */
                    if (at_line_begin)
                    {
                        /*
                         * This code erroneously assumes '\.' on a line alone
                         * inside a quoted CSV string terminates the \copy.
                         * https://www.postgresql.org/message-id/E1TdNVQ-0001ju-GO@wrigleys.postgresql.org
                         */
                        if ((linelen == 3 && memcmp(fgresult, "\\.\n", 3) == 0) ||
                            (linelen == 4 && memcmp(fgresult, "\\.\r\n", 4) == 0))
                        {
                            copydone = true;
                        }
                    }

                    if (copystream == pset.cur_cmd_source)
                    {
                        pset.lineno++;
                        pset.stmt_lineno++;
                    }
                    at_line_begin = true;
                }
                else
                    at_line_begin = false;
            }
    [...]
}
```

从上面的代码中，我们可以看到，psql 中的 `\copy` 命令是按行读取（fgets() 函数），然后判断是否为 `\.`，若是则代表结束，它无法处理当前内容是否在引号内，因此，psql 只发送了部分数据到服务器从而导致了错误。

下面是 Tom Lane 对于这个问题的看法。大意就是在文档中添加一个警告事项。

> A documentation warning might be the appropriate response.  I don't see any plausible way for psql to actually fix the problem, short of a protocol change to allow the backend to tell it how the data stream is going to be parsed.

## 参考

[1] https://www.postgresql.org/message-id/flat/E1TdNVQ-0001ju-GO%40wrigleys.postgresql.org
[2] https://www.postgresql.org/message-id/10e3eff6-eb04-4b3f-aeb4-b920192b977a%40manitou-mail.org

<div class="just-for-fun">
笑林广记 - 训子

富翁子不识字，人劝以延师训子。先学一字是一画，次二字是二画，次三字三画。
其子便欣然投笔告父曰：“儿已都晓字义，何用师为？”
父喜之乃谢去。一日父欲招万姓者饮，命子晨起治状，至午不见写成。
父往询之，子恚曰：“姓亦多矣，如何偏姓万，自早至今才得五百画哩！”
</div>
