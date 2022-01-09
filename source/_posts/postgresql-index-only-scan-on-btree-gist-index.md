---
title: "PostgreSQL 在 btree_gist 索引上 Index Only 扫描问题"
date: 2022-01-07 18:54:54 +0800
categories: 数据库
tags:
  - PostgreSQL
---

最近在邮件列表中发现一个 [btree_gist 索引上的 Index Only 扫描问题](https://www.postgresql.org/message-id/696c995b-b37f-5526-f45d-04abe713179f@gmail.com)，该问题由 Alexander Lakhin 提交，在 `char(n)` 数据类型的 `btree_gist` 索引上会出现，本文简要记录一下该问题。

<!--more-->

## 现象

首先，我们来复现这个问题，该问题依赖于 `btree_gist` 插件，我们先安装该插件，随后新建 `chartmp` 表并向其中插入一条记录，最后我们在该列上创建一个 `gist` 索引。

```sql
CREATE EXTENSION btree_gist;

CREATE TABLE chartmp (a char(32));
INSERT INTO chartmp VALUES('31b0');

CREATE INDEX charidx ON chartmp USING gist (a);
```

我们先看看查询出来的结果。

```sql
postgres=# EXPLAIN VERBOSE SELECT *, octet_length(a) FROM chartmp WHERE a BETWEEN '31a' AND '31c';
                                QUERY PLAN
---------------------------------------------------------------------------
 Seq Scan on public.chartmp  (cost=0.00..1.02 rows=1 width=136)
   Output: a, octet_length(a)
   Filter: ((chartmp.a >= '31a'::bpchar) AND (chartmp.a <= '31c'::bpchar))
(3 rows)

postgres=# SELECT *, octet_length(a) FROM chartmp WHERE a BETWEEN '31a' AND '31c';
                a                 | octet_length
----------------------------------+--------------
 31b0                             |           32
(1 row)
```

从查询计划可以看到，现在是顺序扫描（肯定是顺序扫描啦，毕竟才一条数据嘛），由于问题是在 Index Only 扫描上，那我们势必要走 Index Only 扫描才可以复现问题，因此，我们这里禁用顺序扫描，然后在看执行结果。

```sql
postgres=# SET enable_seqscan TO off;
SET
postgres=# EXPLAIN VERBOSE SELECT *, octet_length(a) FROM chartmp WHERE a BETWEEN '31a' AND '31c';
                                     QUERY PLAN
-------------------------------------------------------------------------------------
 Index Only Scan using charidx on public.chartmp  (cost=0.12..8.15 rows=1 width=136)
   Output: a, octet_length(a)
   Index Cond: ((chartmp.a >= '31a'::bpchar) AND (chartmp.a <= '31c'::bpchar))
(3 rows)

postgres=# SELECT *, octet_length(a) FROM chartmp WHERE a BETWEEN '31a' AND '31c';
  a   | octet_length
------+--------------
 31b0 |            4
(1 row)
```

可以看到这里出来的结果与顺序扫描结果不一致。这里的主要问题是，在索引存储中将会删除末尾的空白，而 Index Only 扫描在找到匹配的键时并不会回表来获取数据，从而导致数据不一致。我们可以通过索引扫描来验证这一点。

```sql
postgres=# EXPLAIN VERBOSE SELECT *, octet_length(a) FROM chartmp WHERE a BETWEEN '31a' AND '31c';
                                   QUERY PLAN
--------------------------------------------------------------------------------
 Index Scan using charidx on public.chartmp  (cost=0.12..8.15 rows=1 width=136)
   Output: a, octet_length(a)
   Index Cond: ((chartmp.a >= '31a'::bpchar) AND (chartmp.a <= '31c'::bpchar))
(3 rows)

postgres=# SELECT *, octet_length(a) FROM chartmp WHERE a BETWEEN '31a' AND '31c';
                a                 | octet_length
----------------------------------+--------------
 31b0                             |           32
(1 row)
```

## 分析

在构建 `char(n)` 类型的 `btree_gist` 索引时，将调用 `gbt_bpchar_compress()` 函数来对将进行处理（感谢 Tom Lane 提供的分析），其定义如下。

```C
Datum
gbt_bpchar_compress(PG_FUNCTION_ARGS)
{
    GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
    GISTENTRY  *retval;

    if (tinfo.eml == 0)
    {
        tinfo.eml = pg_database_encoding_max_length();
    }

    if (entry->leafkey)
    {

        Datum       d = DirectFunctionCall1(rtrim1, entry->key);
        GISTENTRY   trim;

        gistentryinit(trim, d,
                      entry->rel, entry->page,
                      entry->offset, true);
        retval = gbt_var_compress(&trim, &tinfo);
    }
    else
        retval = entry;

    PG_RETURN_POINTER(retval);
}
```

从上面的代码可以看出，到是叶子节点时，将对键调用 `rtrim1()` 函数删除键最右边的空白字符，因此在 Index Only 扫描的时候我们获取不到的数据后面的空白填充。我们可以通过避免删除键最右边的空白字符来解决这个问题。在尝试移除 `gbt_bpchar_compress()` 中针对键的操作之后，我发现当使用等值查询时查不到结果。这是由于 `btree_gist` 在对 `bpchar` 类型的操作使用的是 `text` 类型的操作，例如等值查询将使用 `texteq()` 函数，这是在 `tinfo` 变量中定义的。

```c
static bool
gbt_texteq(const void *a, const void *b, Oid collation, FmgrInfo *flinfo)
{
    return DatumGetBool(DirectFunctionCall2Coll(texteq,
                                                collation,
                                                PointerGetDatum(a),
                                                PointerGetDatum(b)));
}

static gbtree_vinfo tinfo =
{
    gbt_t_text,
    0,
    false,
    gbt_textgt,
    gbt_textge,
    gbt_texteq,
    gbt_textle,
    gbt_textlt,
    gbt_textcmp,
    NULL
};
```

而针对 `bpchar` (i.e. `char(n)`) 类型，实际上应该使用 `bpchareq()` 函数，该函数在比较是会将参数最右侧的空白字符删除，因此可以正常执行等值比较。`bpchareq()` 函数里面的 `bcTruelen()` 是关键，从下面可以看到，它在计算长度时忽略了末尾的空白字符。

```c
/* "True" length (not counting trailing blanks) of a BpChar */
static inline int
bcTruelen(BpChar *arg)
{
    return bpchartruelen(VARDATA_ANY(arg), VARSIZE_ANY_EXHDR(arg));
}

int
bpchartruelen(char *s, int len)
{
    int         i;

    /*
     * Note that we rely on the assumption that ' ' is a singleton unit on
     * every supported multibyte server encoding.
     */
    for (i = len - 1; i >= 0; i--)
    {
        if (s[i] != ' ')
            break;
    }
    return i + 1;
}
```

## 解决

我给出的 patch 只能说可以解决这个问题，但是不够优雅，最后 Tom Lane 给出了解决该问题的 patch，如下所示：

```diff
diff --git a/contrib/btree_gist/btree_text.c b/contrib/btree_gist/btree_text.c
index 8019d11281..be0eac7975 100644
--- a/contrib/btree_gist/btree_text.c
+++ b/contrib/btree_gist/btree_text.c
@@ -90,6 +90,76 @@ static gbtree_vinfo tinfo =
 	NULL
 };

+/* bpchar needs its own comparison rules */
+
+static bool
+gbt_bpchargt(const void *a, const void *b, Oid collation, FmgrInfo *flinfo)
+{
+	return DatumGetBool(DirectFunctionCall2Coll(bpchargt,
+												collation,
+												PointerGetDatum(a),
+												PointerGetDatum(b)));
+}
+
+static bool
+gbt_bpcharge(const void *a, const void *b, Oid collation, FmgrInfo *flinfo)
+{
+	return DatumGetBool(DirectFunctionCall2Coll(bpcharge,
+												collation,
+												PointerGetDatum(a),
+												PointerGetDatum(b)));
+}
+
+static bool
+gbt_bpchareq(const void *a, const void *b, Oid collation, FmgrInfo *flinfo)
+{
+	return DatumGetBool(DirectFunctionCall2Coll(bpchareq,
+												collation,
+												PointerGetDatum(a),
+												PointerGetDatum(b)));
+}
+
+static bool
+gbt_bpcharle(const void *a, const void *b, Oid collation, FmgrInfo *flinfo)
+{
+	return DatumGetBool(DirectFunctionCall2Coll(bpcharle,
+												collation,
+												PointerGetDatum(a),
+												PointerGetDatum(b)));
+}
+
+static bool
+gbt_bpcharlt(const void *a, const void *b, Oid collation, FmgrInfo *flinfo)
+{
+	return DatumGetBool(DirectFunctionCall2Coll(bpcharlt,
+												collation,
+												PointerGetDatum(a),
+												PointerGetDatum(b)));
+}
+
+static int32
+gbt_bpcharcmp(const void *a, const void *b, Oid collation, FmgrInfo *flinfo)
+{
+	return DatumGetInt32(DirectFunctionCall2Coll(bpcharcmp,
+												 collation,
+												 PointerGetDatum(a),
+												 PointerGetDatum(b)));
+}
+
+static gbtree_vinfo bptinfo =
+{
+	gbt_t_bpchar,
+	0,
+	false,
+	gbt_bpchargt,
+	gbt_bpcharge,
+	gbt_bpchareq,
+	gbt_bpcharle,
+	gbt_bpcharlt,
+	gbt_bpcharcmp,
+	NULL
+};
+

 /**************************************************
  * Text ops
@@ -112,29 +182,8 @@ gbt_text_compress(PG_FUNCTION_ARGS)
 Datum
 gbt_bpchar_compress(PG_FUNCTION_ARGS)
 {
-	GISTENTRY  *entry = (GISTENTRY *) PG_GETARG_POINTER(0);
-	GISTENTRY  *retval;
-
-	if (tinfo.eml == 0)
-	{
-		tinfo.eml = pg_database_encoding_max_length();
-	}
-
-	if (entry->leafkey)
-	{
-
-		Datum		d = DirectFunctionCall1(rtrim1, entry->key);
-		GISTENTRY	trim;
-
-		gistentryinit(trim, d,
-					  entry->rel, entry->page,
-					  entry->offset, true);
-		retval = gbt_var_compress(&trim, &tinfo);
-	}
-	else
-		retval = entry;
-
-	PG_RETURN_POINTER(retval);
+	/* This should never have been distinct from gbt_text_compress */
+	return gbt_text_compress(fcinfo);
 }


@@ -179,18 +228,17 @@ gbt_bpchar_consistent(PG_FUNCTION_ARGS)
 	bool		retval;
 	GBT_VARKEY *key = (GBT_VARKEY *) DatumGetPointer(entry->key);
 	GBT_VARKEY_R r = gbt_var_key_readable(key);
-	void	   *trim = (void *) DatumGetPointer(DirectFunctionCall1(rtrim1, PointerGetDatum(query)));

 	/* All cases served by this function are exact */
 	*recheck = false;

-	if (tinfo.eml == 0)
+	if (bptinfo.eml == 0)
 	{
-		tinfo.eml = pg_database_encoding_max_length();
+		bptinfo.eml = pg_database_encoding_max_length();
 	}

-	retval = gbt_var_consistent(&r, trim, strategy, PG_GET_COLLATION(),
-								GIST_LEAF(entry), &tinfo, fcinfo->flinfo);
+	retval = gbt_var_consistent(&r, query, strategy, PG_GET_COLLATION(),
+								GIST_LEAF(entry), &bptinfo, fcinfo->flinfo);
 	PG_RETURN_BOOL(retval);
 }

diff --git a/contrib/btree_gist/expected/char.out b/contrib/btree_gist/expected/char.out
index d715c045cc..45cf9f38d6 100644
--- a/contrib/btree_gist/expected/char.out
+++ b/contrib/btree_gist/expected/char.out
@@ -75,8 +75,8 @@ SELECT * FROM chartmp WHERE a BETWEEN '31a' AND '31c';
 (2 rows)

 SELECT * FROM chartmp WHERE a BETWEEN '31a' AND '31c';
-  a
-------
- 31b0
+                a
+----------------------------------
+ 31b0
 (1 row)

diff --git a/contrib/btree_gist/expected/char_1.out b/contrib/btree_gist/expected/char_1.out
index 867318002b..7b7824b717 100644
--- a/contrib/btree_gist/expected/char_1.out
+++ b/contrib/btree_gist/expected/char_1.out
@@ -75,8 +75,8 @@ SELECT * FROM chartmp WHERE a BETWEEN '31a' AND '31c';
 (2 rows)

 SELECT * FROM chartmp WHERE a BETWEEN '31a' AND '31c';
-  a
-------
- 31b0
+                a
+----------------------------------
+ 31b0
 (1 row)

```

**备注：**上面的 diff 文件中末尾的空白被移除了，因此不能直接用，您需要在[这里](https://www.postgresql.org/message-id/attachment/129615/fix-btree_gist-bpchar-trimming.patch)获取 patch 文件。

~目前，该 patch 还未合并到主分支，尚待验证。~ 2022 年 01 月 08 日已被合并到主分支，并 back-patch 回所有支持的分支。

## 参考

[1] https://www.postgresql.org/message-id/flat/696c995b-b37f-5526-f45d-04abe713179f%40gmail.com

<div class="just-for-fun">
笑林广记 - 嘲武举诗

头戴银雀顶，脚踏粉底皂。
也去参主考，也来谒孔庙。
颜渊喟然叹，夫子莞尔笑。
子路愠见曰：“这般呆狗屎，我若行三军，都去喂马料。”
</div>
