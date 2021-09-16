---
title: "PostgreSQL 系统属性添加"
date: 2019-08-30 22:51:05 +0800
category: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

PostgreSQL 在插入数据的时候除了维护用户的属性列外，还有几个隐藏的系统属性列，如 `ctid`、`xmin` 和 `xmax` 等。如下图所示：

{% asset_img sysattr.png PostgreSQL 系统属性 %}

从上图中我们可以看到，系统属性列其编号（即 `attnum` ）为负数，而用户自定义的属性列其编号则为正数（由 1 开始）。本文将介绍如何在 PostgreSQL 中添加自定义系统属性。

<!-- more -->

## 属性列

PostgreSQL 为每个属性列都在系统表 `pg_attribute` 中记录了一个元组，[见官网文档](https://www.postgresql.org/docs/12/catalog-pg-attribute.html)。这里我们需要对几个常见的列有所认识，这也是本文后续要使用到的。

<style>
table th:nth-of-type(1) {
    width: 15%;
}
table th:nth-of-type(2) {
    width: 80%;
}
</style>

| 属性列 | 说明 |
|--------|------|
| __attname__    | 属性列的名称。
| __atttypid__   | 属性列的数据类型的 OID，引用 `pg_type` 表的 `oid` 字段（外键约束）。
| __attlen__     | 此属性列的数据类型长度，`pg_type` 表的 `typlen` 字段的副本。
| __attnum__     | 属性列编号数。用户定义的普通属性列的编号从 1 开始。系统属性列列（例如 `ctid`）则为负数。
| __attcacheoff__ | 存储中始终为 -1，但是当加载到内存中的行描述符时，可能会更新该行描述符以缓存行中属性的偏移量。
| __atttypmod__   | 记录在创建表时提供的特定于类型的数据（例如，`varchar` 类型的最大长度）。它被传递给特定类型的输入函数和长度强制函数。对于不需要 `atttypmod` 的类型，该值通常为 -1。
| __attbyval__    | 数据类型是否按值传递，`pg_type` 表的 `typbyval` 字段的副本。
| __attstorage__  | 通常是此列类型的 `pg_type` 表的 `typstorage` 字段的副本。对于 TOAST-able 数据类型，可以在创建列后更改此值以控制存储策略。
| __attalign__    | 数据类型的对其方式，`pg_type` 表的 `typalign` 的副本。<br/>`c` 表示按照 `char` 类型对齐（即不需要对齐）；`s` 按 `short` 类型对齐（在大多数机器上是 2 字节对齐）；`i` 表示按照 `int` 类型对齐（通常是 4 字节对齐）；`d` 表示按照 `double` 类型对齐（通常是 8 字节对齐，但并不全是）。
| __attnotnull__  | 该属性列是否具有非空约束。
| __attislocal__  | 该属性列在表中是本地定义。请注意，属性列可以是本地定义并同时继承。

其实整个属性列都是通过 `FormData_pg_attribute` 结果来记录的，它定义在 `src/include/catalog/pg_attribute.h` 头文件中。

## 系统属性

PostgreSQL 的系统属性是在 `src/backend/catalog/heap.c` 源文件中定义的，如下所示：

``` C
static const FormData_pg_attribute a1 = {
    .attname = {"ctid"},
    .atttypid = TIDOID,
    .attlen = sizeof(ItemPointerData),
    .attnum = SelfItemPointerAttributeNumber,
    .attcacheoff = -1,
    .atttypmod = -1,
    .attbyval = false,
    .attstorage = 'p',
    .attalign = 's',
    .attnotnull = true,
    .attislocal = true,
};

static const FormData_pg_attribute a2 = {
    .attname = {"xmin"},
    .atttypid = XIDOID,
    .attlen = sizeof(TransactionId),
    .attnum = MinTransactionIdAttributeNumber,
    .attcacheoff = -1,
    .atttypmod = -1,
    .attbyval = true,
    .attstorage = 'p',
    .attalign = 'i',
    .attnotnull = true,
    .attislocal = true,
};

...

static const FormData_pg_attribute a6 = {
    .attname = {"tableoid"},
    .atttypid = OIDOID,
    .attlen = sizeof(Oid),
    .attnum = TableOidAttributeNumber,
    .attcacheoff = -1,
    .atttypmod = -1,
    .attbyval = true,
    .attstorage = 'p',
    .attalign = 'i',
    .attnotnull = true,
    .attislocal = true,
};

static const FormData_pg_attribute *SysAtt[] = {&a1, &a2, &a3, &a4, &a5, &a6};
```

从上面可以看到，属性列的编号是通过宏来定义的，例如 `TableOidAttributenumber`，这些宏的定义在 `src/include/access/sysattr.h` 头文件中定义，如下所示：

``` C
/*
 * Attribute numbers for the system-defined attributes
 */
#define SelfItemPointerAttributeNumber                  (-1)
#define MinTransactionIdAttributeNumber                 (-2)
#define MinCommandIdAttributeNumber                     (-3)
#define MaxTransactionIdAttributeNumber                 (-4)
#define MaxCommandIdAttributeNumber                     (-5)
#define TableOidAttributeNumber                         (-6)
#define FirstLowInvalidHeapAttributeNumber              (-7)
```

`atttypid` 则是在 `src/include/catalog/pg_type.dat` 文件中声明，并在编译时由 perl 转换为 `pg_type_d.h` 文件中的宏定义。

最终这些系统属性列将被保存在 `SysAttr` 全局数组中。用户在建立表时，PostgreSQL 通过 `AddNewAttributeTuples` 函数向 `pg_attribute` 插入属性列信息，随后在加入系统属性信息，如下所示：

``` C
for (i = 0; i < natts; i++)
{
    attr = TupleDescAttr(tupdesc, i);
    /* Fill in the correct relation OID */
    attr->attrelid = new_rel_oid;
    /* Make sure this is OK, too */
    attr->attstattarget = -1;

    InsertPgAttributeTuple(rel, attr, indstate);

    /* Add dependency info */
    myself.classId = RelationRelationId;
    myself.objectId = new_rel_oid;
    myself.objectSubId = i + 1;
    referenced.classId = TypeRelationId;
    referenced.objectId = attr->atttypid;
    referenced.objectSubId = 0;
    recordDependencyOn(&myself, &referenced, DEPENDENCY_NORMAL);

    /* The default collation is pinned, so don't bother recording it */
    if (OidIsValid(attr->attcollation) &&
        attr->attcollation != DEFAULT_COLLATION_OID)
    {
        referenced.classId = CollationRelationId;
        referenced.objectId = attr->attcollation;
        referenced.objectSubId = 0;
        recordDependencyOn(&myself, &referenced, DEPENDENCY_NORMAL);
    }
}

/*
 * Next we add the system attributes.  Skip OID if rel has no OIDs. Skip
 * all for a view or type relation.  We don't bother with making datatype
 * dependencies here, since presumably all these types are pinned.
 */
if (relkind != RELKIND_VIEW && relkind != RELKIND_COMPOSITE_TYPE)
{
    for (i = 0; i < (int) lengthof(SysAtt); i++)
    {
        FormData_pg_attribute attStruct;

        memcpy(&attStruct, SysAtt[i], sizeof(FormData_pg_attribute));

        /* Fill in the correct relation OID in the copied tuple */
        attStruct.attrelid = new_rel_oid;

        InsertPgAttributeTuple(rel, &attStruct, indstate);
    }
}
```

## 创建系统属性列

现在，我们对系统属性列的工作方式有所了解了，接下来就可以创建自定义系统属性列。首先我们声明一个属性列的编号，如下所示：

``` C
#define InfomaskAttributeNumber                         (-7)
#define FirstLowInvalidHeapAttributeNumber              (-8)
```

__注意；__ 不要忘记更新 `FirstLowInvalidHeapAttributeNumber` 的值。

接着，我们需要声明属性列，并将其添加到 `SysAtt` 数组中，如下所示：

``` C
static const FormData_pg_attribute a7 = {
        .attname = {"infomask"},
        .atttypid = INT2OID,
        .attlen = sizeof(uint16),
        .attnum = InfomaskAttributeNumber,
        .attcacheoff = -1,
        .atttypmod = -1,
        .attbyval = true,
        .attstorage = 'p',
        .attalign = 'i',
        .attnotnull = true,
        .attislocal = true,
};

static const FormData_pg_attribute *SysAtt[] = {&a1, &a2, &a3, &a4, &a5, &a6, &a7};
```

此时，我们就基本完成了属性列的添加。当然，为了能够查询，我还需要在两个地方做修改，它们均位于 `src/backend/access/common/heaptuple.c` 文件中。首先在函数 `heap_attisnull` 中增加我们的属性列：

``` C
bool
heap_attisnull(HeapTuple tup, int attnum, TupleDesc tupleDesc)
{
        /*
         * We allow a NULL tupledesc for relations not expected to have missing
         * values, such as catalog relations and indexes.
         */
        Assert(!tupleDesc || attnum <= tupleDesc->natts);
        if (attnum > (int) HeapTupleHeaderGetNatts(tup->t_data))
        {
                if (tupleDesc && TupleDescAttr(tupleDesc, attnum - 1)->atthasmissing)
                        return false;
                else
                        return true;
        }

        if (attnum > 0)
        {
                if (HeapTupleNoNulls(tup))
                        return false;
                return att_isnull(attnum - 1, tup->t_data->t_bits);
        }

        switch (attnum)
        {
                case TableOidAttributeNumber:
                case SelfItemPointerAttributeNumber:
                case MinTransactionIdAttributeNumber:
                case MinCommandIdAttributeNumber:
                case MaxTransactionIdAttributeNumber:
                case MaxCommandIdAttributeNumber:
                case InfomaskAttributeNumber:
                        /* these are never null */
                        break;

                default:
                        elog(ERROR, "invalid attnum: %d", attnum);
        }

        return false;
}
```

接着，在 `heap_getsysattr` 函数中添加如何获取 `infomask` 的值，如下所示：

``` C
Datum
heap_getsysattr(HeapTuple tup, int attnum, TupleDesc tupleDesc, bool *isnull)
{
        Datum           result;

        Assert(tup);

        /* Currently, no sys attribute ever reads as NULL. */
        *isnull = false;

        switch (attnum)
        {
                case SelfItemPointerAttributeNumber:
                        /* pass-by-reference datatype */
                        result = PointerGetDatum(&(tup->t_self));
                        break;
                case MinTransactionIdAttributeNumber:
                        result = TransactionIdGetDatum(HeapTupleHeaderGetRawXmin(tup->t_data));
                        break;
                case MaxTransactionIdAttributeNumber:
                        result = TransactionIdGetDatum(HeapTupleHeaderGetRawXmax(tup->t_data));
                        break;
                case MinCommandIdAttributeNumber:
                case MaxCommandIdAttributeNumber:

                        /*
                         * cmin and cmax are now both aliases for the same field, which
                         * can in fact also be a combo command id.  XXX perhaps we should
                         * return the "real" cmin or cmax if possible, that is if we are
                         * inside the originating transaction?
                         */
                        result = CommandIdGetDatum(HeapTupleHeaderGetRawCommandId(tup->t_data));
                        break;
                case TableOidAttributeNumber:
                        result = ObjectIdGetDatum(tup->t_tableOid);
                        break;
                case InfomaskAttributeNumber:
                        result = UInt16GetDatum(tup->t_data->t_infomask);
                        break;
                default:
                        elog(ERROR, "invalid attnum: %d", attnum);
                        result = 0;                     /* keep compiler quiet */
                        break;
        }
        return result;
}
```

最后，编译、初始化并启动数据库，效果如下图所示：

{% asset_img result.png 效果图 %}


## 参考

[1] https://www.postgresql.org/docs/12/catalog-pg-attribute.html
[2] https://www.postgresql.org/docs/12/catalog-pg-type.html
