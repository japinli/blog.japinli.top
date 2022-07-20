---
title: "Psql 内存泄漏"
date: 2022-07-20 22:40:59 +0800
categories: 数据库
tags:
  - PostgreSQL
  - psql
---

{% asset_img memory-leak.jpeg %}

今天在邮件列表中发现一个关于 [psql 内存泄露的问题](https://www.postgresql.org/message-id/OS0PR01MB61136CE4A6A21950B82202F8FB8F9%40OS0PR01MB6113.jpnprd01.prod.outlook.com)，经过测试，确实存在内存泄露。同时，我在查看周围的代码时，还发现其它地方也存在类似的内存泄漏。本文简要记录一下该问题。

<!--more-->

内存泄露发生在 `validateSQLNamePattern()` 函数中，其函数定义如下所示：

```c
static bool
validateSQLNamePattern(PQExpBuffer buf, const char *pattern, bool have_where,
                       bool force_escape, const char *schemavar,
                       const char *namevar, const char *altnamevar,
                       const char *visibilityrule, bool *added_clause,
                       int maxparts)
{
    PQExpBufferData dbbuf;
    int         dotcnt;
    bool        added;

    initPQExpBuffer(&dbbuf);
    added = processSQLNamePattern(pset.db, buf, pattern, have_where, force_escape,
                                  schemavar, namevar, altnamevar,
                                  visibilityrule, &dbbuf, &dotcnt);
    if (added_clause != NULL)
        *added_clause = added;

    if (dotcnt >= maxparts)
    {
        pg_log_error("improper qualified name (too many dotted names): %s",
                     pattern);
        termPQExpBuffer(&dbbuf);
        return false;
    }

    if (maxparts > 1 && dotcnt == maxparts - 1)
    {
        if (PQdb(pset.db) == NULL)
        {
            pg_log_error("You are currently not connected to a database.");
            return false;
        }
        if (strcmp(PQdb(pset.db), dbbuf.data) != 0)
        {
            pg_log_error("cross-database references are not implemented: %s",
                         pattern);
            return false;
        }
    }
    return true;
}
```

相信您一眼就能发现哪儿出现了内存泄露。

`initPQExpBuffer()` 函数将调用 `malloc()` 函数分配 512 字节的内存。该函数仅在 `dotcnt >= maxparts` 时释放了其分配的内存，后续忽略了该内存的释放，从而导致内存泄露。我们可以通过诸如 `\dRp` 命令来测试。

由于每次泄露的内存比较小，为了能明显的感知内存泄露，我们可以通过 vim 来创建一个包含 10000 条 `\dRp` 的 SQL 文件，随后使用 psql 连接数据库并执行该文件，同时，使用 `top` 命令和 `/proc/pid/status` 观察内存变化。

```bash
$ top -p $pid
```

```bash
$ while true; do cat /proc/$pid/status | grep -i rss; sleep 1; done
```

注意，`$pid` 为 psql 进程的 ID。

通过上述操作可以看到内存会一直小幅度上涨，并且不会被释放。我们尝试应用下面的补丁，可以避免内存泄露。

```diff
diff --git a/src/bin/psql/describe.c b/src/bin/psql/describe.c
index 88d92a08ae..0ce38e4b4c 100644
--- a/src/bin/psql/describe.c
+++ b/src/bin/psql/describe.c
@@ -6023,15 +6023,18 @@ validateSQLNamePattern(PQExpBuffer buf, const char *pattern, bool have_where,
 		if (PQdb(pset.db) == NULL)
 		{
 			pg_log_error("You are currently not connected to a database.");
+			termPQExpBuffer(&dbbuf);
 			return false;
 		}
 		if (strcmp(PQdb(pset.db), dbbuf.data) != 0)
 		{
 			pg_log_error("cross-database references are not implemented: %s",
 						 pattern);
+			termPQExpBuffer(&dbbuf);
 			return false;
 		}
 	}
+	termPQExpBuffer(&dbbuf);
 	return true;
 }
```

当我们在重复上面的测试步骤，可以发现内存基本上不会发生变化。随后我又查看了 `psql/describe.c` 文件中关于 `validateSQLNamePattern()` 调用的地方，发现其也存在大量的内存泄露。主要集中在 `initPQExpBuffer()` 函数调用后，在错误情况下，忽略了该内存的释放。我们可以使用诸如 `\dRp .*fdkf.*` 的命令来进行测试。由于补丁内容比较大，就不展示了，在下面的参考链接中包含了该 patch。

## 参考

[1] https://www.postgresql.org/message-id/OS0PR01MB61136CE4A6A21950B82202F8FB8F9%40OS0PR01MB6113.jpnprd01.prod.outlook.com

**备注：**图片来源于 https://www.krwalters.com/2018/03/14/memory-leak-in-woodstock/。

<div class="just-for-fun">
笑林广记 - 春生帖

一财主不通文墨，谓友曰：“某人甚是欠通，清早来拜我，就写晚生帖。”
傍一监生曰：“这倒还差不远，好像这两日秋天拜客，竟有写春生帖子的哩。”
</div>
