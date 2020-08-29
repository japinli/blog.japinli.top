---
title: PostgreSQL CREATE TABLE 语法分析
date: 2019-05-12 22:57:43 +0800
category: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

PostgreSQL 采用 flex 进行词法分析，随后利用 yacc 进行语法分析，其词法与语法分析在 scan.l 和 gram.y 文件中实现。本文主要针对 PostgreSQL 的建表语句 `CREATE TABLE` 来分析 PostgreSQL 数据库的词法、语法分析，并简要介绍整个 PostgreSQL 数据库的执行过程。

<!-- more -->

## 语法分析

PostgreSQL 的词法以及语法分析相关的文件存放在 `src/include/parser/` 和 `src/backend/parser` 目录下，上文所介绍的 scan.l 和 gram.y 文件即在 `src/backend/parser` 目录中。本文对于词法分析不做详细介绍，PostgreSQL 将词法分析的结果交给语法分析模块进行语法分析，而语法分析的关键代码即在 gram.y 文件中。下面我们来看看 gram.y 文件的组成，该文件分为三个部分：声明部分 (declarations)、语法规则 (rules) 以及程序实现 (programs)。在声明部分其引入了 PostgreSQL 相关的头文件、函数声明等；第二部分规则给出了 PostgreSQL 数据库中 SQL 语句的定义；第三部分则包含了语法解析的初始化实现、节点的创建等函数定义。

现在，我们主要来看看规则部分的定义。PostgreSQL 关于 SQL 的规则定义开始于 stmtblock，其定义如下：

```
/*
 *  The target production for the whole parse.
 */
stmtblock:  stmtmulti
            {
                pg_yyget_extra(yyscanner)->parsetree = $1;
            }
        ;

/*
 * At top level, we wrap each stmt with a RawStmt node carrying start location
 * and length of the stmt's text.  Notice that the start loc/len are driven
 * entirely from semicolon locations (@2).  It would seem natural to use
 * @1 or @3 to get the true start location of a stmt, but that doesn't work
 * for statements that can start with empty nonterminals (opt_with_clause is
 * the main offender here); as noted in the comments for YYLLOC_DEFAULT,
 * we'd get -1 for the location in such cases.
 * We also take care to discard empty statements entirely.
 */
stmtmulti:  stmtmulti ';' stmt
                {
                    if ($1 != NIL)
                    {
                        /* update length of previous stmt */
                        updateRawStmtEnd(llast_node(RawStmt, $1), @2);
                    }
                    if ($3 != NULL)
                        $$ = lappend($1, makeRawStmt($3, @2 + 1));
                    else
                        $$ = $1;
                }
            | stmt
                {
                    if ($1 != NULL)
                        $$ = list_make1(makeRawStmt($1, 0));
                    else
                        $$ = NIL;
                }
        ;
```

PostgreSQL 的规则从 `stmtblock` 开始，它被定义为 `stmtmulti` 对象，其中 `$1` 即代表 `stmtmulti`，它最终被复制给 `base_yy_extra_type` 的 `parsetree` 成员，而 `parsetree` 是一个链表，它存储的是解析之后的原始解析树对象。`stmtmulti` 的定义则采用递归的方式进行定义，它可以是 `stmtmulti` 加上 `stmt` 也可以是单独的 `stmt`，但最终是以 `stmt` 对象来解析，而多个 `stmt` 对象则是通过链表链接起来的。

接下来，我们看看 `stmt` 是如何定义的。

```
stmt :
            AlterEventTrigStmt
            | AlterCollationStmt
            | AlterDatabaseStmt
            | AlterDatabaseSetStmt
            | AlterDefaultPrivilegesStmt
            | AlterDomainStmt
            | AlterEnumStmt
            | AlterExtensionStmt
            | AlterExtensionContentsStmt
            | AlterFdwStmt
            | AlterForeignServerStmt
            | AlterForeignTableStmt
              ...
            | CopyStmt
            | CreateAmStmt
            | CreateAsStmt
            | CreateAssertionStmt
            | CreateCastStmt
            | CreateConversionStmt
            | CreateDomainStmt
            | CreateExtensionStmt
            | CreateFdwStmt
            | CreateForeignServerStmt
            | CreateForeignTableStmt
            | CreateFunctionStmt
              ...
            | SelectStmt
            | TransactionStmt
            | TruncateStmt
            | UnlistenStmt
            | UpdateStmt
            | VacuumStmt
            | VariableResetStmt
            | VariableSetStmt
            | VariableShowStmt
            | ViewStmt
            | /*EMPTY*/
                { $$ = NULL; }
        ;
```

当你看到这个的时候是否有中似曾相识的感觉？`stmt` 包含了 PostgreSQL 所支持的 SQL 语句的语法定义，例如我们输入 `SELECT * FROM pg_class;` 时，它将通过 `stmt` 转到 `SelectStmt` 的定义处进行解析，而语句在解析完之后都会转换为对应的 `SelectStmt` 结构用于后续进行查询计划的生成。

现在我们针对 PostgreSQL 的建表语句进行分析，关于 [`CREATE TABLE`](https://www.postgresql.org/docs/devel/sql-createtable.html) 的语法可以在官方文档上查询。`CREATE TABLE` 的语法分析如下所示：

```
CreateStmt: CREATE OptTemp TABLE qualified_name '(' OptTableElementList ')'
            OptInherit OptPartitionSpec table_access_method_clause OptWith
            OnCommitOption OptTableSpace
                {
                    CreateStmt *n = makeNode(CreateStmt);
                    $4->relpersistence = $2;
                    n->relation = $4;
                    n->tableElts = $6;
                    n->inhRelations = $8;
                    n->partspec = $9;
                    n->ofTypename = NULL;
                    n->constraints = NIL;
                    n->accessMethod = $10;
                    n->options = $11;
                    n->oncommit = $12;
                    n->tablespacename = $13;
                    n->if_not_exists = false;
                    $$ = (Node *)n;
                }
				...
```

如上所示，`CREATE TABLE` 由关键字 `CREATE` 和 `TABLE` 以及其他一些语法解析对象组成。

* __OptTemp__ - 临时表的选项，表明该表是否为临时表，此外该选项还可以指定创建无日志表。
* __qualified_name__ - 表名，可以指定表所在的 schema。
* __OptTableElementList__ - 由链表构成的表属性列。
* __OptInherit__ - 表继承相关信息。
* __OptPartitionSpec__ - 表分区相关信息。
* __table_access_method_clause__ - 该选项是计划在 PostgreSQL 12 版本中给出的用于替换存储引擎的选项。
* __OptWith__ - `WITH` 选项，用于指定表的一些特定选项，例如 `fillfactor`、`parallel_workers` 等。
* __OnCommitOption__ - 指定数据在提交时的行为。
* __OptTableSpace__ - 指定表空间信息。

从上面的语法分析可以看到，`CREATE TABLE` 语句在执行完语法分析之后将转换为 `CreateStmt` 对象，其定义如下所示：

``` c
/* ----------------------
 *      Create Table Statement
 *
 * NOTE: in the raw gram.y output, ColumnDef and Constraint nodes are
 * intermixed in tableElts, and constraints is NIL.  After parse analysis,
 * tableElts contains just ColumnDefs, and constraints contains just
 * Constraint nodes (in fact, only CONSTR_CHECK nodes, in the present
 * implementation).
 * ----------------------
 */

typedef struct CreateStmt
{
    NodeTag     type;
    RangeVar   *relation;       /* relation to create */
    List       *tableElts;      /* column definitions (list of ColumnDef) */
    List       *inhRelations;   /* relations to inherit from (list of
                                 * inhRelation) */
    PartitionBoundSpec *partbound;  /* FOR VALUES clause */
    PartitionSpec *partspec;    /* PARTITION BY clause */
    TypeName   *ofTypename;     /* OF typename */
    List       *constraints;    /* constraints (list of Constraint nodes) */
    List       *options;        /* options from WITH clause */
    OnCommitAction oncommit;    /* what do we do at COMMIT? */
    char       *tablespacename; /* table space to use, or NULL */
    char       *accessMethod;   /* table access method */
    bool        if_not_exists;  /* just do nothing if it already exists? */
} CreateStmt;
```

PostgreSQL 在实现时对于内部节点采用了继承的思想，拿我们上面的 `CreateStmt` 结构体来说，它的第一个成员为 `NodeTag` 类型，当我们通过 `makeNode(CreateStmt)` 函数创建 `CreateStmt` 对象时，其内部通过一个 `switch` 来判断具体的节点类型，并分配存储空间，而在之后都转换为 `Node` 类型进行使用，如来 `$$ = (Node *) n;` 所示。

假如我们有如下的建表语句：

``` sql
CREATE TABLE test (id int, info text);
```

根据上面的语法规则，由于 `OptTemp` 部分没有指定因此其值为 `RELPERSISTENCE_PERMANENT`，`qualified_name` 则是一个 `RangeVar` 对象，其结构如下：

``` c
/*
 * RangeVar - range variable, used in FROM clauses
 *
 * Also used to represent table names in utility statements; there, the alias
 * field is not used, and inh tells whether to apply the operation
 * recursively to child tables.  In some contexts it is also useful to carry
 * a TEMP table indication here.
 */
typedef struct RangeVar
{
    NodeTag     type;
    char       *catalogname;    /* the catalog (database) name, or NULL */
    char       *schemaname;     /* the schema name, or NULL */
    char       *relname;        /* the relation/sequence name */
    bool        inh;            /* expand rel by inheritance? recursively act
                                 * on children? */
    char        relpersistence; /* see RELPERSISTENCE_* in pg_class.h */
    Alias      *alias;          /* table alias & optional column aliases */
    int         location;       /* token location, or -1 if unknown */
} RangeVar;
```

PostgreSQL 在解析完表名之后会将表名 `test` 存放到 `RangeVar` 对象的 `relname` 成员中，随后使用
`OptTemp` 的值更新 `RangeVar` 的 `relpersistence` 成员。

接着，PostgreSQL 对表的属性列进行解析，即 `OptTableElementList`，它对应的定义为 `TableElementList`，而 `TableElementList` 被定义为 `TableElement` 和 `TableElementList ',' TableElement`。`TableElement` 的定义如下：

```
TableElement:
            columnDef                           { $$ = $1; }
            | TableLikeClause                   { $$ = $1; }
            | TableConstraint                   { $$ = $1; }
        ;
```

从定义可以看出，SQL 语句中表的每个属性列在解析完之后都对应一个 `columnDef` 对象，如果我们为表指定了约束条件，那么就有一个对应的 `TableConstraint` 对象，如果在其中使用了 `LIKE` 的话，就对应有一个 `TableLikeClause` 对象。在本文中我们只关注第一种情况，后面两种情况的分析其实与此类似，故不做详细分析。

在解析阶段，属性列由 `ColumnDef` 进行表示，其定义如下：

``` c
typedef struct ColumnDef
{
    NodeTag     type;
    char       *colname;        /* name of column */
    TypeName   *typeName;       /* type of column */
    int         inhcount;       /* number of times column is inherited */
    bool        is_local;       /* column has local (non-inherited) def'n */
    bool        is_not_null;    /* NOT NULL constraint specified? */
    bool        is_from_type;   /* column definition came from table type */
    char        storage;        /* attstorage setting, or 0 for default */
    Node       *raw_default;    /* default value (untransformed parse tree) */
    Node       *cooked_default; /* default value (transformed expr tree) */
    char        identity;       /* attidentity setting */
    RangeVar   *identitySequence;   /* to store identity sequence name for
                                     * ALTER TABLE ... ADD COLUMN */
    char        generated;      /* attgenerated setting */
    CollateClause *collClause;  /* untransformed COLLATE spec, if any */
    Oid         collOid;        /* collation OID (InvalidOid if not set) */
    List       *constraints;    /* other constraints on column */
    List       *fdwoptions;     /* per-column FDW options */
    int         location;       /* parse location, or -1 if none/unknown */
} ColumnDef;
```

`columnDef` 的语法解析如下所示：

```
columnDef:  ColId Typename create_generic_options ColQualList
                {
                    ColumnDef *n = makeNode(ColumnDef);
                    n->colname = $1;
                    n->typeName = $2;
                    n->inhcount = 0;
                    n->is_local = true;
                    n->is_not_null = false;
                    n->is_from_type = false;
                    n->storage = 0;
                    n->raw_default = NULL;
                    n->cooked_default = NULL;
                    n->collOid = InvalidOid;
                    n->fdwoptions = $3;
                    SplitColQualList($4, &n->constraints, &n->collClause,
                                     yyscanner);
                    n->location = @1;
                    $$ = (Node *)n;
                }
        ;
```

例如，上面的示例语句将产生两个 `ColumnDef` 对象，它们通过链表组织在一起，链表的第一个节点的 `colname` 和 `typeName` 分别为 `id` 和 `int`；第二节点的 `colname` 和 `typeName` 分别为 `info` 和 `text`。

上面基本上就将示例给出的建表语法介绍完了，`CREATE TABLE` 语句解析完之后创建的 `CreateStmt` 对象将通过 `makeRawStmt()` 函数包装到 `RawStmt` 结构中，`RawStmt` 的定义如下：

``` c
/*
 *      RawStmt --- container for any one statement's raw parse tree
 *
 * Parse analysis converts a raw parse tree headed by a RawStmt node into
 * an analyzed statement headed by a Query node.  For optimizable statements,
 * the conversion is complex.  For utility statements, the parser usually just
 * transfers the raw parse tree (sans RawStmt) into the utilityStmt field of
 * the Query node, and all the useful work happens at execution time.
 *
 * stmt_location/stmt_len identify the portion of the source text string
 * containing this raw statement (useful for multi-statement strings).
 */
typedef struct RawStmt
{
    NodeTag     type;
    Node       *stmt;           /* raw parse tree */
    int         stmt_location;  /* start location, or -1 if unknown */
    int         stmt_len;       /* length in bytes; 0 means "rest of string" */
} RawStmt;
```

从 `RawStmt` 的定义可以看出，所有语句最后都被转换为 `Node *` 的指针被存放到 `stmt` 成员中。根据 `makeRowStmt()` 函数的定义也验证的我们的看法。

``` c
static RawStmt *
makeRawStmt(Node *stmt, int stmt_location)
{
    RawStmt    *rs = makeNode(RawStmt);

    rs->stmt = stmt;
    rs->stmt_location = stmt_location;
    rs->stmt_len = 0;           /* might get changed later */
    return rs;
}
```

## 执行流程

上面我们分析了 PostgreSQL 的语法分析部分，接下来我们简要介绍一下 PostgreSQL 的执行流程。首先，我们需要明确 PostgreSQL 是基于多进程开发的，每当一个连接请求过来，PostgreSQL 都将创建一个新的 `postgres` 进程用于处理用户请求，在用户将需要执行的 SQL 语句发送到后端之后，`postgres` 进程将从 `exec_simple_query()` 函数开始进行处理，其主要的流程如下：

1. 调用 `pg_parse_query()` 函数进行词法、语法分析，即我们上面介绍的内容；
2. 循环遍历解析树链表对每个语句进行处理，如果没有查询语句转步骤 7；
3. 调用 `pg_analyze_and_rewrite()` 函数对解析树分析并重写并生成查询计划；
4. 调用 `pg_plan_queries()` 对查询树进行优化并选择一条最优路径生成执行计划；
5. 创建 `Portal` 对象并调用 `PortalRun()` 函数执行查询计划。
6. 执行 `Portal` 的清理工作并转步骤 2；
7. 退出。

需要注意的是 DDL 在步骤 3 和步骤 4 时不会被重写或优化，而只是简单的在原始解析树外面包装对应的结构而已，只有到了步骤 5 时才会执行转换并生成查询计划。

## 参考

[1] https://www.postgresql.org/docs/devel/sql-createtable.html
