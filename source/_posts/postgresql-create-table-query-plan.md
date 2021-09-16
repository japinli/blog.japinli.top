---
title: "PostgreSQL CREATE TABLE 查询计划树及执行计划树的生成"
date: 2019-05-25 08:32:46 +0800
category: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

在{% post_link postgresql-create-table-syntax-analysis 上一篇文章 %}中，我们主要分析了 `CREATE TABLE` 语句的的词法和语法，并简要说明了 PostgreSQL 的执行流程。本文将介绍 PostgreSQL 是如何将解析树转化为执行计划的。

<!-- more -->

## 查询计划树

PostgreSQL 在获取到原始解析树之后将通过函数 `pg_analyze_and_rewrite()` 对解析树进行解析分析并进行规则重写，分析器或规则重写器可能会将一个查询扩展为多个查询，因此可能返回多个查询节点。其函数定义如下：

``` c
/*
 * Given a raw parsetree (gram.y output), and optionally information about
 * types of parameter symbols ($n), perform parse analysis and rule rewriting.
 *
 * A list of Query nodes is returned, since either the analyzer or the
 * rewriter might expand one query to several.
 *
 * NOTE: for reasons mentioned above, this must be separate from raw parsing.
 */
List *
pg_analyze_and_rewrite(RawStmt *parsetree, const char *query_string,
                       Oid *paramTypes, int numParams,
                       QueryEnvironment *queryEnv)
{
    Query      *query;
    List       *querytree_list;

    TRACE_POSTGRESQL_QUERY_REWRITE_START(query_string);

    /*
     * (1) Perform parse analysis.
     */
    if (log_parser_stats)
        ResetUsage();

    query = parse_analyze(parsetree, query_string, paramTypes, numParams,
                          queryEnv);

    if (log_parser_stats)
        ShowUsage("PARSE ANALYSIS STATISTICS");

    /*
     * (2) Rewrite the queries, as necessary
     */
    querytree_list = pg_rewrite_query(query);

    TRACE_POSTGRESQL_QUERY_REWRITE_DONE(query_string);

    return querytree_list;
}
```

从函数的定义可以看到，该函数分为两个阶段：(1) 解析分析；(2) 规则重写。其中规则重写阶段不是必须进行的。

### 解析分析

解析分析通过 `parse_analyze()` 函数进行处理，它将原始解析树转换为一棵查询树。查询树的结构定义如下：

``` C
/*
 * Query -
 *    Parse analysis turns all statements into a Query tree
 *    for further processing by the rewriter and planner.
 *
 *    Utility statements (i.e. non-optimizable statements) have the
 *    utilityStmt field set, and the rest of the Query is mostly dummy.
 *
 *    Planning converts a Query tree into a Plan tree headed by a PlannedStmt
 *    node --- the Query structure is not used by the executor.
 */
typedef struct Query
{
    NodeTag     type;

    CmdType     commandType;    /* select|insert|update|delete|utility */

    QuerySource querySource;    /* where did I come from? */

    uint64      queryId;        /* query identifier (can be set by plugins) */

    bool        canSetTag;      /* do I set the command result tag? */

    Node       *utilityStmt;    /* non-null if commandType == CMD_UTILITY */

    int         resultRelation; /* rtable index of target relation for
                                 * INSERT/UPDATE/DELETE; 0 for SELECT */

    bool        hasAggs;        /* has aggregates in tlist or havingQual */
    bool        hasWindowFuncs; /* has window functions in tlist */
    bool        hasTargetSRFs;  /* has set-returning functions in tlist */
    bool        hasSubLinks;    /* has subquery SubLink */
    bool        hasDistinctOn;  /* distinctClause is from DISTINCT ON */
    bool        hasRecursive;   /* WITH RECURSIVE was specified */
    bool        hasModifyingCTE;    /* has INSERT/UPDATE/DELETE in WITH */
    bool        hasForUpdate;   /* FOR [KEY] UPDATE/SHARE was specified */
    bool        hasRowSecurity; /* rewriter has applied some RLS policy */

    List       *cteList;        /* WITH list (of CommonTableExpr's) */

    List       *rtable;         /* list of range table entries */
    FromExpr   *jointree;       /* table join tree (FROM and WHERE clauses) */

    List       *targetList;     /* target list (of TargetEntry) */

    OverridingKind override;    /* OVERRIDING clause */

    OnConflictExpr *onConflict; /* ON CONFLICT DO [NOTHING | UPDATE] */

    List       *returningList;  /* return-values list (of TargetEntry) */

    List       *groupClause;    /* a list of SortGroupClause's */

    List       *groupingSets;   /* a list of GroupingSet's if present */

    Node       *havingQual;     /* qualifications applied to groups */

    List       *windowClause;   /* a list of WindowClause's */

    List       *distinctClause; /* a list of SortGroupClause's */

    List       *sortClause;     /* a list of SortGroupClause's */

    Node       *limitOffset;    /* # of result tuples to skip (int8 expr) */
    Node       *limitCount;     /* # of result tuples to return (int8 expr) */

    List       *rowMarks;       /* a list of RowMarkClause's */

    Node       *setOperations;  /* set-operation tree if this is top level of
                                 * a UNION/INTERSECT/EXCEPT query */

    List       *constraintDeps; /* a list of pg_constraint OIDs that the query
                                 * depends on to be semantically valid */

    List       *withCheckOptions;   /* a list of WithCheckOption's (added
                                     * during rewrite) */

    /*
     * The following two fields identify the portion of the source text string
     * containing this query.  They are typically only populated in top-level
     * Queries, not in sub-queries.  When not set, they might both be zero, or
     * both be -1 meaning "unknown".
     */
    int         stmt_location;  /* start location, or -1 if unknown */
    int         stmt_len;       /* length in bytes; 0 means "rest of string" */
} Query;
```

当所处理的语句为 DDL 时 `Query` 结构使用 `utilityStmt` 成员来存储 DDL 原始解析树，而对于非 DDL 语句，解析分析则会将原始解析树中对应的结构解析到 `Query` 相应的成员中，本文暂时不做介绍。

`parse_analyze()` 函数通过调用 `transformTopLevelStmt()` 函数将原始解析树转换为查询树，在转换过程中，PostgreSQL 通过 `ParseState` 结构维护解析过程的中间状态。实际上 `transformTopLevelStmt()` 函数是通过调用 `transformOptionalSelectInto()` 函数进行处理，该函数针对 `SELECT ... INTO` 这种语句进行处理，随后使用 `transformStmt()` 函数进行所有语句的处理。

`transformStmt()` 函数内部通过一个 `switch` 语句进行处理，PostgreSQL 将 SQL 语句分为三大类：

* __Optimizable statements__ - 可以优化的语句，包括 `INSERT`, `DELETE`, `UPDATE` 和 `SELECT` 语句。
* __Special cases__ - 特殊语句，包括 `DECLARE CURSOR`, `EXPLAIN`, `CREATE TABLE AS` 和 `CALL` 语句。
* __Utility statements__ - 功能性语句，主要包括 `CREATE TABLE`, `CREATE FUNCTION` 等 DDL 语句。

函数 `parse_analyze()` 的函数定义如下（节选部分代码）：

``` C
/*
 * transformStmt -
 *    recursively transform a Parse tree into a Query tree.
 */
Query *
transformStmt(ParseState *pstate, Node *parseTree)
{
    Query      *result;

    ...

    switch (nodeTag(parseTree))
    {
            /*
             * Optimizable statements
             */
        case T_InsertStmt:
            result = transformInsertStmt(pstate, (InsertStmt *) parseTree);
            break;

            ...

            /*
             * Special cases
             */
        case T_DeclareCursorStmt:
            result = transformDeclareCursorStmt(pstate,
                                                (DeclareCursorStmt *) parseTree);
            break;

            ...

        default:

            /*
             * other statements don't require any transformation; just return
             * the original parsetree with a Query node plastered on top.
             */
            result = makeNode(Query);
            result->commandType = CMD_UTILITY;
            result->utilityStmt = (Node *) parseTree;
            break;
    }

    /* Mark as original query until we learn differently */
    result->querySource = QSRC_ORIGINAL;
    result->canSetTag = true;

    return result;
}
```

本文针对 `CREATE TABLE` 语句进行介绍，从上面的代码可以看到，针对 `CREATE TABLE` 这类 DDL 语句其实只是将原始解析树保存到 `Query->utilityStmt` 结构中。

### 规则重写

规则重写则是通过函数 `pg_rewrite_query()` 进行处理，其定义如下：

``` C
/*
 * Perform rewriting of a query produced by parse analysis.
 *
 * Note: query must just have come from the parser, because we do not do
 * AcquireRewriteLocks() on it.
 */
static List *
pg_rewrite_query(Query *query)
{
    List       *querytree_list;

    if (Debug_print_parse)
        elog_node_display(LOG, "parse tree", query,
                          Debug_pretty_print);

    if (log_parser_stats)
        ResetUsage();

    if (query->commandType == CMD_UTILITY)
    {
        /* don't rewrite utilities, just dump 'em into result list */
        querytree_list = list_make1(query);
    }
    else
    {
        /* rewrite regular queries */
        querytree_list = QueryRewrite(query);
    }

    ...

    return querytree_list;
}
```

从上述代码可以看到，类似于 `parse_analyze()` 函数，`pg_rewrite_query()` 函数针对 DDL 语句也不会进行重写，而只是将其存放到查询树链表中。

## 执行计划树

执行计划树则是通过 `pg_plan_queries()` 的生成的，其函数定义如下：

``` C
/*
 * Generate plans for a list of already-rewritten queries.
 *
 * For normal optimizable statements, invoke the planner.  For utility
 * statements, just make a wrapper PlannedStmt node.
 *
 * The result is a list of PlannedStmt nodes.
 */
List *
pg_plan_queries(List *querytrees, int cursorOptions, ParamListInfo boundParams)
{
    List       *stmt_list = NIL;
    ListCell   *query_list;

    foreach(query_list, querytrees)
    {
        Query      *query = lfirst_node(Query, query_list);
        PlannedStmt *stmt;

        if (query->commandType == CMD_UTILITY)
        {
            /* Utility commands require no planning. */
            stmt = makeNode(PlannedStmt);
            stmt->commandType = CMD_UTILITY;
            stmt->canSetTag = query->canSetTag;
            stmt->utilityStmt = query->utilityStmt;
            stmt->stmt_location = query->stmt_location;
            stmt->stmt_len = query->stmt_len;
        }
        else
        {
            stmt = pg_plan_query(query, cursorOptions, boundParams);
        }

        stmt_list = lappend(stmt_list, stmt);
    }

    return stmt_list;
}
```

`pg_plan_queries()` 函数的处理于解析分析与规则重写相同，针对 DDL 语句就是将查询计划书的封装到执行计划树中，而非 DDL 的语句处理则通过 `pg_plan_query()` 函数进行处理，其过程相对比较复杂。
