---
title: "再谈 PostgreSQL 行级安全策略"
date: 2020-11-21 13:32:49 +0800
category: 数据库
tags:
  - PostgreSQL
---

在 {% post_link postgresql-row-level-security-policy PostgreSQL 行级安全策略的使用 %}一文中，我简要介绍了如何使用行级安全策略，最近因为工作需要对其又有了新的认识，故在此记录一下。本文主要介绍行级安全策略中用户权限和策略表达式（`USING` 和 `CHECK`）。

<!-- more -->

## 用户权限

在之前的文章中我忽略了一点关于行级安全策略的用户权限问题。默认情况下，PostgreSQL 中表的所有者是不受行级安全策略的限制的，也就是说即便表启用了行级安全策略，表的所有者也可以查询所有的数据。

如下所示，我们创建 `rls1` 和 `rls2` 两个用户，随后切换到 `rls1` 用户下并创建 `tblrls` 表，最后将表上的所有操作授权给 `rls2` 用户。

``` psql
postgres=# CREATE USER rls1;
CREATE ROLE
postgres=# CREATE USER rls2;
CREATE ROLE
postgres=# \c postgres rls1
You are now connected to database "postgres" as user "rls1".
postgres=> CREATE TABLE tblrls (id int, value int, username text);
CREATE TABLE
postgres=> GRANT ALL ON tblrls TO rls2;
GRANT
```

接着我们在表中插入数据，并新建一个行级安全策略。

``` psql
postgres=> INSERT INTO tblrls VALUES (1, 10, 'rls1'), (2, 20, 'rls2');
INSERT 0 2
postgres=> ALTER TABLE tblrls ENABLE ROW LEVEL SECURITY ;
ALTER TABLE
postgres=> CREATE POLICY rlsp1 ON tblrls USING ( username = current_user);
CREATE POLICY
```

此时我们查询数据，您会发现 `rls1` 用户可以查看所有数据。

``` psql
postgres=> SELECT * FROM tblrls; -- rls1 用户
 id | value | username
----+-------+----------
  1 |    10 | rls1
  2 |    20 | rls2
(2 rows)

postgres=> \c postgres rls2
You are now connected to database "postgres" as user "rls2".
postgres=> SELECT * FROM tblrls ;
 id | value | username
----+-------+----------
  2 |    20 | rls2
(1 row)
```

这是由于表属于 `rls1` 用户，PostgreSQL 提供了 `ENFORCE ROW ` 来控制表所有者的行级安全策略行为。这里为了方便使用，我们通过超级用户登陆，并使用 `SET ROLE` 来切换用户。

``` psql
postgres=# SELECT * FROM tblrls;
 id | value | username
----+-------+----------
  1 |    10 | rls1
  2 |    20 | rls2
(2 rows)

postgres=> ALTER TABLE tblrls FORCE ROW LEVEL SECURITY;
ALTER TABLE
postgres=> SELECT * FROM tblrls;
 id | value | username
----+-------+----------
  1 |    10 | rls1
(1 row)

postgres=> SET ROLE rls2;
SET
postgres=> SELECT * FROM tblrls;
 id | value | username
----+-------+----------
  2 |    20 | rls2
(1 row)

postgres=> RESET ROLE;
RESET
postgres=# SELECT * FROM tblrls;
 id | value | username
----+-------+----------
  1 |    10 | rls1
  2 |    20 | rls2
(2 rows)
```

从上面的结果，我们可以看到，`FORCE ROW LEVEL SECURITY` 可以控制表所有者的行级安全策略行为，相应的，我们可以通过 `NO FORCE ROW LEVEL SECURITY` 来禁用表所有者的行级安全策略。在梳理这个功能的时候，我还给 PostgreSQL 提供了一个关于[行级安全策略的 psql 补全功能](https://postgr.es/m/15B10F9F-5847-4F5E-BD66-8E25AA473C95@hotmail.com)，代码十分简单，感兴趣的可以去看看。


## 策略表达式

在之前的行级安全策略中，我们都只用到了 `USING` 表达式，PostgreSQL 还支持行级安全策略中使用 `CHECK` 表达式，它们两者的用途是不一样的。

正如上面看到的，`USING` 表达式表明了用户可以读取哪些数据，而 `CHECK` 表达式则指明了哪些数据可以插入/更新到表中。需要注意的是，如果表没有 `CHECK` 表达式，那么它将使用 `USING` 表达式。

我们先来看看没有 `CHECK` 表达式时，插入违反 `USING` 表达式的示例，接上面的例子。

``` psql
postgres=> INSERT INTO tblrls VALUES (3, 30, 'rls2');  -- rls1 用户
ERROR:  new row violates row-level security policy for table "tblrls"
```

现在，我们为其创建一个 `CHECK` 表达式，并测试。

``` psql
postgres=> CREATE POLICY rlsp2 ON tblrls WITH CHECK ( value % 10 = 0);
CREATE POLICY
postgres=> INSERT INTO tblrls VALUES (4, 41, 'rls2');
ERROR:  new row violates row-level security policy for table "tblrls"
postgres=> INSERT INTO tblrls VALUES (4, 40, 'rls2');
INSERT 0 1
```

从上面的结果可以看到，在数据插入的时候将检查 `CHECK` 和 `USING` 表达式，只要满足其中一个条件即可插入到表中。这种行为在行级安全策略中被称为 PERMISSIVE 模式，多个策略通过 OR 进行连接。

当然，我们也可以指定 RESTRICTIVE 模式，那么多个策略则是通过 AND 的方式进行连接。

``` psql
postgres=> DROP POLICY rlsp2 ON tblrls;
DROP POLICY
postgres=> CREATE POLICY rlsp2 ON tblrls AS RESTRICTIVE  WITH CHECK ( value % 10 = 0);
CREATE POLICY
postgres=> INSERT INTO tblrls VALUES (4, 40, 'rls2');
ERROR:  new row violates row-level security policy for table "tblrls"
postgres=> INSERT INTO tblrls VALUES (4, 41, 'rls1');
ERROR:  new row violates row-level security policy "rlsp2" for table "tblrls"
postgres=> INSERT INTO tblrls VALUES (4, 40, 'rls1');
INSERT 0 1
```

注意到这里有的地方每个给出违反的策略名，而有的地方给出了违反的策略名。这是由于在使用 PERMISSIVE 时，PostgreSQL 将会在最外层（多余一个 permissive 策略时）加上一个名为 `NULL` 的 `WithCheckOption`（您可以把它理解为一个策略） 对象将多个 permissive 策略组合，其代码在 `src/backend/rewrite/rowsecurity.c` 文件中。

```C
    {
        /*
         * Add a single WithCheckOption for all the permissive policy clauses,
         * combining them together using OR.  This check has no policy name,
         * since if the check fails it means that no policy granted permission
         * to perform the update, rather than any particular policy being
         * violated.
         */
        WithCheckOption *wco;

        wco = makeNode(WithCheckOption);
        wco->kind = kind;
        wco->relname = pstrdup(RelationGetRelationName(rel));
        wco->polname = NULL;
        wco->cascaded = false;

        if (list_length(permissive_quals) == 1)
            wco->qual = (Node *) linitial(permissive_quals);
        else
            wco->qual = (Node *) makeBoolExpr(OR_EXPR, permissive_quals, -1);

        ChangeVarNodes(wco->qual, 1, rt_index, 0);

        *withCheckOptions = list_append_unique(*withCheckOptions, wco);

        /*
         * Now add WithCheckOptions for each of the restrictive policy clauses
         * (which will be combined together using AND).  We use a separate
         * WithCheckOption for each restrictive policy to allow the policy
         * name to be included in error reports if the policy is violated.
         */
        foreach(item, restrictive_policies)
        {
            RowSecurityPolicy *policy = (RowSecurityPolicy *) lfirst(item);
            Expr       *qual = QUAL_FOR_WCO(policy);
            WithCheckOption *wco;

            if (qual != NULL)
            {
                qual = copyObject(qual);
                ChangeVarNodes((Node *) qual, 1, rt_index, 0);

                wco = makeNode(WithCheckOption);
                wco->kind = kind;
                wco->relname = pstrdup(RelationGetRelationName(rel));
                wco->polname = pstrdup(policy->policy_name);
                wco->qual = (Node *) qual;
                wco->cascaded = false;

                *withCheckOptions = list_append_unique(*withCheckOptions, wco);
                *hasSubLinks |= policy->hassublinks;
            }
        }
    }
```

## 参考

[1] https://www.postgresql.org/docs/current/sql-createpolicy.html
[2] https://learn.graphile.org/docs/PostgreSQL_Row_Level_Security_Infosheet.pdf
