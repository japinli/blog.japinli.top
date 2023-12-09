---
title: "PostgreSQL ICU 回归测试失败"
date: 2023-08-15 22:46:14 +0800
categories: 数据库
tags:
  - PostgreSQL
---

最近遇到一个比较有意思的问题，我在运行 PostgreSQL 的回归测试时发现 `collate.icu.utf8` 这个测试用例在 `REL_14_STABLE` 分支始终无法跑过，但是在 `REL_15_STABLE` 却可以正常运行。同时由于 `collate.icu.utf8` 失败还将导致 `foreign_data` 测试用例也失败了。

<!--more-->

下面是详细的错误信息。

```diff
diff -U3 /home/japin/Codes/postgres/build/../src/test/regress/expected/collate.icu.utf8.out /home/japin/Codes/postgres/build/src/test/regress/results/collate.icu.utf8.out
--- /home/japin/Codes/postgres/build/../src/test/regress/expected/collate.icu.utf8.out	2023-08-14 17:37:31.960448245 +0800
+++ /home/japin/Codes/postgres/build/src/test/regress/results/collate.icu.utf8.out	2023-08-14 21:30:44.335214886 +0800
@@ -1035,6 +1035,9 @@
           quote_literal(current_setting('lc_ctype')) || ');';
 END
 $$;
+ERROR:  collations with different collate and ctype values are not supported by ICU
+CONTEXT:  SQL statement "CREATE COLLATION test1 (provider = icu, lc_collate = 'C.UTF-8', lc_ctype = 'en_US.UTF-8');"
+PL/pgSQL function inline_code_block line 3 at EXECUTE
 CREATE COLLATION test3 (provider = icu, lc_collate = 'en_US.utf8'); -- fail, need lc_ctype
 ERROR:  parameter "lc_ctype" must be specified
 CREATE COLLATION testx (provider = icu, locale = 'nonsense'); /* never fails with ICU */  DROP COLLATION testx;
@@ -1045,13 +1048,12 @@
  collname
 ----------
  test0
- test1
  test5
-(3 rows)
+(2 rows)

 ALTER COLLATION test1 RENAME TO test11;
+ERROR:  collation "test1" for encoding "UTF8" does not exist
 ALTER COLLATION test0 RENAME TO test11; -- fail
-ERROR:  collation "test11" already exists in schema "collate_tests"
 ALTER COLLATION test1 RENAME TO test22; -- fail
 ERROR:  collation "test1" for encoding "UTF8" does not exist
 ALTER COLLATION test11 OWNER TO regress_test_role;
@@ -1059,18 +1061,19 @@
 ERROR:  role "nonsense" does not exist
 ALTER COLLATION test11 SET SCHEMA test_schema;
 COMMENT ON COLLATION test0 IS 'US English';
+ERROR:  collation "test0" for encoding "UTF8" does not exist
 SELECT collname, nspname, obj_description(pg_collation.oid, 'pg_collation')
     FROM pg_collation JOIN pg_namespace ON (collnamespace = pg_namespace.oid)
     WHERE collname LIKE 'test%'
     ORDER BY 1;
  collname |    nspname    | obj_description
 ----------+---------------+-----------------
- test0    | collate_tests | US English
  test11   | test_schema   |
  test5    | collate_tests |
-(3 rows)
+(2 rows)

 DROP COLLATION test0, test_schema.test11, test5;
+ERROR:  collation "test0" for encoding "UTF8" does not exist
 DROP COLLATION test0; -- fail
 ERROR:  collation "test0" for encoding "UTF8" does not exist
 DROP COLLATION IF EXISTS test0;
@@ -1078,10 +1081,17 @@
 SELECT collname FROM pg_collation WHERE collname LIKE 'test%';
  collname
 ----------
-(0 rows)
+ test11
+ test5
+(2 rows)

 DROP SCHEMA test_schema;
+ERROR:  cannot drop schema test_schema because other objects depend on it
+DETAIL:  collation test_schema.test11 depends on schema test_schema
+HINT:  Use DROP ... CASCADE to drop the dependent objects too.
 DROP ROLE regress_test_role;
+ERROR:  role "regress_test_role" cannot be dropped because some objects depend on it
+DETAIL:  owner of collation test_schema.test11
 -- ALTER
 ALTER COLLATION "en-x-icu" REFRESH VERSION;
 NOTICE:  version has not changed
diff -U3 /home/japin/Codes/postgres/build/../src/test/regress/expected/foreign_data.out /home/japin/Codes/postgres/build/src/test/regress/results/foreign_data.out
--- /home/japin/Codes/postgres/build/../src/test/regress/expected/foreign_data.out	2023-08-14 17:37:31.964448260 +0800
+++ /home/japin/Codes/postgres/build/src/test/regress/results/foreign_data.out	2023-08-14 21:30:55.571170376 +0800
@@ -5,10 +5,13 @@
 -- Suppress NOTICE messages when roles don't exist
 SET client_min_messages TO 'warning';
 DROP ROLE IF EXISTS regress_foreign_data_user, regress_test_role, regress_test_role2, regress_test_role_super, regress_test_indirect, regress_unprivileged_role;
+ERROR:  role "regress_test_role" cannot be dropped because some objects depend on it
+DETAIL:  owner of collation test_schema.test11
 RESET client_min_messages;
 CREATE ROLE regress_foreign_data_user LOGIN SUPERUSER;
 SET SESSION AUTHORIZATION 'regress_foreign_data_user';
 CREATE ROLE regress_test_role;
+ERROR:  role "regress_test_role" already exists
 CREATE ROLE regress_test_role2;
 CREATE ROLE regress_test_role_super SUPERUSER;
 CREATE ROLE regress_test_indirect;
```

## 分析

从上面的错误信息我们可以看到回归测试在执行 `CREATE COLLATION test1 (provider = icu, lc_collate = 'C.UTF-8', lc_ctype = 'en_US.UTF-8');` 语句时出现了非期望的情况。通过查看 `collate.icu.utf8.out` 文件，我们可以定位到如下内容：

```sql
do $$
BEGIN
  EXECUTE 'CREATE COLLATION test1 (provider = icu, lc_collate = ' ||
          quote_literal(current_setting('lc_collate')) ||
          ', lc_ctype = ' ||
          quote_literal(current_setting('lc_ctype')) || ');';
END
$$;
```

测试用例使用 `current_setting()` 来获取 `lc_collate` 和 `lc_ctype` 的值，并且期望这两个值是相同的，但是在实际的回归测试时，`lc_collate` 为 `C.UTF-8` 而 `lc_ctype` 为 `en_US.UTF-8`，从而导致测试用例失败。

然而，当我尝试使用 `make installcheck` 运行回归测试时，一切又都正常了。

考虑到这个是和 `locale` 相关，因此我确认了一下该环境下的 `locale` 设置。

```bash
$ locale
LANG=C.UTF-8
LANGUAGE=
LC_CTYPE="en_US.UTF-8"
LC_NUMERIC="en_US.UTF-8"
LC_TIME="en_US.UTF-8"
LC_COLLATE="en_US.UTF-8"
LC_MONETARY="en_US.UTF-8"
LC_MESSAGES="en_US.UTF-8"
LC_PAPER="en_US.UTF-8"
LC_NAME="en_US.UTF-8"
LC_ADDRESS="en_US.UTF-8"
LC_TELEPHONE="en_US.UTF-8"
LC_MEASUREMENT="en_US.UTF-8"
LC_IDENTIFICATION="en_US.UTF-8"
LC_ALL=en_US.UTF-8
```

可以看到 `LANG` 的设置与其他的不同，我尝试用 `export LANG=en_US.UTF-8` 重新导出环境变量，然后在执行 `make check`，此时一切就正常了。

从结果来看，回归测试的失败是由于 `LANG` 的设置不合理导致的。那么为什么 `REL_15_STABLE` 没有遇到这个情况呢？

如下所示，查看 `REL_15_STABLE` 的 `collate.icu.utf8.out` 测试，可以发现它将 `lc_collate` 和 `lc_ctype` 合并为 `locale` 了，因此没有导致回归测试失败。

```bash
$ git show origin/REL_15_STABLE:src/test/regress/expected/collate.icu.utf8.out | grep -A 3 -B 2 'CREATE COLLATION test1'
do $$
BEGIN
  EXECUTE 'CREATE COLLATION test1 (provider = icu, locale = ' ||
          quote_literal(current_setting('lc_collate')) || ');';
END
$$;
```

这是 PG 15 开发分支的 [`f2553d43`](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=f2553d43060edb210b36c63187d52a632448e1d2) 提交引入的。

```diff
diff --git a/src/test/regress/sql/collate.icu.utf8.sql b/src/test/regress/sql/collate.icu.utf8.sql
index 242a7ce6b7..b0ddc7db44 100644
--- a/src/test/regress/sql/collate.icu.utf8.sql
+++ b/src/test/regress/sql/collate.icu.utf8.sql
@@ -366,13 +366,11 @@ $$;
 CREATE COLLATION test0 FROM "C"; -- fail, duplicate name
 do $$
 BEGIN
-  EXECUTE 'CREATE COLLATION test1 (provider = icu, lc_collate = ' ||
-          quote_literal(current_setting('lc_collate')) ||
-          ', lc_ctype = ' ||
-          quote_literal(current_setting('lc_ctype')) || ');';
+  EXECUTE 'CREATE COLLATION test1 (provider = icu, locale = ' ||
+          quote_literal(current_setting('lc_collate')) || ');';
 END
 $$;
-CREATE COLLATION test3 (provider = icu, lc_collate = 'en_US.utf8'); -- fail, need lc_ctype
+CREATE COLLATION test3 (provider = icu, lc_collate = 'en_US.utf8'); -- fail, needs "locale"
 CREATE COLLATION testx (provider = icu, locale = 'nonsense'); /* never fails with ICU */  DROP COLLATION testx;

 CREATE COLLATION test4 FROM nonsense;
```

那么为什么 `LANG` 会影响到数据库的 `lc_collate` 和 `lc_ctype` 呢？在我的环境变量中又是配置了 `LC_COLLATE` 和 `LC_CTYPE` 的，同时也可以注意到 `LC_ALL` 也配置了。

关于环境变量 `LANG`，`LC_ALL` 和 `LC_*` 的优先级如下所示：

> The environment variables LANG, LC_ALL, LC_COLLATE, LC_CTYPE, LC_MESSAGES, LC_MONETARY, LC_NUMERIC, LC_TIME, (LC_*), and NLSPATH provide for the support of internationalised applications. The standard utilities make use of these environment variables as described in this section and the individual ENVIRONMENT VARIABLES sections for the utilities. If these variables specify locale categories that are not based upon the same underlying codeset, the results are unspecified.
>
> The values of locale categories are determined by a precedence order; the first condition met below determines the value:
>
> 1. If the LC_ALL environment variable is defined and is not null, the value of LC_ALL is used.
> 2. If the LC_* environment variable ( LC_COLLATE, LC_CTYPE, LC_MESSAGES, LC_MONETARY, LC_NUMERIC, LC_TIME) is defined and is not null, the value of the environment variable is used to initialise the category that corresponds to the environment variable.
> 3. If the LANG environment variable is defined and is not null, the value of the LANG environment variable is used.
> 4. If the LANG environment variable is not set or is set to the empty string, the implementation-dependent default locale is used.

从上面我看可以看到，`LC_ALL` 的优先级是最高的，其次是 `LC_*`，最后是 `LANG`，那么为什么 `make check` 的时候会出现 `LC_COLLATE` 和 `LC_CTYPE` 不一致的情况呢？（这里更准确的说应该是 `current_setting('lc_collate')` 和 `current_setting('lc_ctype')` 不一致。）

**待进一步分析。**

## 解决办法

上面已经提到了如何解决这个问题，我们可以重新导出 `LANG` 环境变量，使其与 `LC_ALL`、`LC_CTYPE` 和 `LC_COLLATE` 一致。

## 参考

[1] https://pubs.opengroup.org/onlinepubs/7908799/xbd/envvar.html

<div class="just-for-fun">
笑林广记 - 驼叔

有驼子赴席，泰然上座。众客既齐，自觉不安，复趋下谦。
众客曰：“驼叔请上座，直（侄）背（辈）怎敢。”
</div>
