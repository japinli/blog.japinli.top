---
title: "PostgreSQL 自定义系统函数"
date: 2019-11-25 21:32:48 +0800
category: Database
tags:
  - PostgreSQL
  - Source
---

本文主要介绍如何实现一个系统函数，类似于 `pg_backend_pid()` 的系统函数。PostgreSQL 所有的系统函数都记录在 `pg_proc` 系统表中。

``` plpgsql
postgres=# select oid,proname from pg_proc where proname = 'pg_backend_pid';
 oid  |    proname
------+----------------
 2026 | pg_backend_pid
(1 row)
```

<!-- more -->
## 系统表 `pg_proc`

关于系统表 [pg_proc][] 都详细介绍可以查看官方文档，这里简要介绍一些本文使用到的一些属性列。

<style>
table th:nth-of-type(1) {
    width: 15%;
}
table th:nth-of-type(2) {
    width: 10%;
}
</style>

| 属性列          | 类型      | 说明                                                   |
|-----------------|-----------|--------------------------------------------------------|
| oid             | oid       | 行标识符，用于标识函数                                 |
| proname         | name      | 函数名                                                 |
| pronamespace    | oid       | 包含该函数的命令空间的标识符                           |
| proowner        | oid       | 该函数的拥有者                                         |
| prorows         | float4    | 估计的结果行数 (如果 `proretset` 为 `false` 则为零)    |
| proretset       | bool      | 函数返回一个集合（即指定数据类型的多个值）             |
| provolatile     | char      | 函数的结果是否取决于输入参数，或受外部因素影响<br>`i` - 不变的函数，对于相同的输入始终有相同的输出。<br>`s` - 稳定的函数，其结果（对于固定输入）在扫描中不会改变。<br> `v` - 易失的函数，其结果可能随时更改，这样做的副作用是无法优化对它们的调用。         |
| proparallel     | char      | 该函数是否可以在并行模式下安全运行<br>`s` - 可以安全地在并行模式下不受限制地运行功能。<br>`r` - 可以在并行模式下运行的函数，但是它们的执行仅限于并行组领导者，并行工作进程无法调用这些功能。<br>`u` - 在并行模式下不安全的函数，此类函数的存在会强制执行串行执行计划。                     |
| pronargs        | int2      | 输入参数的个数                                         |
| pronargdefaults | int2      | 具有默认值的参数个数                                   |
| prorettype      | oid       | 返回值的数据类型                                       |
| proargtypes     | oidvector | 函数参数数据类型数组，这仅包括输入函数                 |
| proallargtypes  | oid[]     | 函数参数数据类型数组，这包含所有参数（输入、输出参数） |
| proargmodes     | char[]    | 函数参数的模式数组，`i` - INPUT 参数，`o` - OUTPUT 参数，`b` - INPUT/OUTPUT 参数，`v` - VARIADIC 参数，`t` - TABLE 参数。根据实现语言/调用约定，它可能是解释语言功能的实际源代码，链接符号，文件名或几乎所有其他内容。                                 |
| prosrc          | text      | 函数处理程序如何调用函数根据实现语言/调用约定，它可能是解释语言功能的实际源代码，链接符号，文件名或几乎所有其他内容                               |

我们上面提到的 `pg_backend_pid` 函数的各个属性如下所示：

``` perl
...
{ oid => '2026', descr => 'statistics: current backend PID',
  proname => 'pg_backend_pid', provolatile => 's', proparallel => 'r',
  prorettype => 'int4', proargtypes => '', prosrc => 'pg_backend_pid' },
...
```

上述内容来自 `src/include/catalog/pg_proc.dat` 文件，该文件中定义的系统函数的相关信息，在编译时，PostgreSQL 将会使用 Perl 对其进行转换，并最终插入到 `pg_proc` 系统表中。

## PostgreSQL 函数调用约定

PostgreSQL 通过函数调用约定来抑制传递参数和返回结果的复杂性。其定义如下所示：

``` C
Datum funcname(PG_FUNCTION_ARGS);
```

例如，`pg_backend_pid()` 函数的定义如下：

``` C
Datum
pg_backend_pid(PG_FUNCTION_ARGS)
{
    PG_RETURN_INT32(MyProcPid);
}
```

我们可以通过 `PG_GETARG_xxx()` 的宏来获取对应类型的参数；在非严格函数中，需要使用 `PG_ARGNULL_xxx()` 宏来事先检查参数是否为空；同时我们可以使用 `PG_RETURN_xxx()` 宏来返回结果。`PG_GETARG_xxx()` 接受一个数字参数，该参数表示我们需要获取那个参数，参数从零开始；`PG_RETURN_xxx()` 的参数是实际返回的值。这些宏都定义在 `src/include/fmgr.h` 文件中。

## 自定义系统函数

现在，我们可以来实现一个自定义的系统函数。PostgreSQL 提供了一个系统函数 `sha256(bytea)` 来计算 SHA256 哈希值。在本文中，我们将新 `sha256(text)` 类型的函数来计算 SHA256 哈希值。其源码如下：

``` C
/*
 * Create a SHA256 hash of a text value and return it as hex string.
 */
Datum
sha256_text(PG_FUNCTION_ARGS)
{
    int       i, j;
    text     *in_text = PG_GETARG_TEXT_PP(0);
    size_t    len;
    uint8     hexsum[PG_SHA256_DIGEST_LENGTH];
    char      digest[PG_SHA256_DIGEST_STRING_LENGTH];
    pg_sha256_ctx    sha256_ctx;

    /* Calculate the length of the buffer using varlena metadata */
    len = VARSIZE_ANY_EXHDR(in_text);

    /* get the hash result */
    pg_sha256_init(&sha256_ctx);
    pg_sha256_update(&sha256_ctx, (uint8 *) VARDATA_ANY(in_text), len);
    pg_sha256_final(&sha256_ctx, hexsum);

    for (i = 0, j = 0; i < PG_SHA256_DIGEST_LENGTH; i++)
    {
        static const char *hex = "0123456789abcdef";
        digest[j++] = hex[(hexsum[i] >> 4) & 0xF];
        digest[j++] = hex[hexsum[i] & 0xF];
    }
    digest[j] = '\0';

    PG_RETURN_TEXT_P(cstring_to_text(digest));
}
```

我们将其定义在 `src/backend/utils/adt/cryptohashes.c` 文件中，该文件包含了常用的哈希算法。接着我们需要在 `src/include/catalog/pg_proc.dat` 文件中添加 `sha256_text` 的实现，如下所示：

``` perl
...
{ oid => '3420', descr => 'SHA-256 hash',
  proname => 'sha256', proleakproof => 't', prorettype => 'bytea',
  proargtypes => 'bytea', prosrc => 'sha256_bytea' },
{ oid => '3423', descr => 'SHA256 hash',
  proname => 'sha256', proleakproof => 't', prorettype => 'text',
  proargtypes => 'text', prosrc => 'sha256_text' },
...
```

__注意：__`oid` 是不能重复的，我们可以使用 `src/include/catalog/unused_oids` 来获取一个未使用的 `oid`。

经过上述步骤，我们就完整的创建了一个 PostgreSQL 系统函数，如下所示：

``` plpgsql
postgres=# select sha256('hello');
                              sha256
------------------------------------------------------------------
 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
(1 row)

postgres=# postgres=# select sha256('hello'::bytea);
                               sha256
--------------------------------------------------------------------
 \x2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
(1 row)
```

当然，这个示例只是为了演示而做的。但是，根据这个示例，我们可以轻易的实现我们需要的系统函数。

## 参考

[1] https://www.postgresql.org/docs/11/catalog-pg-proc.html
[2] https://www.postgresql.org/docs/11/xfunc-c.html

[pg_proc]: https://www.postgresql.org/docs/11/catalog-pg-proc.html
