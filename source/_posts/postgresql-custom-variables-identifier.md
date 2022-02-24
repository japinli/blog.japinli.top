---
title: "PostgreSQL 自定义参数的标识符问题"
date: 2022-02-24 21:00:40 +0800
categories: 数据库
tags:
  - BUG
  - PG14
  - PostgreSQL
---

PostgreSQL 提供了自定义参数的功能，您可以使用 [`SET`][] 或 [`set_config()`][] 函数来定义参数，本文介绍一下在 PG14（14.1 和 14.2）中引入的关于自定义参数标识符的的问题 [BUG #17415][]。

<!--more-->

## 现象

既然说在 PG13 上可以正常工作，那么我们先测试 PG13，看看具体是什么样的。

```sql
postgres=# SELECT version();
                                               version
------------------------------------------------------------------------------------------------------
 PostgreSQL 13.6 on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 9.3.0-17ubuntu1~20.04) 9.3.0, 64-bit
(1 row)

postgres=# SET custom._my_guc = 50;
SET
postgres=# SHOW custom._my_guc;
 custom._my_guc
----------------
 50
(1 row)
```

接着，我们在 PG14 上面来进行测试。

```sql
postgres=# SELECT version();
                                               version
------------------------------------------------------------------------------------------------------
 PostgreSQL 14.2 on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 9.3.0-17ubuntu1~20.04) 9.3.0, 64-bit
(1 row)

postgres=# SET custom._my_guc = 50;
ERROR:  invalid configuration parameter name "custom._my_guc"
DETAIL:  Custom parameter names must be two or more simple identifiers separated by dots.
```

从上面可以看到，PG14 中以 `_` 开头的自定义变量将触发语法错误。

在 PostgreSQL 中，参数可以包含一个或多个[标识符][]，多个标识符由 `.` 连接。而标识符则是由字母（`a-z` 以及带变音符号的字母和非拉丁字母）和 `_` 组成的，按照这个说法那么以 `_` 开头是可以接受的，为什么触发了语法错误呢？

通过错误信息我们可以定位到 `guc.c` 这个文件中的 `find_option()` 函数，如下所示：

```c
static struct config_generic *
find_option(const char *name, bool create_placeholders, bool skip_errors,
            int elevel)
{
    [...]

    if (create_placeholders)
    {
        /*
         * Check if the name is valid, and if so, add a placeholder.  If it
         * doesn't contain a separator, don't assume that it was meant to be a
         * placeholder.
         */
        if (strchr(name, GUC_QUALIFIER_SEPARATOR) != NULL)
        {
            if (valid_custom_variable_name(name))
                return add_placeholder_variable(name, elevel);
            /* A special error message seems desirable here */
            if (!skip_errors)
                ereport(elevel,
                        (errcode(ERRCODE_INVALID_NAME),
                         errmsg("invalid configuration parameter name \"%s\"",
                                name),
                         errdetail("Custom parameter names must be two or more simple identifiers separated by dots.")));
            return NULL;
        }
    }

    [...]
}
```

从上面的逻辑可以看到，当 `valid_custom_variable_name()` 函数验证失败之后才有可能进入到下面的错误处理中，因此，可以断定问题出在 `valid_custom_variable_name()` 函数中，接着我们看看该函数的定义。

```c
/*
 * Decide whether a proposed custom variable name is allowed.
 *
 * It must be two or more identifiers separated by dots, where the rules
 * for what is an identifier agree with scan.l.  (If you change this rule,
 * adjust the errdetail in find_option().)
 */
static bool
valid_custom_variable_name(const char *name)
{
    bool        saw_sep = false;
    bool        name_start = true;

    for (const char *p = name; *p; p++)
    {
        if (*p == GUC_QUALIFIER_SEPARATOR)
        {
            if (name_start)
                return false;   /* empty name component */
            saw_sep = true;
            name_start = true;
        }
        else if (strchr("ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                        "abcdefghijklmnopqrstuvwxyz", *p) != NULL ||
                 IS_HIGHBIT_SET(*p))
        {
            /* okay as first or non-first character */
            name_start = false;
        }
        else if (!name_start && strchr("0123456789_$", *p) != NULL)
             /* okay as non-first character */ ;
        else
            return false;
    }
    if (name_start)
        return false;           /* empty name component */
    /* OK if we found at least one separator */
    return saw_sep;
}
```

上面的代码不是特别复杂，该函数是用于检查自定义参数是否合法的，自定义参数必须是由 `.` 分割的两个或多个标识符，该标识符与 `scan.l` 中的标识符相同。那么我们看看 `scan.l` 中是如何定义标识符的。

```lex
ident_start     [A-Za-z\200-\377_]
ident_cont      [A-Za-z\200-\377_0-9\$]

identifier      {ident_start}{ident_cont}*
```

这与上面提到的标识符定义相吻合。`ident_start` 中包含了 `_`，然而在 `valid_custom_variable_name()` 函数中，处理标识符的第一个字符（循环中第一个 `eles if` 语句）时忽略了 `_`，因此导致语法错误。我们可以利用 `git blame` 来查看该函数的更改记录。

```shell
$ git blame -L :valid_custom_variable_name $(find . -name guc.c)
[...]
3db826bd55c (Tom Lane      2021-04-07 11:22:22 -0400 5473)              else if (strchr("ABCDEFGHIJKLMNOPQRSTUVWXYZ"
3db826bd55c (Tom Lane      2021-04-07 11:22:22 -0400 5474)                                              "abcdefghijklmnopqrstuvwxyz", *p) != NULL ||
3db826bd55c (Tom Lane      2021-04-07 11:22:22 -0400 5475)                               IS_HIGHBIT_SET(*p))
3db826bd55c (Tom Lane      2021-04-07 11:22:22 -0400 5476)              {
3db826bd55c (Tom Lane      2021-04-07 11:22:22 -0400 5477)                      /* okay as first or non-first character */
3db826bd55c (Tom Lane      2021-04-07 11:22:22 -0400 5478)                      name_start = false;
3db826bd55c (Tom Lane      2021-04-07 11:22:22 -0400 5479)              }
[...]
```

3db826bd55c 这个提交导致了这个问题，通过测试 3db826bd55c 之前的一个记录发现 `SET custom._my_guc = 50;` 可以正常使用，而这个提交之后的便出现语法错误。

## 解决方案

这个问题相对比较简单，主要就是 `_` 这个字符放错了位置，我们将其从第二个 `else if` 移到第一个中即可解决。

```diff
diff --git a/src/backend/utils/misc/guc.c b/src/backend/utils/misc/guc.c
index e4afd07bfe..bf7ec0d466 100644
--- a/src/backend/utils/misc/guc.c
+++ b/src/backend/utils/misc/guc.c
@@ -5474,13 +5474,13 @@ valid_custom_variable_name(const char *name)
                        name_start = true;
                }
                else if (strchr("ABCDEFGHIJKLMNOPQRSTUVWXYZ"
-                                               "abcdefghijklmnopqrstuvwxyz", *p) != NULL ||
+                                               "abcdefghijklmnopqrstuvwxyz_", *p) != NULL ||
                                 IS_HIGHBIT_SET(*p))
                {
                        /* okay as first or non-first character */
                        name_start = false;
                }
-               else if (!name_start && strchr("0123456789_$", *p) != NULL)
+               else if (!name_start && strchr("0123456789$", *p) != NULL)
                         /* okay as non-first character */ ;
                else
                        return false;
```

## 参考

[1] https://www.postgresql.org/docs/14/sql-set.html
[2] https://www.postgresql.org/docs/14/functions-admin.html#FUNCTIONS-ADMIN-SET
[3] https://www.postgresql.org/docs/14/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS
[4] https://www.postgresql.org/message-id/17415-ebdb683d7e09a51c%40postgresql.org

<div class="just-for-fun">
笑林广记 - 书低

一生赁僧房读书，每日游玩，午后归房。
呼童取书来，童持《文选》，视之曰低；持《汉书》，视之曰低；又持《史记》，视之曰低。
僧大诧曰：“此三书熟其一，足称饱学，俱云低何也？”
生曰：“我要睡，取书作枕头耳。”
</div>

[`SET`]: https://www.postgresql.org/docs/14/sql-set.html
[`set_config()`]: https://www.postgresql.org/docs/14/functions-admin.html#FUNCTIONS-ADMIN-SET
[BUG #17415]: https://www.postgresql.org/message-id/17415-ebdb683d7e09a51c%40postgresql.org
[标识符]: https://www.postgresql.org/docs/14/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS
