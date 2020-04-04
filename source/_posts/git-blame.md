---
title: "初识 git blame"
date: 2019-12-14 11:25:05 +0800
category: Misc
tags: git
---

最近在向 PostgreSQL 社区提交 patch 时，发现其维护者很快就定位到了代码何时由谁更改了，作为一个萌新，我也不好意思问:(，只能自己下来查找资料，经过一番搜索，发现了 `git blame` 这个命令。

<!-- more -->

## git blame

Git 的 blame 子命令可以显示一个文件每一行最后的修改作者及信息。由此，我们便可以快速定位代码的修改。

例如，我们可以通过如下命令来查看文件的更改。

``` shell
$ git blame ./src/backend/utils/adt/timestamp.c
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000    1) /*-------------------------------------------------------------------------
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000    2)  *
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000    3)  * timestamp.c
cc26ea9fe2e (Peter Eisentraut   2013-04-20 11:04:41 -0400    4)  *        Functions for the built-in SQL types "timestamp" and "interval".
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000    5)  *
97c39498e5c (Bruce Momjian      2019-01-02 12:44:25 -0500    6)  * Portions Copyright (c) 1996-2019, PostgreSQL Global Development Group
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000    7)  * Portions Copyright (c) 1994, Regents of the University of California
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000    8)  *
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000    9)  *
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000   10)  * IDENTIFICATION
9f2e2113869 (Magnus Hagander    2010-09-20 22:08:53 +0200   11)  *        src/backend/utils/adt/timestamp.c
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000   12)  *
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000   13)  *-------------------------------------------------------------------------
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000   14)  */
18952f67446 (Tom Lane           2000-05-29 01:59:17 +0000   15)
18952f67446 (Tom Lane           2000-05-29 01:59:17 +0000   16) #include "postgres.h"
18952f67446 (Tom Lane           2000-05-29 01:59:17 +0000   17)
4bc578eb838 (Marc G. Fournier   1997-04-03 19:58:11 +0000   18) #include <ctype.h>
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000   19) #include <math.h>
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000   20) #include <limits.h>
dd4eea257b7 (Neil Conway        2005-06-30 03:48:58 +0000   21) #include <sys/time.h>
...
```

是不是觉得太长了不方便查看，没关系，`git blame` 还提供了参数可以控制文件中查看的内容。例如查看文件第 20 行到 40 行之间的改动。

``` shell
$ git blame -L 20,40 ./src/backend/utils/adt/timestamp.c
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000 20) #include <limits.h>
dd4eea257b7 (Neil Conway        2005-06-30 03:48:58 +0000 21) #include <sys/time.h>
cb292206c5c (Peter Eisentraut   2000-07-12 22:59:15 +0000 22)
18952f67446 (Tom Lane           2000-05-29 01:59:17 +0000 23) #include "access/xact.h"
5cabcfccce4 (Tom Lane           2002-08-26 17:54:02 +0000 24) #include "catalog/pg_type.h"
df1a699e5ba (Tom Lane           2017-04-05 23:51:27 -0400 25) #include "common/int128.h"
b6d15590f72 (Tom Lane           2008-05-04 23:19:24 +0000 26) #include "funcapi.h"
30f609484d0 (Tom Lane           2003-05-12 23:08:52 +0000 27) #include "libpq/pqformat.h"
8507ddb9c63 (Thomas G. Lockhart 1997-07-01 00:22:46 +0000 28) #include "miscadmin.h"
b8a18ad4850 (Noah Misch         2015-03-01 13:22:34 -0500 29) #include "nodes/makefuncs.h"
c13897983a0 (Robert Haas        2012-02-08 09:33:02 -0500 30) #include "nodes/nodeFuncs.h"
1fb57af9206 (Tom Lane           2019-02-09 18:08:48 -0500 31) #include "nodes/supportnodes.h"
0bd61548ab8 (Tom Lane           2004-05-07 00:24:59 +0000 32) #include "parser/scansup.h"
bec98a31c55 (Tom Lane           2000-07-17 03:05:41 +0000 33) #include "utils/array.h"
94094c05697 (Marc G. Fournier   1997-03-14 05:58:13 +0000 34) #include "utils/builtins.h"
b5f7cff84f5 (Tom Lane           2005-06-29 22:51:57 +0000 35) #include "utils/datetime.h"
6bf0bc842bd (Tomas Vondra       2018-07-29 03:30:48 +0200 36) #include "utils/float.h"
b5f7cff84f5 (Tom Lane           2005-06-29 22:51:57 +0000 37)
e303a2dbe8c (Tom Lane           2002-09-21 19:52:41 +0000 38) /*
e303a2dbe8c (Tom Lane           2002-09-21 19:52:41 +0000 39)  * gcc's -ffast-math switch breaks routines that expect exact results from
a536b2dd80f (Bruce Momjian      2005-07-21 03:56:25 +0000 40)  * expressions like timeval / SECS_PER_HOUR, where timeval is double.
```

我们还可以通过指定偏移的方式来显示。例如，下面的命令可以到达和上面的命令相同的效果。

``` shell
$ git blame -L 20,+21 ./src/backend/utils/adt/timestamp.c
$ git blame -L 40,-21 ./src/backend/utils/adt/timestamp.c
```

如果我们向查看一个函数的变更呢？是否需要先在源文件中查看函数的起止行，然后在指定行号呢？答案当然是 NO。我们可以通过指定函数名来完成这一需求。例如，我想要查看 `timestamp_part` 函数的更改。

``` shell
$ git blame -L :timestamp_part ./src/backend/utils/adt/timestamp.c
ae526b40703 (Tom Lane           2000-06-09 01:11:16 +0000 4522) timestamp_part(PG_FUNCTION_ARGS)
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000 4523) {
220db7ccd8c (Tom Lane           2008-03-25 22:42:46 +0000 4524)         text       *units = PG_GETARG_TEXT_PP(0);
1dc34982511 (Bruce Momjian      2005-10-15 02:49:52 +0000 4525)         Timestamp       timestamp = PG_GETARG_TIMESTAMP(1);
ae526b40703 (Tom Lane           2000-06-09 01:11:16 +0000 4526)         float8          result;
a70e13a39ec (Tom Lane           2016-03-16 19:09:04 -0400 4527)         Timestamp       epoch;
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000 4528)         int                     type,
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000 4529)                                 val;
0bd61548ab8 (Tom Lane           2004-05-07 00:24:59 +0000 4530)         char       *lowunits;
547df0cc853 (Thomas G. Lockhart 2002-04-21 19:52:18 +0000 4531)         fsec_t          fsec;
b6b71b85bc4 (Bruce Momjian      2004-08-29 05:07:03 +0000 4532)         struct pg_tm tt,
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000 4533)                            *tm = &tt;
41f1f5b76ad (Thomas G. Lockhart 2000-02-16 17:26:26 +0000 4534)
220db7ccd8c (Tom Lane           2008-03-25 22:42:46 +0000 4535)         lowunits = downcase_truncate_identifier(VARDATA_ANY(units),
220db7ccd8c (Tom Lane           2008-03-25 22:42:46 +0000 4536)                                                                                         VARSIZE_ANY_EXHDR(units),
0bd61548ab8 (Tom Lane           2004-05-07 00:24:59 +0000 4537)                                                                                         false);
0bd61548ab8 (Tom Lane           2004-05-07 00:24:59 +0000 4538)
0bd61548ab8 (Tom Lane           2004-05-07 00:24:59 +0000 4539)         type = DecodeUnits(0, lowunits, &val);
0bd61548ab8 (Tom Lane           2004-05-07 00:24:59 +0000 4540)         if (type == UNKNOWN_FIELD)
0bd61548ab8 (Tom Lane           2004-05-07 00:24:59 +0000 4541)                 type = DecodeSpecial(0, lowunits, &val);
0bd61548ab8 (Tom Lane           2004-05-07 00:24:59 +0000 4542)
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4543)         if (TIMESTAMP_NOT_FINITE(timestamp))
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4544)         {
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4545)                 result = NonFiniteTimestampTzPart(type, val, lowunits,
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4546)                                                                                   TIMESTAMP_IS_NOBEGIN(timestamp),
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4547)                                                                                   false);
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4548)                 if (result)
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4549)                         PG_RETURN_FLOAT8(result);
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4550)                 else
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4551)                         PG_RETURN_NULL();
647d87c56ab (Tom Lane           2016-01-21 22:26:20 -0500 4552)         }
...
```

您以为这就完了么？Too yong too simple. `git blame` 的 `-L` 参数还支持正则表达式。我们可以是下面的正则表达式方式实现上面的需求。

``` shell
$ git blame -L '/^timestamp_part(/,/^}$/' ./src/backend/utils/adt/timestamp.c
```

暂时先整理到此处，更多的用法可以查看[文档](https://git-scm.com/docs/git-blame)或帮助手册 (`man git-blame`)。

## 参考

[1] https://git-scm.com/docs/git-blame
