---
title: "Oracle 迁移 PostgreSQL - 空字符串"
date: 2021-09-26 21:10:58 +0800
categories: 数据库
tags:
  - Oracle
  - PostgreSQL
  - 迁移
---

Oracle 数据库中空字符串和 `NULL` 在字符串的环境下是相同的，这就意味着我们可以直接将其与字符串进行操作从而得到我们想要的结果，然而在 PostgreSQL 数据库中，任何字符串与 `NULL` 进行操作结果均为 `NULL`。因此，在迁移 `NULL` 字符串操作时，我们需要特别注意。

<!--more-->

## 示例

为了后面的演示说明，这里提供了一个简单的测试数据，如下所示。

```sql
CREATE TABLE t1 (id int, data varchar(10));
INSERT INTO t1 VALUES (1, 'Good');
INSERT INTO t1 VALUES (2, NULL);
```

接着，我们分别在 PostgreSQL 和 Oracle 数据库中执行下面的语句，可以发现它们的不同之处。

```sql
SELECT id, data || ', ooooooh, my God!' AS data FROM t1;
```

Oracle 中的执行结果如下：

```sql
SQL> SELECT id, data || ', ooooooh, my God!' AS data FROM t1;

        ID DATA
---------- ----------------------------
         1 Good, ooooooh, my God!
         2 , ooooooh, my God!
```

PostgreSQL 中的执行结果如下：

```sql
postgres=# SELECT id, data || ', ooooooh, my God!' AS data FROM t1;
 id |          data
----+------------------------
  1 | Good, ooooooh, my God!
  2 |
(2 rows)
```

其结果与上文描述一致，因此我们在将字符串操作迁移到 PostgreSQL 的时候需要进行判空处理。

## 迁移

我们可以使用 `coalesce()` 来进行迁移处理。

```sql
postgres=# SELECT id, coalesce(data, '') || ', ooooooh, my God!' AS data FROM t1;
 id |          data
----+------------------------
  1 | Good, ooooooh, my God!
  2 | , ooooooh, my God!
(2 rows)
```

这种方式在 Oracle 中同样适用。

```sql
SQL> SELECT id, coalesce(data, '') || ', ooooooh, my God!' AS data FROM t1;

        ID DATA
---------- ----------------------------
         1 Good, ooooooh, my God!
         2 , ooooooh, my God!
```

我个人觉得这种写法的可读性更好一些（此外，Oracle 中还可以使用 `nvl()` 来替代 `coalesce()` 函数）。

## 函数与存储过程

PostgreSQL 在使用 plpgsql 编写函数或存储过程时，字符串默认值为 `NULL`，因此，在进行字符串相关的操作时同样需要注意。例如：

```sql
CREATE OR REPLACE FUNCTION public.tfunc()
RETURNS void
AS $$
DECLARE
    t varchar(10);
    r record;
BEGIN
   FOR r IN SELECT id, data || t AS data FROM t1
   LOOP
       RAISE NOTICE '%, %', r.id, r.data;
   END LOOP;
END;
$$ LANGUAGE plpgsql;
```

上述函数的执行结果为：

```
postgres=# select tfunc();
NOTICE:  1, <NULL>
NOTICE:  2, <NULL>
 tfunc
-------

(1 row)
```

## 参考

[1] https://wiki.postgresql.org/wiki/Oracle_to_Postgres_Conversion#Empty_strings_and_NULL_values

<div class="just-for-fun">
笑林广记 - 强盗脚

乡民初次入城，见有木桶悬于城上。
问人曰：“此中何物？”
应者曰：“强盗头。”
及至县前，见数个木匣钉于谯楼之上，皆前官既去，而所留遗爱之靴。
乡民不知，乃点首曰：“城上挂的强盗头，此处一定是强盗脚了。”
</div>
