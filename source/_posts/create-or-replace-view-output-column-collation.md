---
title: "PostgreSQL 视图替换时更新输出列的 collation 问题"
date: 2022-02-16 22:09:03 +0800
categories: 数据库
tags:
  - PostgreSQL
---

最近在邮件列表中发现 [`CREATE OR REPLACE VIEW` 存在一个 bug，无法更新输出列的 collation](https://www.postgresql.org/message-id/17404-8a4a270ef30a6709@postgresql.org)。如下所示：

```sql
postgres=# CREATE TABLE tbl (info text);
CREATE TABLE
postgres=# CREATE VIEW my_tbl_view AS SELECT info FROM tbl;
CREATE VIEW

postgres=# \d+ my_tbl_view
                        View "public.my_tbl_view"
 Column | Type | Collation | Nullable | Default | Storage  | Description
--------+------+-----------+----------+---------+----------+-------------
 info   | text |           |          |         | extended |
View definition:
 SELECT tbl.info
   FROM tbl;

postgres=# CREATE OR REPLACE VIEW my_tbl_view AS SELECT info COLLATE "en_US.utf8" FROM tbl;
CREATE VIEW
postgres=# \d+ my_tbl_view
                        View "public.my_tbl_view"
 Column | Type | Collation | Nullable | Default | Storage  | Description
--------+------+-----------+----------+---------+----------+-------------
 info   | text |           |          |         | extended |
View definition:
 SELECT tbl.info COLLATE "en_US.utf8" AS info
   FROM tbl;
```

可以看到在 `Collation` 列中没有发生改变，而且也没任何提示，只是默默的丢弃了 `COLLATE "en_US.utf8"`，但是在视图的定义中又更新了 `Collation`，这多少让人有点疑惑。

<!--more-->

接着尝试在新建视图的时候指定 `Collation` 发现它是可以被记录的。

```sql
postgres=# CREATE OR REPLACE VIEW my_tbl_view1 AS SELECT info COLLATE "en_US.utf8" FROM tbl;
CREATE VIEW
postgres=# \d+ my_tbl_view1
                        View "public.my_tbl_view1"
 Column | Type | Collation  | Nullable | Default | Storage  | Description
--------+------+------------+----------+---------+----------+-------------
 info   | text | en_US.utf8 |          |         | extended |
View definition:
 SELECT tbl.info COLLATE "en_US.utf8" AS info
   FROM tbl;

postgres=# CREATE OR REPLACE VIEW my_tbl_view1 AS SELECT info COLLATE "C" FROM tbl;
CREATE VIEW
postgres=# \d+ my_tbl_view1
                        View "public.my_tbl_view1"
 Column | Type | Collation  | Nullable | Default | Storage  | Description
--------+------+------------+----------+---------+----------+-------------
 info   | text | en_US.utf8 |          |         | extended |
View definition:
 SELECT tbl.info COLLATE "C" AS info
   FROM tbl;
```

## 分析

`CREATE OR REPLACE VIEW` 属于 DDL 语句，因此在 PostgreSQL 内部是通过 `ProcessUtility()` 函数来处理的，其处理流程如下图所示。

{% asset_img flow-for-create-view.png Flow of CREATE VIEW in PostgreSQL %}

其中关于视图信息的内容主要集中在 `DefineVirtualRelation()` 函数中，其流程如下所示。

{% asset_img flow-of-DefineVirtualRelation.png Flow of DefineVirtualRelation %}

当我们执行的是 `CREATE OR REPLACE VIEW` 命令并且视图存在时将执行上图中左边部分流程：

1. 检测当前视图是否正在被使用；
2. 构建视图的属性列；
3. 检测视图新的属性列与旧属性列，违反相应的规则将拒绝更改视图；
4. 处理新增的属性列，如果有新增的属性列；
5. 以规则的形式存储视图查询语句。

通过查看 `checkViewTupleDesc()` 函数，我们发现它在比较新旧属性时忽略了 `collation` 相关的信息。

```c
/*
 * Verify that tupledesc associated with proposed new view definition
 * matches tupledesc of old view.  This is basically a cut-down version
 * of equalTupleDescs(), with code added to generate specific complaints.
 * Also, we allow the new tupledesc to have more columns than the old.
 */
static void
checkViewTupleDesc(TupleDesc newdesc, TupleDesc olddesc)
{
    int         i;

    if (newdesc->natts < olddesc->natts)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_TABLE_DEFINITION),
                 errmsg("cannot drop columns from view")));

    for (i = 0; i < olddesc->natts; i++)
    {
        Form_pg_attribute newattr = TupleDescAttr(newdesc, i);
        Form_pg_attribute oldattr = TupleDescAttr(olddesc, i);

        /* XXX msg not right, but we don't support DROP COL on view anyway */
        if (newattr->attisdropped != oldattr->attisdropped)
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_TABLE_DEFINITION),
                     errmsg("cannot drop columns from view")));

        if (strcmp(NameStr(newattr->attname), NameStr(oldattr->attname)) != 0)
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_TABLE_DEFINITION),
                     errmsg("cannot change name of view column \"%s\" to \"%s\"",
                            NameStr(oldattr->attname),
                            NameStr(newattr->attname)),
                     errhint("Use ALTER VIEW ... RENAME COLUMN ... to change name of view column instead.")));
        /* XXX would it be safe to allow atttypmod to change?  Not sure */
        if (newattr->atttypid != oldattr->atttypid ||
            newattr->atttypmod != oldattr->atttypmod)
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_TABLE_DEFINITION),
                     errmsg("cannot change data type of view column \"%s\" from %s to %s",
                            NameStr(oldattr->attname),
                            format_type_with_typemod(oldattr->atttypid,
                                                     oldattr->atttypmod),
                            format_type_with_typemod(newattr->atttypid,
                                                     newattr->atttypmod))));
        /* We can ignore the remaining attributes of an attribute... */
    }

    /*
     * We ignore the constraint fields.  The new view desc can't have any
     * constraints, and the only ones that could be on the old view are
     * defaults, which we are happy to leave in place.
     */
}
```

在随后的属性列处理中，将跳过已有的属性列，只针对新增的属性列进行处理，从而导致 `collation` 信息没有机会更新，如下所示。

```c
        /*
         * If new attributes have been added, we must add pg_attribute entries
         * for them.  It is convenient (although overkill) to use the ALTER
         * TABLE ADD COLUMN infrastructure for this.
         *
         * Note that we must do this before updating the query for the view,
         * since the rules system requires that the correct view columns be in
         * place when defining the new rules.
         *
         * Also note that ALTER TABLE doesn't run parse transformation on
         * AT_AddColumnToView commands.  The ColumnDef we supply must be ready
         * to execute as-is.
         */
        if (list_length(attrList) > rel->rd_att->natts)
        {
            ListCell   *c;
            int         skip = rel->rd_att->natts;

            foreach(c, attrList)
            {
                if (skip > 0)
                {
                    skip--;
                    continue;
                }
                atcmd = makeNode(AlterTableCmd);
                atcmd->subtype = AT_AddColumnToView;
                atcmd->def = (Node *) lfirst(c);
                atcmds = lappend(atcmds, atcmd);
            }

            /* EventTriggerAlterTableStart called by ProcessUtilitySlow */
            AlterTableInternal(viewOid, atcmds, true);

            /* Make the new view columns visible */
            CommandCounterIncrement();
        }
```

## 解决方案

Tom Lane 认为这是一个 bug，当在修改视图属性列的 `collation` 时应该报错，这和修改属性的数据类型一样不确定是否安全，Tom Lane 的解决方案是在判断新旧属性的 `collation` 不一致时报错并终止，如下所示。

```diff
index e183ab097c44cda951696e1b2f2250118344c72c..459e9821d08142fb66f901e554c6a894b528d3bf 100644 (file)
--- a/src/backend/commands/view.c
+++ b/src/backend/commands/view.c
@@ -282,7 +282,12 @@ checkViewTupleDesc(TupleDesc newdesc, TupleDesc olddesc)
                            NameStr(oldattr->attname),
                            NameStr(newattr->attname)),
                     errhint("Use ALTER VIEW ... RENAME COLUMN ... to change name of view column instead.")));
-       /* XXX would it be safe to allow atttypmod to change?  Not sure */
+
+       /*
+        * We cannot allow type, typmod, or collation to change, since these
+        * properties may be embedded in Vars of other views/rules referencing
+        * this one.  Other column attributes can be ignored.
+        */
        if (newattr->atttypid != oldattr->atttypid ||
            newattr->atttypmod != oldattr->atttypmod)
            ereport(ERROR,
@@ -293,7 +298,18 @@ checkViewTupleDesc(TupleDesc newdesc, TupleDesc olddesc)
                                                     oldattr->atttypmod),
                            format_type_with_typemod(newattr->atttypid,
                                                     newattr->atttypmod))));
-       /* We can ignore the remaining attributes of an attribute... */
+
+       /*
+        * At this point, attcollations should be both valid or both invalid,
+        * so applying get_collation_name unconditionally should be fine.
+        */
+       if (newattr->attcollation != oldattr->attcollation)
+           ereport(ERROR,
+                   (errcode(ERRCODE_INVALID_TABLE_DEFINITION),
+                    errmsg("cannot change collation of view column \"%s\" from \"%s\" to \"%s\"",
+                           NameStr(oldattr->attname),
+                           get_collation_name(oldattr->attcollation),
+                           get_collation_name(newattr->attcollation))));
    }
```

## 参考

[1] https://www.postgresql.org/message-id/17404-8a4a270ef30a6709@postgresql.org

<div class="just-for-fun">
笑林广记 - 咬飞边

贫子途遇监生，忽然抱住咬耳一口，生惊问其故，答曰：“我穷苦极矣。见了大锭银子，如何不咬些飞边用用。”
</div>
