---
title: "PostgreSQL 插件编写"
date: 2018-12-19 21:31:57 +0800
category: 数据库
tags:
  - PostgreSQL
---

PostgreSQL 标榜自己为最先进 (Most Advance) 的开源关系数据库，它支持大部分 SQL 标准并且提供了许多其他现代特性：复杂查询、外键、触发器、视图、事务完整性、MVCC。同样，PostgreSQL 可以用许多方法扩展，比如，通过增加新的数据类型、函数、操作符、聚集函数、索引。PostgreSQL 被设计为易于扩展，因此通过插件我们可以很容易的扩展 PostgreSQL 数据库。本文就从编写一个简单的斐波那契的数据库扩展来介绍 PostgreSQL 插件的编写。

<!-- more -->

## 斐波那契数列

斐波那契数列 (Fibonacci sequence)，又称黄金分割数列、因数学家列昂纳多·斐波那契 (Leonardoda Fibonacci) 以兔子繁殖为例子而引入，故又称为“兔子数列”，指的是这样一个数列：1、1、2、3、5、8、13、21、34、...... 在数学上，斐波纳契数列以如下被以递推的方法定义<sup>1</sup>：

```
F(0) = 0, F(1) = 1, F(n) = F(n - 1) + F(n - 2) (n >= 2, n ∈ N)
```

## PostgreSQL 扩展插件的框架

我们为了使 PostgreSQL 可以通过 `CREATE EXTENSION` 命令加载插件，我们的扩展插件至少需要两个文件：一个名为 `extension_name.control` 的控制文件和一个名为 `extension--version.sql` 的扩展 SQL 脚本文件。其中控制文件中包含了扩展插件名、版本等基本信息。现在让我们创建这两个文件。

我们的 fibonacci 扩展插件的控制文件 (fibonacci.control) 内容如下：

```
# fibonacci extension
comment = 'fibonacci extension'
default_version = '0.0.1'
relocatable = true
```

我们将使用 PL/pgSQL 来实现这个插件 (fibonacci--0.0.1.sql)，其内容如下所示：

```
-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION fibonacci" to load this file. \quit
CREATE FUNCTION fibonacci(n INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
    DECLARE
        counter INTEGER := 0;
        i INTEGER := 0;
        j INTEGER := 1;
    BEGIN

        IF n < 1 THEN
            RETURN 0;
        END IF;

        WHILE counter < n LOOP
            counter := counter + 1;
            SELECT j, i + j INTO i, j;
        END LOOP;

        RETURN i;
    END;
    $$;
```

自 PostgreSQL 9.1 之后，PostgreSQL 提供了 PGXS 用于构建其插件，大部分构建插件的环境变量都可以通过 pg_config 得到重用。接下来我们为 fibonacci 插件添加一个 Makefile 文件用于安装插件。

```
EXTENSION = fibonacci        # the extensions name
DATA = fibonacci--0.0.1.sql  # script files to install

# postgres build stuff
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
```

接下来我们便可以通过 `make install` 来安装插件。最后，我们在数据库中执行如下操作：

```
postgres@database:~/postgresql-10.4/fib$ psql postgres
psql (10.4)
Type "help" for help.

postgres=# create extension fibonacci ;
CREATE EXTENSION
postgres=# select fibonacci(10);
 fibonacci
-----------
        55
(1 row)

postgres=#
```

## 测试用例

现在我们完成了基本的插件功能，但是任何程序都应该包含测试用例以便验证程序的正确性。我们可以很方便的为 PostgreSQL 添加回归测试，在执行完 `make install` 命令之后利用 `make installcheck` 运行插件的回归测试。PostgreSQL 将回归测试脚本放在插件目录的 `sql/` 文件中，每个测试文件都对应一个期望结果的输出文件并放置在插件目录的 `expected/` 文件中，测试脚本与期望结果具有相同的名字，唯一不同的是期望结果的文件的后缀名为 `.out`。命令 `make installcheck` 执行 `psql` 目录下的所有脚本并且将输出的结果与 `expected` 目录中的文件进行比较。任何不同的结果都将被写入 `regression.diffs` 文件。现在，我们为插件添加测试用例：

```
postgres@database:~/postgresql-10.4/fib$ cat sql/fibonacci_test.sql
CREATE EXTENSION fibonacci;
SELECT fibonacci(0);
SELECT fibonacci(1);
SELECT fibonacci(2);
SELECT fibonacci(3);
SELECT fibonacci(4);
SELECT fibonacci(5);
SELECT fibonacci(6);
SELECT fibonacci(7);
SELECT fibonacci(8);
SELECT fibonacci(9);
SELECT fibonacci(10);
SELECT fibonacci(11);
SELECT fibonacci(12);
SELECT fibonacci(13);
SELECT fibonacci(14);
SELECT fibonacci(15);
SELECT fibonacci(16);
SELECT fibonacci(17);
SELECT fibonacci(18);
SELECT fibonacci(19);
SELECT fibonacci(20);
```

同时，我们需要修改 `Makefile` 文件，以便其能执行回归测试。

```
EXTENSION = fibonacci        # the extensions name
DATA = fibonacci--0.0.1.sql  # script files to install
REGRESS = fibonacci_test     # our test script file (without extension)

# postgres build stuff
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
```

现在，我们执行 `make install && make installcheck` 时，回归测试将会失败，这是由于我们还没有指定期望的输出结果。但是，我们发现目录下多了一个 `results` 目录，并且该目录下包含 `fibonacci_test.out` 和 `fibonacci_test.out.diff` 两个文件。为了简便，我们在这里创建一个 `expected` 目录，并将 `fibonacci_test.out` 拷贝到该目录下。

```
postgres@database:~/postgresql-10.4/fib$ mkdir expected
postgres@database:~/postgresql-10.4/fib$ mv results/fibonacci_test.out expected/
postgres@database:~/postgresql-10.4/fib$ make installcheck
/home/postgres/postgresql-10.4/lib/pgxs/src/makefiles/../../src/test/regress/pg_regress --inputdir=./ --bindir='/home/postgres/postgresql-10.4/bin'    --dbname=contrib_regression fibonacci_test
(using postmaster on Unix socket, default port)
============== dropping database "contrib_regression" ==============
DROP DATABASE
============== creating database "contrib_regression" ==============
CREATE DATABASE
ALTER DATABASE
============== running regression test queries        ==============
test fibonacci_test           ... ok

=====================
 All 1 tests passed.
=====================

postgres@database:~/postgresql-10.4/fib$
```

我们测试求 `[1,30]` 的斐波那契数列，其运行结果如下：

```
postgres=# SELECT i, fibonacci(i) FROM generate_series(1,30) i;
 i  | fibonacci
----+-----------
  1 |         1
  2 |         1
  3 |         2
  4 |         3
  5 |         5
  6 |         8
  7 |        13
  8 |        21
  9 |        34
 10 |        55
 11 |        89
 12 |       144
 13 |       233
 14 |       377
 15 |       610
 16 |       987
 17 |      1597
 18 |      2584
 19 |      4181
 20 |      6765
 21 |     10946
 22 |     17711
 23 |     28657
 24 |     46368
 25 |     75025
 26 |    121393
 27 |    196418
 28 |    317811
 29 |    514229
 30 |    832040
(30 rows)

Time: 12.432 ms
postgres=#
```

## 利用 C 语言优化性能

上面我们使用 PL/pgSQL 为 PostgreSQL 编写了斐波那契插件，从上面的运行时间看基本还算可以。但是，我们还可以通过 C 语言来重写这个插件从而提高其性能。下面给出了 C 语言版的斐波那契插件的实现。

``` C
/*----------------------------------------------------------------------------
 *
 * fibonacci.c
 *   Fibonacci extension for PostgreSQL.
 *
 *----------------------------------------------------------------------------
*/
#include "postgres.h"
#include "fmgr.h"

PG_MODULE_MAGIC;

Datum fibonacci(PG_FUNCTION_ARGS);

PG_FUNCTION_INFO_V1(fibonacci);

Datum
fibonacci(PG_FUNCTION_ARGS)
{
    int32 arg = PG_GETARG_INT32(0);
    int32 i = 0;
    int32 j = 1;

    if (arg < 1) {
        PG_RETURN_INT32(0);
    }

    while (arg--) {
        int32 t = j;
        j = i + j;
        i = t;
    }

    PG_RETURN_INT32(i);
}
```

* `postgres.h` 文件包含了 PostgreSQL 的一些基本的编程接口，该文件需要在每个声明 Postgres 函数的 C 源文件中出现。
* `fmgr.h` 包含了 `PG_GETARG_XXX` 和 `PG_RETURN_XXX` 的一系列宏定义。
* `PG_MODULE_MAGIC` 是一个魔术块，它用于确保将动态加载的目标文件加载到兼容的服务器中。

现在，我们利用 C 语言重写了斐波那契插件；接着，我们需要修改安装脚本文件 `fibonacci--0.0.1.sql` 和 `Makefile` 文件。为了便于区分，我们将 C 语言实现的版本命名为 `0.0.2`，因此我们创建一个 `fibonacci--0.0.2.sql` 的安装脚本，其内容如下：

``` sql
-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION fibonacci" to load this file. \quit
CREATE FUNCTION fibonacci(n INTEGER)
RETURNS INTEGER AS '$libdir/fibonacci'
LANGUAGE C IMMUTABLE STRICT;
```

接下来修改 `Makefile` 文件使其能正常编译我们的 fibonacci 插件的源文件。

```
EXTENSION = fibonacci        # the extensions name
DATA = fibonacci--0.0.2.sql  # script files to install
REGRESS = fibonacci_test     # our test script file (without extension)
MODULES = fibonacci

# postgres build stuff
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
```

注意，我们还需要修改 `fibonacci.control` 文件中的 `default_version` 为 `0.0.2`。现在我们便可以通过 `make install && make installcheck` 来安装插件了。

```
postgres=# SELECT i, fibonacci(i) FROM generate_series(1,30) i;
 i  | fibonacci
----+-----------
  1 |         1
  2 |         1
  3 |         2
  4 |         3
  5 |         5
  6 |         8
  7 |        13
  8 |        21
  9 |        34
 10 |        55
 11 |        89
 12 |       144
 13 |       233
 14 |       377
 15 |       610
 16 |       987
 17 |      1597
 18 |      2584
 19 |      4181
 20 |      6765
 21 |     10946
 22 |     17711
 23 |     28657
 24 |     46368
 25 |     75025
 26 |    121393
 27 |    196418
 28 |    317811
 29 |    514229
 30 |    832040
(30 rows)

Time: 2.280 ms
postgres=#
```

从运行时间上看，C 语言版的斐波那契要比 PL/pgSQL 的运行速度快大约 80%。

__备注：__ 由于 C 语言插件在 PostgreSQL 中采用动态库的形式载入的，因此我们需要修改配置文件中的 `shared_preload_libraries` 参数。

## 总结

本文介绍了如何使用 plpgsql 编写 PostgreSQL 的扩展插件，PostgreSQL 有两个基本的文件：

* extension.control - 插件控制文件
* extension--version.sql - 用于创建扩展的脚本文件

此外，我们可能还需要 `sql` 和 `expected` 目录用于存放回归测试用例及其结果。最后，为了提高插件的运行效率，我们将原来的 PL/pgSQL 版本采用 C 语言来实现。

## 参考

[1] [斐波那契数列](https://baike.baidu.com/item/%E6%96%90%E6%B3%A2%E9%82%A3%E5%A5%91%E6%95%B0%E5%88%97/99145?fr=aladdin)
[2] [Writing Postgres Extensions - the Basics](http://big-elephants.com/2015-10/writing-postgres-extensions-part-i/)
[3] [PostgreSQL - C-Language Functions](https://www.postgresql.org/docs/10/xfunc-c.html)
