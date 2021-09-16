---
title: "PostgreSQL 修改配置参数"
date: 2020-06-09 21:12:39 +0800
category: 数据库
tags:
  - PostgreSQL
---

今天在使用 `ALTER SYSTEM` 来修改 PostgreSQL 参数时遇到无法启动数据库的问题。如下所示：

```
postgres=# ALTER SYSTEM SET shared_preload_libraries TO 'pg_buffercache,passwordcheck';
ALTER SYSTEM
postgres=# \q
$ pg_ctl restart
waiting for server to shut down.... done
server stopped
waiting for server to start....postgres: could not access directory "/Users/japinli/Codes/postgresql/pg/data": No such file or directory
Run initdb or pg_basebackup to initialize a PostgreSQL data directory.
 stopped waiting
pg_ctl: could not start server
Examine the log output.
```

你是否也遇到了这样的问题呢？其实这都是由于我们先入为主的思想导致的，`ALTER SYSTEM` 支持以逗号分割的列表，而这类参数的修改不需要使用引号。因此，正确的使用方式如下：

```
ALTER SYSTEM SET shared_preload_libraries TO pg_buffercache, passwordcheck;
```

<!-- more -->

## 分析

首先我们看看 pg_ctl 在启动时是如何加载 `shared_preload_libraries` 配置文件的。这里我们需要注意的是 pg_ctl 最终还是调用 postgres 来启动。通过分析我们可以发现 `shared_preload_libraries` 参数是在 `PostmasterMain()` 函数中调用 `process_shared_preload_libraries()` 来处理的，该函数定义如下：

``` C
void
process_shared_preload_libraries(void)
{
    process_shared_preload_libraries_in_progress = true;
    load_libraries(shared_preload_libraries_string,
                   "shared_preload_libraries",
                   false);
    process_shared_preload_libraries_in_progress = false;
}
```

从上面可以看到，`shared_preload_libraries` 是通过 `load_libraries()` 函数处理的，`load_libraries()` 函数则是通过 `SplitDirectoriesString()` 函数来处理的。


``` C
bool
SplitDirectoriesString(char *rawstring, char separator,
                       List **namelist)
{
    char       *nextp = rawstring;
    bool        done = false;

    *namelist = NIL;

    while (scanner_isspace(*nextp))
        nextp++;                /* skip leading whitespace */

    if (*nextp == '\0')
        return true;            /* allow empty string */

    /* At the top of the loop, we are at start of a new directory. */
    do
    {
        char       *curname;
        char       *endp;

        if (*nextp == '"')
        {
            /* Quoted name --- collapse quote-quote pairs */
            curname = nextp + 1;
            for (;;)
            {
                endp = strchr(nextp + 1, '"');
                if (endp == NULL)
                    return false;   /* mismatched quotes */
                if (endp[1] != '"')
                    break;      /* found end of quoted name */
                /* Collapse adjacent quotes into one quote, and look again */
                memmove(endp, endp + 1, strlen(endp));
                nextp = endp;
            }
            /* endp now points at the terminating quote */
            nextp = endp + 1;
        }
        else
        {
            /* Unquoted name --- extends to separator or end of string */
            curname = endp = nextp;
            while (*nextp && *nextp != separator)
            {
                /* trailing whitespace should not be included in name */
                if (!scanner_isspace(*nextp))
                    endp = nextp + 1;
                nextp++;
            }
            if (curname == endp)
                return false;   /* empty unquoted name not allowed */
        }

        while (scanner_isspace(*nextp))
            nextp++;            /* skip trailing whitespace */

        if (*nextp == separator)
        {
            nextp++;
            while (scanner_isspace(*nextp))
                nextp++;        /* skip leading whitespace for next */
            /* we expect another name, so done remains false */
        }
        else if (*nextp == '\0')
            done = true;
        else
            return false;       /* invalid syntax */

        /* Now safe to overwrite separator with a null */
        *endp = '\0';

        /* Truncate path if it's overlength */
        if (strlen(curname) >= MAXPGPATH)
            curname[MAXPGPATH - 1] = '\0';

        /*
         * Finished isolating current name --- add it to list
         */
        curname = pstrdup(curname);
        canonicalize_path(curname);
        *namelist = lappend(*namelist, curname);

        /* Loop back if we didn't reach end of string */
    } while (!done);

    return true;
}
```

从上面的 22-38 行代码，我们可以看到，postgres 在处理带有双引号的内容是将其作为一个整体来处理的，因此，我们的 `shared_preload_libraries` 配置无法通过。

关于 `shared_preload_libraries` 的处理流程如下所示：

```
-> PostmasterMain()
    |
    +-> process_shared_preload_libraries()
         |
         +-> load_libraries()
              |
              +-> SplitDirectoriesString()
```

那么为什么 `ALTER SYSTEM` 在写入时要加上双引号呢？我们先看看 `share_preload_libraries` 参数的相关设置。

``` C
    {
        {"shared_preload_libraries", PGC_POSTMASTER, CLIENT_CONN_PRELOAD,
            gettext_noop("Lists shared libraries to preload into server."),
            NULL,
            GUC_LIST_INPUT | GUC_LIST_QUOTE | GUC_SUPERUSER_ONLY
        },
        &shared_preload_libraries_string,
        "",
        NULL, NULL, NULL
    },
```

参数 `shared_preload_libraries` 的 `flag` 为 `GUC_LIST_INPUT | GUC_LIST_QUOTE | GUC_SUPERUSER_ONLY`，而我们使用的 `'pg_buffercache,passwordcheck'` 是作为一个整体，而不是 LIST 来处理的，因此，在写入是由于有特殊的分割符，所以就需要加上双引号，从而导致错误。

关于 `ALTER SYSTEM` 命令的处理可以查看 `gram.y` 中的 `AlterSystemStmt` 定义，随后接着分析 `AlterSystemSetConfigFile()` 函数，其处理流程大致如下：

```
-> AlterSystemSetConfigFile()
    |
    +-> ExtractSetVariableArgs()
         |
         +-> ExtractSetVariableArgs()
              |
              +-> flatten_set_variable_args()
```

## 参考

[1] https://www.postgresql.org/docs/10/sql-altersystem.html
