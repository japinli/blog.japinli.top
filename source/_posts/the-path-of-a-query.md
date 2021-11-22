---
title: "PostgreSQL SQL 查询路径"
date: 2021-11-21 17:09:42 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 源码
---

在 PostgreSQL 中，查询一般会经历以下几个阶段：

1. 应用程序连接到 PostgreSQL 并发送查询请求，随后等待返回结果。
2. 解析器（parser）检查应用程序传输的查询的语法是否正确并创建查询树（query tree）。
3. 重写系统（rewrite system）采用解析器阶段创建的查询树，并查找存储在系统表中的规则来重写查询树，例如视图。
4. 规划器/优化器（planner/optimizer）采用（重写的）查询树并创建一个查询计划，该计划将作为执行器（executor）的输入。
   它首先创建得到相同结果的所有路径。例如，在表上有索引，那么将会创建两个查询路径：顺序扫描和索引扫描。接下来估计每条路径的执行成本并选择最便宜的路径，将最便宜的路径扩展为执行器可以使用的完整计划。
5. 执行器递归地遍历计划树并以计划表示的方式检索行。执行器在扫描表时会使用存储系统、执行排序和连接、估算条件并最后归还得到的行。

## 建立连接

PostgreSQL 采用客户端服务器模型实现，针对每一个客户端的连接，它将为其创建一个后端服务进程。由于我们不能提前知道有多少了连接，因此我们必须使用一个主进程在每次连接请求时创建一个后端服务进程。主进程是一个被称为 `postmaster` 的进程，它在一个特定的 TCP/IP 端口监听连接请求。当它监测到连接请求时，它将创建一个后端进程。这些后端进程使用信号量和共享内存相互通信并与实例的其他进程通信，以确保整个并发数据访问过程中的数据完整性。

如下所示，当我们启动数据库后一般会有如下进程。

```shell
px@ubuntu:~/Codes/postgres/Debug$ ps -ef | grep postgres
px       1785509       1  0 17:34 ?        00:00:00 /home/px/Codes/postgres/Debug/pg/bin/postgres
px       1785510 1785509  0 17:34 ?        00:00:00 postgres: checkpointer
px       1785511 1785509  0 17:34 ?        00:00:00 postgres: background writer
px       1785513 1785509  0 17:34 ?        00:00:00 postgres: walwriter
px       1785514 1785509  0 17:34 ?        00:00:00 postgres: autovacuum launcher
px       1785515 1785509  0 17:34 ?        00:00:00 postgres: stats collector
px       1785516 1785509  0 17:34 ?        00:00:00 postgres: logical replication launcher
px       1788661  578230  0 17:53 pts/8    00:00:00 grep --color=auto postgres
```

此时，若我们在另一个终端通过 psql 连接数据库，其进程信息如下：

```shell
px@ubuntu:~/Codes/postgres/Debug$ ps -ef | grep postgres
px       1785509       1  0 17:34 ?        00:00:00 /home/px/Codes/postgres/Debug/pg/bin/postgres
px       1785510 1785509  0 17:34 ?        00:00:00 postgres: checkpointer
px       1785511 1785509  0 17:34 ?        00:00:00 postgres: background writer
px       1785513 1785509  0 17:34 ?        00:00:00 postgres: walwriter
px       1785514 1785509  0 17:34 ?        00:00:00 postgres: autovacuum launcher
px       1785515 1785509  0 17:34 ?        00:00:00 postgres: stats collector
px       1785516 1785509  0 17:34 ?        00:00:00 postgres: logical replication launcher
px       1788933  578230  0 17:55 pts/8    00:00:00 psql postgres
px       1788934 1785509  0 17:55 ?        00:00:00 postgres: px postgres [local] idle
px       1788954 1784579  0 17:55 pts/4    00:00:00 grep --color=auto postgres
```

可以看到，后端进程中多了一个进程 ID 为 `1788934` 的进程。您可以在 psql 端通过 `pg_backend_pid()` 函数来进行验证。

```sql
postgres=# SELECT pg_backend_pid();
 pg_backend_pid
----------------
        1788934
(1 row)
```

连接建立后，客户端进程可以向其连接的后端进程发送查询。查询使用纯文本传输，即在客户端没有进行解析。后端进程解析查询，创建执行计划，执行计划，并通过在已建立的连接上传输检索到的行将它们返回给客户端。

为了验证上面的内容，我们创建 `friend` 的表并插入数据。

```sql
CREATE TABLE friend (firstname text, lastname text, age int);
INSERT INTO friend VALUES ('Sandy', 'Tom', 33);
INSERT INTO friend VALUES ('Lily', 'Jane', 23);
```

接着我们通过 psql 连接到数据库（注意需要走 TCP/IP，可以使用 `psql -h 127.0.0.1` 的方式进行连接），并利用 tcpdump 来捕获数据包。

```
$ psql -h 127.0.0.1 postgres
postgres=# SELECT firstname
postgres-# FROM friend
postgres-# WHERE age = 33;
 firstname
-----------
 Sandy
(1 row)
```

下面是 tcpdump 的输出，我们可以看到数据包中包含了我们在 psql 中输入的查询语句。

```shell
$ sudo tcpdump -X -i lo port 5432
18:17:57.376100 IP localhost.55238 > localhost.postgresql: Flags [P.], seq 50:100, ack 113, win 512, options [nop,nop,TS val 1265806437 ecr 1265755262], length 50
        0x0000:  4500 0066 313b 4000 4006 0b55 7f00 0001  E..f1;@.@..U....
        0x0010:  7f00 0001 d7c6 1538 e8dd 8ea1 7e88 14b9  .......8....~...
        0x0020:  8018 0200 fe5a 0000 0101 080a 4b72 ac65  .....Z......Kr.e
        0x0030:  4b71 e47e 5100 0000 3153 454c 4543 5420  Kq.~Q...1SELECT.
        0x0040:  6669 7273 746e 616d 650a 4652 4f4d 2066  firstname.FROM.f
        0x0050:  7269 656e 640a 5748 4552 4520 6167 6520  riend.WHERE.age.
        0x0060:  3d20 3333 3b00                           =.33;.
18:17:57.376956 IP localhost.postgresql > localhost.55238: Flags [P.], seq 113:184, ack 100, win 512, options [nop,nop,TS val 1265806438 ecr 1265806437], length 71
        0x0000:  4500 007b 4194 4000 4006 fae6 7f00 0001  E..{A.@.@.......
        0x0010:  7f00 0001 1538 d7c6 7e88 14b9 e8dd 8ed3  .....8..~.......
        0x0020:  8018 0200 fe6f 0000 0101 080a 4b72 ac66  .....o......Kr.f
        0x0030:  4b72 ac65 5400 0000 2200 0166 6972 7374  Kr.eT..."..first
        0x0040:  6e61 6d65 0000 0040 0600 0100 0000 19ff  name...@........
        0x0050:  ffff ffff ff00 0044 0000 000f 0001 0000  .......D........
        0x0060:  0005 5361 6e64 7943 0000 000d 5345 4c45  ..SandyC....SELE
        0x0070:  4354 2031 005a 0000 0005 49              CT.1.Z....I
```

下图是 PostgreSQL 数据库连接的示意图，用户终端通过应用程序连接 PostgreSQL 服务器进行查询操作，而应用服务器一般情况下都是通过 libpq 这个库来实现对 PostgreSQL 数据库的访问。

{% asset_img connection.png %}

为了方便后续查看，建议设置以下选项：

```
log_min_messages = debug5
debug_print_parse = on
debug_print_rewritten = on
debug_print_plan = on
# debug_pretty_print = on
```

上面我们通过 ps 命令看到了新进程的创建，我们也可以在日志文件中找到相应的日志。

```
2021-11-21 18:59:25.293 CST [1798570] DEBUG:  forked new backend, pid=1798903 socket=9
2021-11-21 18:59:25.300 CST [1798903] DEBUG:  InitPostgres
2021-11-21 18:59:25.301 CST [1798903] DEBUG:  my backend ID is 3
2021-11-21 18:59:25.303 CST [1798903] DEBUG:  StartTransaction(1) name: unnamed; blockState: DEFAULT; state: INPROGRESS, xid/subid/cid: 0/1/0
2021-11-21 18:59:25.314 CST [1798903] DEBUG:  CommitTransaction(1) name: unnamed; blockState: STARTED; state: INPROGRESS, xid/subid/cid: 0/1/0
2021-11-21 18:59:41.553 CST [1798903] DEBUG:  StartTransaction(1) name: unnamed; blockState: DEFAULT; state: INPROGRESS, xid/subid/cid: 0/1/0
```

## 解析器

后端进程在接收到查询请求后，首先会进行查询的解析。解析器由两部分组成：

* 定义在 `gram.y` 和 `scan.l` 文件中的解析器，它使用 Unix 的 bison 和 flex 工具实现。
* 转换过程对解析器返回的数据结构进行修改和扩充。

### 解析器

解析器必须检查查询字符串（以纯文本形式出现）的语法是否有效。 如果语法正确，则会建立并返回解析树； 否则返回错误。

词法分析其（lexer）定义在 `scan.l` 文件中，它负责识别标识符、SQL 关键字等。对于找到的每个关键字或标识符，都会生成一个标记（token）并将其传递给解析器。

解析器（parser）定义在 `gram.y` 文件中，它由一组语法规则和在触发规则时执行的操作组成。操作的代码（实际上是 C 代码）用于构建解析树。

下面就是一颗原始解析树的详细组成。

```
2021-11-21 19:42:20.293 CST [1805230] LOG:  parse tree:
2021-11-21 19:42:20.293 CST [1805230] DETAIL:  {QUERY :commandType 1 :querySource 0 :canSetTag true :utilityStmt <>
	:resultRelation 0 :hasAggs false :hasWindowFuncs false :hasTargetSRFs false
	:hasSubLinks false :hasDistinctOn false :hasRecursive false :hasModifyingCTE
	false :hasForUpdate false :hasRowSecurity false :isReturn false :cteList <>
	:rtable ({RANGETBLENTRY :alias <> :eref {ALIAS :aliasname friend :colnames
	("firstname" "lastname" "age")} :rtekind 0 :relid 16384 :relkind r
	:rellockmode 1 :tablesample <> :lateral false :inh true :inFromCl true
	:requiredPerms 2 :checkAsUser 0 :selectedCols (b 8 10) :insertedCols (b)
	:updatedCols (b) :extraUpdatedCols (b) :securityQuals <>}) :jointree {FROMEXPR
	:fromlist ({RANGETBLREF :rtindex 1}) :quals {OPEXPR :opno 96 :opfuncid 65
	:opresulttype 16 :opretset false :opcollid 0 :inputcollid 0 :args ({VAR :varno
	1 :varattno 3 :vartype 23 :vartypmod -1 :varcollid 0 :varlevelsup 0 :varnosyn
	1 :varattnosyn 3 :location 35} {CONST :consttype 23 :consttypmod -1
	:constcollid 0 :constlen 4 :constbyval true :constisnull false :location 41
	:constvalue 4 [ 33 0 0 0 0 0 0 0 ]}) :location 39}} :targetList ({TARGETENTRY
	:expr {VAR :varno 1 :varattno 1 :vartype 1043 :vartypmod 34 :varcollid 100
	:varlevelsup 0 :varnosyn 1 :varattnosyn 1 :location 7} :resno 1 :resname
	firstname :ressortgroupref 0 :resorigtbl 16384 :resorigcol 1 :resjunk false})
	:override 0 :onConflict <> :returningList <> :groupClause <> :groupDistinct
	false :groupingSets <> :havingQual <> :windowClause <> :distinctClause <>
	:sortClause <> :limitOffset <> :limitCount <> :limitOption 0 :rowMarks <>
	:setOperations <> :constraintDeps <> :withCheckOptions <> :stmt_location 0
	:stmt_len 43}
```

我们来看看 PostgreSQL 是如何识别标识符的。在 `scan.l` 文件中，您可以找到如下内容：

```
identifier      {ident_start}{ident_cont}*

{identifier}    {
                    int         kwnum;
                    char       *ident;

                    SET_YYLLOC();

                    /* Is it a keyword? */
                    kwnum = ScanKeywordLookup(yytext,
                                              yyextra->keywordlist);
                    if (kwnum >= 0)
                    {
                        yylval->keyword = GetScanKeyword(kwnum,
                                                         yyextra->keywordlist);
                        return yyextra->keyword_tokens[kwnum];
                    }

                    /*
                     * No.  Convert the identifier to lower case, and truncate
                     * if necessary.
                     */
                    ident = downcase_truncate_identifier(yytext, yyleng, true);
                    yylval->str = ident;
                    return IDENT;
                }

{other}         {
                    SET_YYLLOC();
                    return yytext[0];
                }

<<EOF>>         {
                    SET_YYLLOC();
                    yyterminate();
                }
```

您可以结合[文档](https://www.postgresql.org/docs/14/sql-syntax-lexical.html#SQL-SYNTAX-IDENTIFIERS)来阅读这部分内容。标识符由 `ident_start` 和 `ident_cont` 两部分组成，它们的主要区别在于 `ident_start` 里面不包含数字，即标识符不能以数字开头。

接着，我们来看看解析器中 `SELECT` 触发的操作。

```
simple_select:
            SELECT opt_all_clause opt_target_list
            into_clause from_clause where_clause
            group_clause having_clause window_clause
                {
                    SelectStmt *n = makeNode(SelectStmt);
                    n->targetList = $3;
                    n->intoClause = $4;
                    n->fromClause = $5;
                    n->whereClause = $6;
                    n->groupClause = ($7)->list;
                    n->groupDistinct = ($7)->distinct;
                    n->havingClause = $8;
                    n->windowClause = $9;
                    $$ = (Node *)n;
                }
```

这里仅给出了部分语法规则的实现，`SELECT` 语句还包含其他语法规则，您可以在 `gram.y` 文件的 `simple_select` 中找到。从上面我们可以看到，解析器将 `SELECT` 语句的解析结果存放到了 `SelectStmt` 结构中，`SelectStmt` 的定义如下：

```c
typedef struct SelectStmt
{
    NodeTag     type;

    /*
     * These fields are used only in "leaf" SelectStmts.
     */
    List       *distinctClause; /* NULL, list of DISTINCT ON exprs, or
                                 * lcons(NIL,NIL) for all (SELECT DISTINCT) */
    IntoClause *intoClause;     /* target for SELECT INTO */
    List       *targetList;     /* the target list (of ResTarget) */
    List       *fromClause;     /* the FROM clause */
    Node       *whereClause;    /* WHERE qualification */
    List       *groupClause;    /* GROUP BY clauses */
    bool        groupDistinct;  /* Is this GROUP BY DISTINCT? */
    Node       *havingClause;   /* HAVING conditional-expression */
    List       *windowClause;   /* WINDOW window_name AS (...), ... */

    /*
     * In a "leaf" node representing a VALUES list, the above fields are all
     * null, and instead this field is set.  Note that the elements of the
     * sublists are just expressions, without ResTarget decoration. Also note
     * that a list element can be DEFAULT (represented as a SetToDefault
     * node), regardless of the context of the VALUES list. It's up to parse
     * analysis to reject that where not valid.
     */
    List       *valuesLists;    /* untransformed list of expression lists */

    /*
     * These fields are used in both "leaf" SelectStmts and upper-level
     * SelectStmts.
     */
    List       *sortClause;     /* sort clause (a list of SortBy's) */
    Node       *limitOffset;    /* # of result tuples to skip */
    Node       *limitCount;     /* # of result tuples to return */
    LimitOption limitOption;    /* limit type */
    List       *lockingClause;  /* FOR UPDATE (list of LockingClause's) */
    WithClause *withClause;     /* WITH clause */

    /*
     * These fields are used only in upper-level SelectStmts.
     */
    SetOperation op;            /* type of set op */
    bool        all;            /* ALL specified? */
    struct SelectStmt *larg;    /* left child */
    struct SelectStmt *rarg;    /* right child */
    /* Eventually add fields for CORRESPONDING spec here */
} SelectStmt;
```

解析阶段所用到的数据类型基本上都定义在 `src/include/nodes/parsenodes.h` 文件中，如 `ResTarget`、`RangeVar`、和 `ColumnRef` 等。

### 转换过程

解析器阶段仅使用有关 SQL 语法结构的固定规则创建解析树。它不会在系统目录中进行任何查找，因此不可能了解所请求操作的详细语义。解析器完成后，转换过程将解析器返回的树作为输入，并进行语义解释以了解查询引用了哪些表、函数和运算符。为表示此信息而构建的数据结构称为查询树（query tree）。

我们将原始解析与语义分析分开的原因是系统目录查找只能在事务内完成，然而，我们并不希望在收到查询字符串后立即启动事务。原始解析阶段足以识别事务控制命令（`BEGIN`、`ROLLBACK` 等），然后无需任何进一步分析即可正确执行这些命令。一旦我们知道我们正在处理一个实际的查询（例如 `SELECT` 或 `UPDATE`），如果我们还没有进入一个事务，就可以开始一个事务。只有这样才能调用转换过程。

转换过程创建的查询树在大多数地方与原始解析树在结构上类似，但在细节上有很多不同。例如，解析树中的 `FuncCall` 节点表示在语法上看起来像函数调用的东西。这可能会转换为 `FuncExpr` 或 `Aggref` 节点，具体取决于引用的名称是普通函数还是聚合函数。此外，有关列的实际数据类型和表达式结果的信息会添加到查询树中。

转换过程则是通过一系列 `transformXXX()` 函数实现的，它从顶层的 `transformTopLevelStmt()` 函数开始，如果需要将针对 `SELECT INTO` 语句进行处理，最终到 `transformStmt()` 函数，该函数内部主要是一个 `switch ... case ...` 语句，针对不同的语句调用对应的 `transform` 函数，最后将返回一个查询树（query tree）。

## 规则系统

PostgreSQL 支持强大的规则系统来规范视图和模糊视图更新。最初的 PostgreSQL 规则系统由两个实现组成：

* 第一个使用行级（row level）处理工作，并在执行程序的深处实现。每当访问单个行时，就会调用规则系统。这个实现在 1995 年被删除，当时伯克利 Postgres 项目的最后一个正式版本被转换成 Postgres95。
* 规则系统的第二种实现是一种称为查询重写的技术。重写系统是一个存在于解析器阶段和计划器/优化器之间的模块。

关于查询重写在 [PostgreSQL 文档](https://www.postgresql.org/docs/14/rules.html)中有详细的说明，这也是一个比较大的主题，这里我们简要介绍一下。

查询重写通过函数 `QueryRewrite()` 实现，它的输入和输出都是查询树，即树中的表示或语义细节级别没有变化。您可以把它认为是一种宏扩展。`QueryRewrite()` 函数分为三个步骤：

1. 应用所有非 `SELECT` 规则，这可能得到 0 个或多个查询树。
2. 对每个查询应用 RIR 规则。
3. 确定哪个结果查询应该设置命令结果标签；并相应地更新 `canSetTag` 字段。

## 计划器/优化器

计划器/优化器的任务是创建一个最佳的执行计划。一个给定的 SQL 查询（今后称为查询树）实际上可以有多种执行方式，每种方式都将产生相同的结果。如果在计算上可行，查询优化器将检查这些可能的执行计划中的每一个，最终选择预期运行速度最快的执行计划。

在某些情况下，检查一个查询所有可能的执行方式会耗费非常多的时间和内存空间。特别是当涉及大量表做连接操作的时候。为了能在合理的时间内给出一个合理的（不一定是最优的）查询计划，当连接数量超过 [geqo_threshold](https://www.postgresql.org/docs/14/runtime-config-query.html#GUC-GEQO-THRESHOLD) 时，PostgreSQL 将使用一种[遗传查询优化器](https://www.postgresql.org/docs/14/geqo.html)。

计划器的搜索过程实际上使用称为路径（path）的数据结构，这些数据结构只是计划的简化表示，仅包含规划器做出决策所需的信息。在确定最便宜的路径后，将构建一个完整的计划树以传递给执行者。

## 执行器

## 参考

[1] https://www.postgresql.org/docs/14/query-path.html
[2] https://momjian.us/main/writings/pgsql/internalpics.pdf

<div class="just-for-fun">
笑林广记 -
</div>
