---
title: "PostgreSQL 无法更改外键引用的聚集列的数据类型"
date: 2022-03-12 14:00:48 +0800
categories: 数据库
tags:
  - BUG
  - PG14
  - PostgreSQL
---

最近在邮件列表中看到一个关于聚集列的数据类型修改导致的异常问题 [BUG #17409][]。本文简要记录一下分析过程以及解决方案。目前该问题已经被修复，在 14.1 和 14.2 版本中应该可以重现。

	commit 641f3dffcdf1c7378cfb94c98b6642793181d6db
	Author: Tom Lane <tgl@sss.pgh.pa.us>
	Date:   Fri Mar 11 13:47:26 2022 -0500

	    Restore the previous semantics of get_constraint_index().

	    Commit 8b069ef5d changed this function to look at pg_constraint.conindid
	    rather than searching pg_depend.  That was a good performance improvement,
	    but it failed to preserve the exact semantics.  The old code would only
	    return an index that was "owned by" (internally dependent on) the
	    specified constraint, whereas the new code will also return indexes that
	    are just referenced by foreign key constraints.  This confuses ALTER
	    TABLE, which was implicitly expecting the previous semantics, into
	    failing with errors like
	        ERROR:  relation 146621 has multiple clustered indexes
	    or
	        ERROR:  "pk_attbl" is not an index for table "atref"

	    We can fix this without reverting the performance improvement by adding
	    a contype check in get_constraint_index().  Another way could be to
	    make ALTER TABLE check it, but I'm worried that extension code could
	    also have subtle dependencies on the old semantics.

	    Tom Lane and Japin Li, per bug #17409 from Holly Roberts.
	    Back-patch to v14 where the error crept in.

	    Discussion: https://postgr.es/m/17409-52871dda8b5741cb@postgresql.org

<!--more-->

## 现象

我们可以通过如下的示例来重现这个问题（源码为 PostgreSQL e94bb1473）。

```sql
$ psql postgres
psql (15devel)
Type "help" for help.

postgres=# CREATE TABLE attbl (p1 int constraint pk_attbl primary key);
CREATE TABLE
postgres=# CREATE TABLE atref (c1 int references attbl(p1));
CREATE TABLE
postgres=# CLUSTER attbl USING pk_attbl;
CLUSTER
postgres=# ALTER TABLE attbl ALTER COLUMN p1 SET DATA TYPE bigint;
ERROR:  relation 16384 has multiple clustered indexes
postgres=#
```

然而实际上表 `attbl` 并不存在多个聚集索引，如下所示。

```
postgres=# SELECT
postgres-#     table_cls.relnamespace::regnamespace::text AS schema,
postgres-#     table_cls.relname AS table,
postgres-#     index_cls.relname AS index,
postgres-#     indisclustered
postgres-# FROM
postgres-#     pg_index pi INNER JOIN pg_class index_cls ON (pi.indexrelid = index_cls.oid)
postgres-#     INNER JOIN pg_class table_cls ON (pi.indrelid = table_cls.oid)
postgres-# WHERE
postgres-#     (table_cls.relnamespace::regnamespace::text, table_cls.relname) = ('public', 'attbl');
 schema | table |  index   | indisclustered
--------+-------+----------+----------------
 public | attbl | pk_attbl | t
(1 row)
```

因此可以断定这是一个 BUG。

## 分析

从邮件来看，这个问题应该是在 13 之后的版本中引入的。通过 `git bisect` 查找，我发现是在 [8b069ef5dc][] 提交中引入的这个问题。

	commit 8b069ef5dca97cd737a5fd64c420df3cd61ec1c9
	Author: Peter Eisentraut <peter@eisentraut.org>
	Date:   Wed Dec 9 15:12:05 2020 +0100

    	Change get_constraint_index() to use pg_constraint.conindid

    	It was still using a scan of pg_depend instead of using the conindid
    	column that has been added since.

    	Since it is now just a catalog lookup wrapper and not related to
    	pg_depend, move from pg_depend.c to lsyscache.c.

    	Reviewed-by: Matthias van de Meent <boekewurm+postgres@gmail.com>
    	Reviewed-by: Tom Lane <tgl@sss.pgh.pa.us>
    	Reviewed-by: Michael Paquier <michael@paquier.xyz>
    	Discussion: https://www.postgresql.org/message-id/flat/4688d55c-9a2e-9a5a-d166-5f24fe0bf8db%40enterprisedb.com


该提交主要是修改了 `get_constraint_index()` 函数，在这之前，它是通过扫描 `pg_depend` 表来获取约束底层的索引信息（如果存在，返回索引的 oid）；在这之后，它是从 `syscache` 中获取（系统表 `pg_constraint`）。

根据错误信息，我发现其是在 `RememberClusterOnForRebuilding()` 函数中报错，如下所示。

```c
/*
 * Subroutine for ATExecAlterColumnType: remember any clustered index.
 */
static void
RememberClusterOnForRebuilding(Oid indoid, AlteredTableInfo *tab)
{
    if (!get_index_isclustered(indoid))
        return;

    if (tab->clusterOnIndex)
        elog(ERROR, "relation %u has multiple clustered indexes", tab->relid);

    tab->clusterOnIndex = get_rel_name(indoid);
}
```

在该函数中，它使用 `tab->clusterOnIndex` 来判断是否已经存在聚集索引。这个问题就出在这个聚集索引出现了两次，通过调试发现，这两次的值都是一致的，这里出现两次调用是由于 `ALTER TABLE attbl ALTER COLUMN p1 SET DATA TYPE bigint;` 这个语句在内部还会生成一条 `ALTER TABLE public.tbref ADD CONSTRAINT fk_tbref FOREIGN KEY (c1) REFERENCES attbl(p1);` 语句（尚未分析这样做的原因）。由于在 `RememberClusterOnForRebuilding()` 函数中没有判断 `tab->clusterOnIndex` 是否为同一个对象，因此，当同一个对象出现两次时，也会报如上错误，经 Michael Paquier 指出，`RememberReplicaIdentityForRebuilding()` 存在相似的问题。

## 解决方案

经过上面的分析，我尝试在报错之前判断其是否为同一个对象，v1 版本就此诞生，如下所示。

```diff
diff --git a/src/backend/commands/tablecmds.c b/src/backend/commands/tablecmds.c
index 3e83f375b5..4c0689d62e 100644
--- a/src/backend/commands/tablecmds.c
+++ b/src/backend/commands/tablecmds.c
@@ -12853,13 +12853,22 @@ ATExecAlterColumnType(AlteredTableInfo *tab, Relation rel,
 static void
 RememberReplicaIdentityForRebuilding(Oid indoid, AlteredTableInfo *tab)
 {
+	char	*indname;
+
 	if (!get_index_isreplident(indoid))
 		return;

-	if (tab->replicaIdentityIndex)
+	indname = get_rel_name(indoid);
+	if (tab->replicaIdentityIndex == NULL)
+	{
+		tab->replicaIdentityIndex = get_rel_name(indoid);
+		return;
+	}
+
+	if (strcmp(tab->replicaIdentityIndex, indname) != 0)
 		elog(ERROR, "relation %u has multiple indexes marked as replica identity", tab->relid);

-	tab->replicaIdentityIndex = get_rel_name(indoid);
+	pfree(indname);
 }

 /*
@@ -12868,13 +12877,22 @@ RememberReplicaIdentityForRebuilding(Oid indoid, AlteredTableInfo *tab)
 static void
 RememberClusterOnForRebuilding(Oid indoid, AlteredTableInfo *tab)
 {
+	char	*indname;
+
 	if (!get_index_isclustered(indoid))
 		return;

-	if (tab->clusterOnIndex)
+	indname = get_rel_name(indoid);
+	if (tab->clusterOnIndex == NULL)
+	{
+		tab->clusterOnIndex = indname;
+		return;
+	}
+
+	if (strcmp(tab->clusterOnIndex, indname) != 0)
 		elog(ERROR, "relation %u has multiple clustered indexes", tab->relid);

-	tab->clusterOnIndex = get_rel_name(indoid);
+	pfree(indname);
 }
```

但是，这种方式过于繁琐，因此，Tom Lane 尝试 `get_rel_name()` 延迟到之后来进行调用，从而避免反复的调用 `get_rel_name()` 函数，为此诞生了 v2 版本。

```diff
diff --git a/src/backend/commands/tablecmds.c b/src/backend/commands/tablecmds.c
index dc5872f988..19c924b7df 100644
--- a/src/backend/commands/tablecmds.c
+++ b/src/backend/commands/tablecmds.c
@@ -189,8 +189,8 @@ typedef struct AlteredTableInfo
 	List	   *changedConstraintDefs;	/* string definitions of same */
 	List	   *changedIndexOids;	/* OIDs of indexes to rebuild */
 	List	   *changedIndexDefs;	/* string definitions of same */
-	char	   *replicaIdentityIndex;	/* index to reset as REPLICA IDENTITY */
-	char	   *clusterOnIndex; /* index to use for CLUSTER */
+	Oid			replicaIdentityIndex;	/* index to reset as REPLICA IDENTITY */
+	Oid			clusterOnIndex; /* index to use for CLUSTER */
 	List	   *changedStatisticsOids;	/* OIDs of statistics to rebuild */
 	List	   *changedStatisticsDefs;	/* string definitions of same */
 } AlteredTableInfo;
@@ -12856,10 +12856,12 @@ RememberReplicaIdentityForRebuilding(Oid indoid, AlteredTableInfo *tab)
 	if (!get_index_isreplident(indoid))
 		return;

-	if (tab->replicaIdentityIndex)
+	/* We must de-duplicate multiple requests */
+	if (OidIsValid(tab->replicaIdentityIndex) &&
+		tab->replicaIdentityIndex != indoid)
 		elog(ERROR, "relation %u has multiple indexes marked as replica identity", tab->relid);

-	tab->replicaIdentityIndex = get_rel_name(indoid);
+	tab->replicaIdentityIndex = indoid;
 }

 /*
@@ -12871,10 +12873,12 @@ RememberClusterOnForRebuilding(Oid indoid, AlteredTableInfo *tab)
 	if (!get_index_isclustered(indoid))
 		return;

-	if (tab->clusterOnIndex)
+	/* We must de-duplicate multiple requests */
+	if (OidIsValid(tab->clusterOnIndex) &&
+		tab->clusterOnIndex != indoid)
 		elog(ERROR, "relation %u has multiple clustered indexes", tab->relid);

-	tab->clusterOnIndex = get_rel_name(indoid);
+	tab->clusterOnIndex = indoid;
 }

 /*
@@ -13117,13 +13121,15 @@ ATPostAlterTypeCleanup(List **wqueue, AlteredTableInfo *tab, LOCKMODE lockmode)
 	/*
 	 * Queue up command to restore replica identity index marking
 	 */
-	if (tab->replicaIdentityIndex)
+	if (OidIsValid(tab->replicaIdentityIndex))
 	{
 		AlterTableCmd *cmd = makeNode(AlterTableCmd);
 		ReplicaIdentityStmt *subcmd = makeNode(ReplicaIdentityStmt);

 		subcmd->identity_type = REPLICA_IDENTITY_INDEX;
-		subcmd->name = tab->replicaIdentityIndex;
+		subcmd->name = get_rel_name(tab->replicaIdentityIndex);
+		Assert(subcmd->name);
+
 		cmd->subtype = AT_ReplicaIdentity;
 		cmd->def = (Node *) subcmd;

@@ -13135,12 +13141,13 @@ ATPostAlterTypeCleanup(List **wqueue, AlteredTableInfo *tab, LOCKMODE lockmode)
 	/*
 	 * Queue up command to restore marking of index used for cluster.
 	 */
-	if (tab->clusterOnIndex)
+	if (OidIsValid(tab->clusterOnIndex))
 	{
 		AlterTableCmd *cmd = makeNode(AlterTableCmd);

 		cmd->subtype = AT_ClusterOn;
-		cmd->name = tab->clusterOnIndex;
+		cmd->name = get_rel_name(tab->clusterOnIndex);
+		Assert(cmd->name);

 		/* do it after indexes and constraints */
 		tab->subcmds[AT_PASS_OLD_CONSTR] =
```

上述两个版本都能解决这个问题，但是大神的脚本并没有因此而停下，Tom Lane 又继续分析了 `get_constraint_index()` 函数，他发现这个函数在前后的语义已经发生了变化。表 `attbl` 有 `pk_attbl` 主键约束，同时也有 `fk_attbl` 外键约束。函数 `get_constraint_index()` 的新实现返回 `pk_attbl` 索引作为两个约束的关联索引，而旧代码只为 `pk_attbl` 约束返回它。v3 版本则是在 `get_constraint_index()` 加入了对 `contype` 的判断。

```diff
diff --git a/src/backend/utils/cache/lsyscache.c b/src/backend/utils/cache/lsyscache.c
index feef999863..1b7e11b93e 100644
--- a/src/backend/utils/cache/lsyscache.c
+++ b/src/backend/utils/cache/lsyscache.c
@@ -1126,8 +1126,13 @@ get_constraint_name(Oid conoid)
  *		Given the OID of a unique, primary-key, or exclusion constraint,
  *		return the OID of the underlying index.
  *
- * Return InvalidOid if the index couldn't be found; this suggests the
- * given OID is bogus, but we leave it to caller to decide what to do.
+ * Returns InvalidOid if the constraint could not be found or is of
+ * the wrong type.
+ *
+ * The intent of this function is to return the index "owned" by the
+ * specified constraint.  Therefore we must check contype, since some
+ * pg_constraint entries (e.g. for foreign-key constraints) store the
+ * OID of an index that is referenced but not owned by the constraint.
  */
 Oid
 get_constraint_index(Oid conoid)
@@ -1140,7 +1145,12 @@ get_constraint_index(Oid conoid)
 		Form_pg_constraint contup = (Form_pg_constraint) GETSTRUCT(tp);
 		Oid			result;

-		result = contup->conindid;
+		if (contup->contype == CONSTRAINT_UNIQUE ||
+			contup->contype == CONSTRAINT_PRIMARY ||
+			contup->contype == CONSTRAINT_EXCLUSION)
+			result = contup->conindid;
+		else
+			result = InvalidOid;
 		ReleaseSysCache(tp);
 		return result;
 	}
```

## 参考

[1] https://www.postgresql.org/message-id/17409-52871dda8b5741cb%40postgresql.org

<div class="just-for-fun">
笑林广记 - 自不识

有监生穿大衣，带圆帽，于着衣镜中自照，得意甚，指谓妻曰：“你看镜中是何人？”
妻曰：“臭乌龟，亏你做了监生，连自（字同）都不识。”
</div>

[BUG #17409]: https://www.postgresql.org/message-id/17409-52871dda8b5741cb%40postgresql.org
[8b069ef5dc]: https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=8b069ef5dca97cd737a5fd64c420df3cd61ec1c9
