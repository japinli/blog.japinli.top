---
title: "PostgreSQL 行类型规则导出错误"
date: 2022-01-14 22:09:24 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

最近在浏览邮件列表时发现通过 pg_dump 导出带有行类型的规则导出之后无法导入到数据库中，已确认为 bug，目前已被修复。

	commit 43c2175121c829c8591fc5117b725f1f22bfb670
	Author: Tom Lane <tgl@sss.pgh.pa.us>
	Date:   Thu Jan 13 17:49:25 2022 -0500

	    Fix ruleutils.c's dumping of whole-row Vars in more contexts.

	    Commit 7745bc352 intended to ensure that whole-row Vars would be
	    printed with "::type" decoration in all contexts where plain
	    "var.*" notation would result in star-expansion, notably in
	    ROW() and VALUES() constructs.  However, it missed the case of
	    INSERT with a single-row VALUES, as reported by Timur Khanjanov.

	    Nosing around ruleutils.c, I found a second oversight: the
	    code for RowCompareExpr generates ROW() notation without benefit
	    of an actual RowExpr, and naturally it wasn't in sync :-(.
	    (The code for FieldStore also does this, but we don't expect that
	    to generate strictly parsable SQL anyway, so I left it alone.)

	    Back-patch to all supported branches.

	    Discussion: https://postgr.es/m/efaba6f9-4190-56be-8ff2-7a1674f9194f@intrans.baku.az

<!--more-->

## 现象

首先我们创建两张表和一条规则，如下所示。

```sql
CREATE TABLE test(a int);
CREATE TABLE test_log(old test);
CREATE RULE del AS ON DELETE TO test DO INSERT INTO test_log VALUES(old);
```

当我们向其中插入、删除数据一切正常。

```
mydb=# INSERT INTO test VALUES (1);
INSERT 0 1
mydb=# DELETE FROM test;
DELETE 1
mydb=# SELECT * FROM test_log;
 old
-----
 (1)
(1 row)
```

当我们尝试使用 pg_dump 导出时，一切正常，但是通过 psql 导入时则出现错误了。

```
$ pg_dump mydb -f mydb.sql
$ psql tdb -f mydb.sql
[...]
psql:mydb.sql:68: ERROR:  column "old" is of type public.test but expression is of type integer
LINE 3:   VALUES (old.*);
                  ^
HINT:  You will need to rewrite or cast the expression.
```

从 mydb.sql 文件中可以看到错误正好发生在 `CREATE RULE` 位置处，如下所示：

```sql
CREATE RULE del AS
    ON DELETE TO public.test DO  INSERT INTO public.test_log (old)
  VALUES (old.*);
```

## 分析

正如 Tom Lane 在提交日志中所说，提交记录 7745bc352 确保在所有上下文中，当纯 `var.*` 符号会导致 `*` 扩展时，尤其是在 row() 和 VALUES() 构造中时，使用 `::type` 装饰来打印整行变量。然而，正如 Timur Khanjanov 所报告的那样，它忽略了使用单行值插入的情况。

```diff
diff --git a/src/backend/utils/adt/ruleutils.c b/src/backend/utils/adt/ruleutils.c
index 51391f6a4e..3388f7c17e 100644
--- a/src/backend/utils/adt/ruleutils.c
+++ b/src/backend/utils/adt/ruleutils.c
@@ -391,6 +391,8 @@ static void appendContextKeyword(deparse_context *context, const char *str,
 static void removeStringInfoSpaces(StringInfo str);
 static void get_rule_expr(Node *node, deparse_context *context,
 			  bool showimplicit);
+static void get_rule_expr_toplevel(Node *node, deparse_context *context,
+					   bool showimplicit);
 static void get_oper_expr(OpExpr *expr, deparse_context *context);
 static void get_func_expr(FuncExpr *expr, deparse_context *context,
 			  bool showimplicit);
@@ -4347,10 +4349,10 @@ get_values_def(List *values_lists, deparse_context *context)

 			/*
 			 * Strip any top-level nodes representing indirection assignments,
-			 * then print the result.
+			 * then print the result.  Whole-row Vars need special treatment.
 			 */
-			get_rule_expr(processIndirection(col, context, false),
-						  context, false);
+			get_rule_expr_toplevel(processIndirection(col, context, false),
+								   context, false);
 		}
 		appendStringInfoChar(buf, ')');
 	}
@@ -4771,7 +4773,8 @@ get_target_list(List *targetList, deparse_context *context,
 		 * the top level of a SELECT list it's not right (the parser will
 		 * expand that notation into multiple columns, yielding behavior
 		 * different from a whole-row Var).  We need to call get_variable
-		 * directly so that we can tell it to do the right thing.
+		 * directly so that we can tell it to do the right thing, and so that
+		 * we can get the attribute name which is the default AS label.
 		 */
 		if (tle->expr && (IsA(tle->expr, Var)))
 		{
@@ -7515,7 +7518,8 @@ get_rule_expr(Node *node, deparse_context *context,
 						!tupdesc->attrs[i]->attisdropped)
 					{
 						appendStringInfoString(buf, sep);
-						get_rule_expr(e, context, true);
+						/* Whole-row Vars need special treatment here */
+						get_rule_expr_toplevel(e, context, true);
 						sep = ", ";
 					}
 					i++;
@@ -7941,6 +7945,27 @@ get_rule_expr(Node *node, deparse_context *context,
 	}
 }

+/*
+ * get_rule_expr_toplevel		- Parse back a toplevel expression
+ *
+ * Same as get_rule_expr(), except that if the expr is just a Var, we pass
+ * istoplevel = true not false to get_variable().  This causes whole-row Vars
+ * to get printed with decoration that will prevent expansion of "*".
+ * We need to use this in contexts such as ROW() and VALUES(), where the
+ * parser would expand "foo.*" appearing at top level.  (In principle we'd
+ * use this in get_target_list() too, but that has additional worries about
+ * whether to print AS, so it needs to invoke get_variable() directly anyway.)
+ */
+static void
+get_rule_expr_toplevel(Node *node, deparse_context *context,
+					   bool showimplicit)
+{
+	if (node && IsA(node, Var))
+		(void) get_variable((Var *) node, 0, true, context);
+	else
+		get_rule_expr(node, context, showimplicit);
+}
+
```

从代码层面来看，主要的修改在于针对 `get_rule_expr()` 函数进行了封装，当 `node` 参数仅仅是一个 `Var` 时，函数 `get_variable()` 的 `istoplevel` 参数被设置为 `true`，以便其被正确的处理。


<div class="just-for-fun">
笑林广记 - 公子封君

有公子兼封君者，父对之乃欣羡不已。
讶问其故，曰：“你的爷既胜过我的爷，你的儿又胜过我的儿。”
</div>


[7745bc352]: https://github.com/postgres/postgres/commit/7745bc352a82bd588be986479c7aabc3b076a375
