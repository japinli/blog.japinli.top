---
title: postgresql 索引扫描排序运算符
date: 2022-01-23 14:15:10 +0800
categories: 数据库
tags:
  - PostgreSQL
---

[最近看到一个问题](https://pgfans.cn/q/649)，说是在 `ExecIndexBuildScanKeys()` 函数中的 `isorderby` 参数在有 `ORDER BY` 字句时，`IndexScan` 中的 `indexorderby` 也为空。例如下面两个查询：

```sql
SELECT col FROM table_name ORDER BY index_key op const LIMIT 5;
SELECT col FROM table_name WHERE index_key op const;
```

这两个查询在执行 `ExecIndexBuildScanKeys()` 时 `IndexScan` 结构中的 `indexorderby` 均为空。然而，`IndexScan->indexorderby` 的注释为 `list of index ORDER BY exprs`，即 `ORDER BY` 语句后面的索引表达式，第一个 SQL 语句明显有 `ORDER BY` 字句，那么为什么此时的 `indexorderby` 为空呢？

<!--more-->

## 分析

我们首先来看看 [`IndexScan`](https://github.com/postgres/postgres/blob/master/src/include/nodes/plannodes.h#L367) 结构体的定义（代码比较长，仅截取部分内容）：

```c
/* ----------------
 *      index scan node
 *
 * [...]
 *
 * indexorderbyorig is similarly the original form of any ORDER BY expressions
 * that are being implemented by the index, while indexorderby is modified to
 * have index column Vars on the left-hand side.  Here, multiple expressions
 * must appear in exactly the ORDER BY order, and this is not necessarily the
 * index column order.  Only the expressions are provided, not the auxiliary
 * sort-order information from the ORDER BY SortGroupClauses; it's assumed
 * that the sort ordering is fully determinable from the top-level operators.
 * indexorderbyorig is used at runtime to recheck the ordering, if the index
 * cannot calculate an accurate ordering.  It is also needed for EXPLAIN.
 *
 * [...]
 *
 * ----------------
 */
typedef struct IndexScan
{
    Scan        scan;
    Oid         indexid;        /* OID of index to scan */
    List       *indexqual;      /* list of index quals (usually OpExprs) */
    List       *indexqualorig;  /* the same in original form */
    List       *indexorderby;   /* list of index ORDER BY exprs */
    List       *indexorderbyorig;   /* the same in original form */
    List       *indexorderbyops;    /* OIDs of sort ops for ORDER BY exprs */
    ScanDirection indexorderdir;    /* forward or backward or don't care */
} IndexScan;
```

从上面来看好像没有什么问题，`ORDER BY` 字句中的表达式包含索引时，那么 `indexorderby` 就不应该为空。那么这个是不是一个 bug 呢？我们接着分析。既然这个地方 `indexorderby` 为空，那么我们来看看何时创建的 `IndexScan` 结构，针对 `indexorderby` 又进行了什么处理。

通过调试，我发现在 `create_indexscan_plan()` 函数中有处理，如下所示：

```c
static Scan *
create_indexscan_plan(PlannerInfo *root,
                      IndexPath *best_path,
                      List *tlist,
                      List *scan_clauses,
                      bool indexonly)
{
    [...]

    /*
     * Extract the index qual expressions (stripped of RestrictInfos) from the
     * IndexClauses list, and prepare a copy with index Vars substituted for
     * table Vars.  (This step also does replace_nestloop_params on the
     * fixed_indexquals.)
     */
    fix_indexqual_references(root, best_path,
                             &stripped_indexquals,
                             &fixed_indexquals);

    /*
     * Likewise fix up index attr references in the ORDER BY expressions.
     */
    fixed_indexorderbys = fix_indexorderby_references(root, best_path);

    [...]
}
```

函数 `fix_indexorderby_references()` 定义如下：

```
/*
 * fix_indexorderby_references
 *    Adjust indexorderby clauses to the form the executor's index
 *    machinery needs.
 *
 * This is a simplified version of fix_indexqual_references.  The input is
 * bare clauses and a separate indexcol list, instead of IndexClauses.
 */
static List *
fix_indexorderby_references(PlannerInfo *root, IndexPath *index_path)
{
    IndexOptInfo *index = index_path->indexinfo;
    List       *fixed_indexorderbys;
    ListCell   *lcc,
               *lci;

    fixed_indexorderbys = NIL;

    forboth(lcc, index_path->indexorderbys, lci, index_path->indexorderbycols)
    {
        Node       *clause = (Node *) lfirst(lcc);
        int         indexcol = lfirst_int(lci);

        clause = fix_indexqual_clause(root, index, indexcol, clause, NIL);
        fixed_indexorderbys = lappend(fixed_indexorderbys, clause);
    }

    return fixed_indexorderbys;
}
```

然而，这里的 `index_path->indexorderbys` 和 `index_path->indexorderbycols` 均为空，我们接着分析 `index_path`。`IndexPath` 定义如下所示：

```c
/*
 * [...]
 * 'indexorderbys', if not NIL, is a list of ORDER BY expressions that have
 * been found to be usable as ordering operators for an amcanorderbyop index.
 * The list must match the path's pathkeys, ie, one expression per pathkey
 * in the same order.  These are not RestrictInfos, just bare expressions,
 * since they generally won't yield booleans.  It's guaranteed that each
 * expression has the index key on the left side of the operator.
 *
 * 'indexorderbycols' is an integer list of index column numbers (zero-based)
 * of the same length as 'indexorderbys', showing which index column each
 * ORDER BY expression is meant to be used with.  (There is no restriction
 * on which index column each ORDER BY can be used with.)
 * [...]
 */
typedef struct IndexPath
{
    Path        path;
    IndexOptInfo *indexinfo;
    List       *indexclauses;
    List       *indexorderbys;
    List       *indexorderbycols;
    ScanDirection indexscandir;
    Cost        indextotalcost;
    Selectivity indexselectivity;
} IndexPath;
```

从上面我们可以看到一个关键的信息 `ordering operators`，在官网上搜索 `ordering operators` 关键字，我们可以找到 [Index Scanning][] 和 [Interfacing Extensions to Indexes][] 里面有相关的描述。

> Some access methods return index entries in a well-defined order, others do not. There are actually two different ways that an access method can support sorted output:
>
>   * Access methods that always return entries in the natural ordering of their data (such as btree) should set amcanorder to true. Currently, such access methods must use btree-compatible strategy numbers for their equality and ordering operators.
>
>   * Access methods that support ordering operators should set amcanorderbyop to true. This indicates that the index is capable of returning entries in an order satisfying ORDER BY index_key operator constant. Scan modifiers of that form can be passed to amrescan as described previously.

一些访问方法以明确定义的顺序返回索引条目，而另一些则没有。实际上，访问方法可以支持排序输出有两种不同的方式：
* 始终以数据的自然顺序返回条目的访问方法（例如 btree）应将 `amcanorder` 设置为 `true`。目前，此类访问方法必须使用与 btree 兼容的策略编号作为其相等和排序运算符
* 支持排序运算符的访问方法应将 `amcanorderbyop` 设置为 `true`。这表明索引能够以满足 `ORDER BY index_key` 运算符常量的顺序返回条目。

> Some index access methods (currently, only GiST and SP-GiST) support the concept of ordering operators. What we have been discussing so far are search operators. A search operator is one for which the index can be searched to find all rows satisfying `WHERE indexed_column operator constant`. Note that nothing is promised about the order in which the matching rows will be returned. In contrast, an ordering operator does not restrict the set of rows that can be returned, but instead determines their order. An ordering operator is one for which the index can be scanned to return rows in the order represented by `ORDER BY indexed_column operator constant`. The reason for defining ordering operators that way is that it supports nearest-neighbor searches, if the operator is one that measures distance. For example, a query like
>
>     SELECT * FROM places ORDER BY location <-> point '(101,456)' LIMIT 10;
>
> finds the ten places closest to a given target point. A GiST index on the location column can do this efficiently because <-> is an ordering operator.
>
> While search operators have to return Boolean results, ordering operators usually return some other type, such as float or numeric for distances. This type is normally not the same as the data type being indexed. To avoid hard-wiring assumptions about the behavior of different data types, the definition of an ordering operator is required to name a B-tree operator family that specifies the sort ordering of the result data type. As was stated in the previous section, B-tree operator families define PostgreSQL's notion of ordering, so this is a natural representation. Since the point `<->` operator returns float8, it could be specified in an operator class creation command like this:
>
>     OPERATOR 15    <-> (point, point) FOR ORDER BY float_ops
>
> where `float_ops` is the built-in operator family that includes operations on float8. This declaration states that the index is able to return rows in order of increasing values of the `<->` operator.

一些索引访问方法（目前只有 GiST 和 SP-GiST）支持排序运算符的概念。搜索运算符是一种可以搜索索引以找到满足 `WHERE indexed_column operator constant` 的所有行的运算符。对于返回的记录其顺序可能是随机的。相反，排序运算符不限制可以返回的记录，而是确定它们的顺序。排序运算符是一种可以扫描其索引以按 `ORDER BY indexed_column operator constant` 表示的顺序返回行的运算符。以这种方式定义排序运算符的原因是，如果运算符是测量距离的运算符，它可以支持最近邻搜索。例如：

```sql
SELECT * FROM places ORDER BY location <-> point '(101,456)' LIMIT 10;
```

找到最接近给定目标点的十个地点。`location` 列上的 GiST 索引可以有效地做到这一点，因为 `<->` 是一个排序运算符。

搜索运算符必须返回 `boolean` 类型的值，排序运算符通常返回其它类型，如代表距离的 `float` 或 `numeric` 类型。这种类型通常与被索引的数据类型不同。

分析到这里我们大致可以知道为什么之前的 `ORDER BY index_key op constant` 这里在 `IndexScan` 中的 `indexorderby` 为空了，因为之前的示例中的索引上面的操作并不支持排序运算符，因此为空。我们可以通过下面的示例来进行验证。

```sql
CREATE TABLE tbl01(id int primary key, location point);
INSERT INTO tbl01 VALUES (1, '(40, 50)');
INSERT INTO tbl01 VALUES (2, '(30, 20)');
INSERT INTO tbl01 VALUES (3, '(10, 24)');
CREATE INDEX ON tbl01 USING gist(location);
```

基于上面的示例，当我们执行 `SELECT * FROM tbl01 ORDER BY location <-> point '(0, 0)'` 查询时，`IndexScan` 中的 `indexorderby` 将不为空。

## 总结

按照文档来说，PostgreSQL 索引有查找运算符（Search Operator）和排序运算符（Ordering Operator）。我们通常使用到的是查找运算符，排序运算符接触的比较少（至少对于我来说是这样的）。

* 查找运算符：用于查询符合条件的记录，返回记录的顺序是随机的，即有多个记录的值等于查找键，这些记录在第一次可能以 `a, b, c` 的顺序返回，第二次则以 `c, a, b` 的顺序返回。查找运算符的返回值是 `boolean` 类型。
* 排序运算符：用于对记录进行排序，返回记录的顺序是确定的，多次执行都是一样的。排序运算符的返回值通常是其它类型，如代表距离的 `float` 或 `numeric` 类型。

## 参考

[1] https://www.postgresql.org/docs/current/index-scanning.html
[2] https://www.postgresql.org/docs/current/xindex.html
[3] 《PostgreSQL 修炼之道 - 从小工到专家》

<div class="just-for-fun">
笑林广记 - 考监

一监生过国学门，闻祭酒方盛怒两生而治之，问门上人者，然则打欤？罚欤？镦锁欤？
答曰：“出题考文。”
生即咈然，曰：“咦，罪不至此。”
</div>


[Index Scanning]: https://www.postgresql.org/docs/current/index-scanning.html
[Interfacing Extensions to Indexes]: https://www.postgresql.org/docs/current/xindex.html
[Ordering Operators]: https://www.postgresql.org/docs/current/xindex.html#XINDEX-ORDERING-OPS
