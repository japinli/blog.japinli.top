---
title: "pg_parse_query 和 pg_rewrite_query 函数返回值分析"
date: 2023-12-16 22:18:19 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

最近被朋友问到 `pg_parse_query()` 函数在什么情况下会返回多个 `RawStmt`，因为在大多数情况下，该函数仅会返回一个 `RawStmt`。这个问题与之前另一个朋友咨询的 `pg_rewrite_query()` 有点类似，但当时自己并没有整理记录，因此借着这个机会对这两个问题稍微整理一下。

<!--more-->

## `pg_parse_query()`

该函数用于对查询语句做原始解析并将查询语句转换为 `RawStmt` 对象。根据注释可以看到该函数返回原始解析树列表（即 `RawStmt` 的列表），当参数 `query_string` 中包含多个命令时，便会返回多个 `RawStmt` 对象。

那么什么时候会传入多个命令呢？当使用 `psql` 写多个 SQL 命令之后，其本质上还是一个 SQL 命令接着一个 SQL 命令执行的，因此仅会返回包含一个 `RawStmt` 结构的解析树连表。普通的不行，那么试试 PostgreSQL 中的函数看是否会同时传入多个命令，毕竟函数本身就可以包含多个 SQL 命令嘛。

```sql
CREATE OR REPLACE FUNCTION f01() RETURNS void AS $$ SELECT 1; SELECT 'abc'; $$ LANGUAGE sql;
```

随后我们在 `pg_parse_query()` 函数中下断点，如下所示：

```
Breakpoint 1, pg_parse_query (query_string=0x55e7821305e0 "CREATE OR REPLACE FUNCTION f01() RETURNS void AS $$ SELECT 1; SELECT 'abc'; $$ LANGUAGE sql;")
    at /home/japin/Codes/postgres/build/../src/backend/tcop/postgres.c:614
(gdb) n
(gdb) n
(gdb) # 执行 raw_parser()
(gdb) n
(gdb) p *raw_parsetree_list
$3 = {type = T_List, length = 1, max_length = 5, elements = 0x55e7821313c8, initial_elements = 0x55e7821313c8}
```

可以看到仍然只有一个 `RawStmt` 对象，不过这时如果继续执行，会发现它还会再进入到该函数中。

```gdb
(gdb) c
Continuing.

Breakpoint 1, pg_parse_query (query_string=0x55e78220e648 " SELECT 1; SELECT 'abc'; ")
    at /home/japin/Codes/postgres/build/../src/backend/tcop/postgres.c:614
(gdb) n
(gdb) n
(gdb) # 执行 raw_parser()
(gdb) n
(gdb) p *raw_parsetree_list
$4 = {type = T_List, length = 2, max_length = 5, elements = 0x55e78220f6a8, initial_elements = 0x55e78220f6a8}
```
可以看到，当前的 `query_string` 为 `SELECT 1; SELECT 'abc';` 它包含两个 SQL 命令，当执行完 `raw_parser()` 执行，生成了两个 `RawStmt` 对象并存储到 `raw_parsetree_list` 作为 `pg_parser_query()` 函数的返回值。

接着，尝试执行 `f01()` 函数，可以看到同样的效果。

```gdb
Breakpoint 1, pg_parse_query (query_string=0x55e7821305e0 "SELECT f01();")
    at /home/japin/Codes/postgres/build/../src/backend/tcop/postgres.c:614
(gdb) c
Continuing.

Breakpoint 1, pg_parse_query (query_string=0x55e7822084f0 " SELECT 1; SELECT 'abc'; ")
    at /home/japin/Codes/postgres/build/../src/backend/tcop/postgres.c:614
```

函数体里面包含了多个 SQL 语句，这时候就会有多个 `RawStmt` 对象产生。

## `pg_rewrite_query()`

该函数用于对解析树生成的查询进行重写。对于 DDL（诸如 `CREATE`, `DESTROY`, `COPY`, `VACUUM` 等）不会进行重写，只是将其包装成列表并返回，而对于 DML（`INSERT`, `SELECT`, `UPDATE` 和 `DELETE` 等）则需要进行重写，该重写由函数 `QueryRewrite()` 来进行。函数 [`QueryRewrite()`](https://git.postgresql.org/gitweb/?p=postgresql.git;a=blob;f=src/backend/rewrite/rewriteHandler.c;h=41a362310a8905a8e37a86c56572041050dcae5a;hb=HEAD#l4183) 可以分为三个阶段：

1. 应用所有的非 `SELECT` 规则，肯能得到零个或多个查询；
2. 对每个查询应用 RIR (Retrieve-Instead-Retrieve) 规则；
3. 确定结果查询中的哪一个（如果有）应该设置命令结果标签；并相应地更新 `canSetTag` 字段。

```c
/*
 * QueryRewrite -
 *    Primary entry point to the query rewriter.
 *    Rewrite one query via query rewrite system, possibly returning 0
 *    or many queries.
 *
 * NOTE: the parsetree must either have come straight from the parser,
 * or have been scanned by AcquireRewriteLocks to acquire suitable locks.
 */
List *
QueryRewrite(Query *parsetree)
{
    uint64      input_query_id = parsetree->queryId;
    List       *querylist;
    List       *results;
    ListCell   *l;
    CmdType     origCmdType;
    bool        foundOriginalQuery;
    Query      *lastInstead;

    /*
     * This function is only applied to top-level original queries
     */
    Assert(parsetree->querySource == QSRC_ORIGINAL);
    Assert(parsetree->canSetTag);

    /*
     * Step 1
     *
     * Apply all non-SELECT rules possibly getting 0 or many queries
     */
    querylist = RewriteQuery(parsetree, NIL, 0);

    /*
     * Step 2
     *
     * Apply all the RIR rules on each query
     *
     * This is also a handy place to mark each query with the original queryId
     */
    results = NIL;
    foreach(l, querylist)
    {
        Query      *query = (Query *) lfirst(l);

        query = fireRIRrules(query, NIL);

        query->queryId = input_query_id;

        results = lappend(results, query);
    }

    /*
     * Step 3
     *
     * Determine which, if any, of the resulting queries is supposed to set
     * the command-result tag; and update the canSetTag fields accordingly.
     *
     * If the original query is still in the list, it sets the command tag.
     * Otherwise, the last INSTEAD query of the same kind as the original is
     * allowed to set the tag.  (Note these rules can leave us with no query
     * setting the tag.  The tcop code has to cope with this by setting up a
     * default tag based on the original un-rewritten query.)
     *
     * The Asserts verify that at most one query in the result list is marked
     * canSetTag.  If we aren't checking asserts, we can fall out of the loop
     * as soon as we find the original query.
     */
    origCmdType = parsetree->commandType;
    foundOriginalQuery = false;
    lastInstead = NULL;

    foreach(l, results)
    {
        Query      *query = (Query *) lfirst(l);

        if (query->querySource == QSRC_ORIGINAL)
        {
            Assert(query->canSetTag);
            Assert(!foundOriginalQuery);
            foundOriginalQuery = true;
#ifndef USE_ASSERT_CHECKING
            break;
#endif
        }
        else
        {
            Assert(!query->canSetTag);
            if (query->commandType == origCmdType &&
                (query->querySource == QSRC_INSTEAD_RULE ||
                 query->querySource == QSRC_QUAL_INSTEAD_RULE))
                lastInstead = query;
        }
    }

    if (!foundOriginalQuery && lastInstead != NULL)
        lastInstead->canSetTag = true;

    return results;
}
```

从上面的代码可以看到，`pg_rewrite_query()` 的结果来自 `RewriteQuery()` 函数，而该函数是和 PostgreSQL 规则系统相关的，因此，当存在多个规则的时候可能会返回多个查询。

我们使用下面的测试用例来验证上述想法。

```sql
DROP TABLE IF EXISTS t1, t2;
CREATE TABLE t1 (id int, info text);
CREATE TABLE t2 (a int, b int);
CREATE RULE r00 AS ON INSERT TO t1 DO INSTEAD INSERT INTO t2 VALUES (random()::int, random()::int);
CREATE RULE r01 AS ON INSERT TO t1 DO INSTEAD SELECT * FROM t2;
```

接下来我们在 `pg_rewrite_query()` 和 `QueryRewrite()` 处下断点，执行 `INSERT INTO t1 VALUES (1, 'hello')` 并进行观察。

```
(gdb)
Breakpoint 2, pg_rewrite_query (query=0x55e782131438)
    at /home/japin/Codes/postgres/build/../src/backend/tcop/postgres.c:807
(gdb) c
Continuing.

Breakpoint 4, QueryRewrite (parsetree=0x55e782131438) at /home/japin/Codes/postgres/build/../src/backend/rewrite/rewriteHandler.c:4185
(gdb) n
(gdb) p *querylist
$13 = {type = T_List, length = 2, max_length = 5, elements = 0x55e78227f870, initial_elements = 0x55e78227f870}
```

可以看到 `t1` 表上包含了两条规则，查询重写完成之后生成了两个查询数，与猜想吻合。


<!--（即 [DO](https://www.postgresql.org/docs/current/sql-do.html) 语句）-->

<div class="just-for-fun">
笑林广记 - 忍屁

一女善屁，新婚随嫁一妪、一婢，嘱以忍屁遮羞。
临拜堂，忽撒一屁，顾妪曰：“这个老妈无体面。”
少顷又撒一屁，顾婢曰：“这个丫头恁可恶！”
随后又一屁，左右顾而妪、婢俱不在，无可说得，乃曰：“这张屁股好没正经。”
</div>
