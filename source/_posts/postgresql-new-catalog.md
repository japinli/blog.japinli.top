---
title: "PostgreSQL 添加系统表"
date: 2019-08-24 09:58:00 +0800
category: Database
tags:
  - PostgreSQL
  - Source
---

本文将介绍如何在 PostgreSQL 中创建一个新的系统表。PostgreSQL 将系统表都存放在 `src/include/catalog` 目录下，如下图所示：

{% asset_img catalogs.png PostgresQL 系统表目录 %}

从目录结构来看，我们大概可以猜测到 PostgreSQL 将系统表的定义和数据分别存放在两个不同的文件中，例如，系统表 `pg_class`，其表结构定义在 `pg_class.h` 文件中，而数据则在 `pg_class.dat` 文件中。此外每个表都在数据库内部都有一个唯一的 OID 来作为标识。PostgreSQL 提供了脚本来检查未使用的 OID 以及是否包含重复的 OID，它们分别为 `unused_oids` 和 `duplicate_oids`。所有的系统表都将由 `src/backend/catalog/Catalog.pm` 进行处理，该文件负责将系统表文件转换为 Perl 数据结构。

<!-- more -->
在了解了 PostgreSQL 关于系统表的基本概念之后，我们尝试添加一个自己的系统表 `pg_play`。

## 系统表头文件

正如我们上面看到的，我们需要在 `src/include/catalog` 目录下新建一个 `pg_play.h` 的头文件，其内容如下：

``` C
/*-------------------------------------------------------------------------
 * pg_play.h
 *    definition of the "play" system catalog (pg_play)
 *
 * src/include/catalog/pg_play.h
 *
 * NOTES
 *    The Catalog.pm module reads this file and derives schema
 *    information.
 *-------------------------------------------------------------------------
 */
#ifndef PG_PLAY_H
#define PG_PLAY_H

#include "catalog/genbki.h"
#include "catalog/pg_class_d.h"

/* ----------------
 *		pg_play definition.  cpp turns this into
 *		typedef struct FormData_pg_play
 * ----------------
 */
CATALOG(pg_play,2023,PlayRelationId)
{
	Oid         playid;
	NameData    playname;
} FormData_pg_play;

typedef FormData_pg_play *Form_pg_play;

#endif /* PG_PLAY_H */
```

每个系统表头文件都应该包含 `catalog/genbki.h` 头文件，该文件中定义了 `CATALOG`, `BKI_BOOTSTRAP` 等相关的宏。其中 `CATALOG` 宏的作用就是定义一个结构体变量，它的定义如下：

``` C
#define CppConcat(x, y)                   x##y
#define CATALOG(name,oid,oidmacro)  typedef struct CppConcat(FormData_,name)
```

而 `catalog/pg_class_d.h` 文件则是编译时由 `src/backend/catalog/genbki.pl` 生成的一个头文件，该文件中包含了系统表属性列的编号定义。例如，`pg_play` 系统表生成的内容如下：

``` C
/*-------------------------------------------------------------------------
 *
 * pg_play_d.h
 *    Macro definitions for pg_play
 *
 * Portions Copyright (c) 1996-2019, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * NOTES
 *  ******************************
 *  *** DO NOT EDIT THIS FILE! ***
 *  ******************************
 *
 *  It has been GENERATED by src/backend/catalog/genbki.pl
 *
 *-------------------------------------------------------------------------
 */
#ifndef PG_PLAY_D_H
#define PG_PLAY_D_H

#define PlayRelationId 2023

#define Anum_pg_play_playid 1
#define Anum_pg_play_playname 2

#define Natts_pg_play 2


#endif							/* PG_PLAY_D_H */
```

## 系统表编译配置

如上所述，我们添加了系统表定义，现在我们要做的就是将其添加到编译环境中，从而使得 PostgreSQL 在编译时可以去处理我们定义的 `pg_play` 系统表。在 `src/backend/catalog/Makefile` 文件中有一个 `CATALOG_HEADERS` 目标，如下所示：

``` C
CATALOG_HEADERS := \
         pg_proc.h pg_type.h pg_attribute.h pg_class.h \
         pg_attrdef.h pg_constraint.h pg_inherits.h pg_index.h pg_operator.h \
         pg_opfamily.h pg_opclass.h pg_am.h pg_amop.h pg_amproc.h \
         pg_language.h pg_largeobject_metadata.h pg_largeobject.h pg_aggregate.h \
         pg_statistic_ext.h \
         pg_statistic.h pg_rewrite.h pg_trigger.h pg_event_trigger.h pg_description.h \
         pg_cast.h pg_enum.h pg_namespace.h pg_conversion.h pg_depend.h \
         pg_database.h pg_db_role_setting.h pg_tablespace.h pg_pltemplate.h \
         pg_authid.h pg_auth_members.h pg_shdepend.h pg_shdescription.h \
         pg_ts_config.h pg_ts_config_map.h pg_ts_dict.h \
         pg_ts_parser.h pg_ts_template.h pg_extension.h \
         pg_foreign_data_wrapper.h pg_foreign_server.h pg_user_mapping.h \
         pg_foreign_table.h pg_policy.h pg_replication_origin.h \
         pg_default_acl.h pg_init_privs.h pg_seclabel.h pg_shseclabel.h \
         pg_collation.h pg_partitioned_table.h pg_range.h pg_transform.h \
         pg_sequence.h pg_publication.h pg_publication_rel.h pg_subscription.h \
         pg_subscription_rel.h pg_play.h
```

我们在末尾我们新建的 `pg_play` 系统表头文件。现在，我们在重新编译、安装并初始化数据库即可看到我们新建的 `pg_play` 系统表。如下图所示：

{% asset_img pg_play_catalog.png pg_play 系统表 %}

## 默认元组添加

如果我们需要想 `pg_play` 系统表中添加一些默认元组，我们可以创建一个 `pg_play.dat` 的文件，其内容如下：

``` perl
#----------------------------------------------------------------------
#
# pg_play.dat
#    Initial contents of the pg_play system catalog.
#
# src/include/catalog/pg_play.dat
#
#----------------------------------------------------------------------

[

{ playid => '2', playname => 'Play' },
{ playid => '3', playname => 'with' },
{ playid => '4', playname => 'PostgreSQL' },

]
```

然后需要在 `src/backend/catalog/Makefile` 文件的 `POSTGRES_BKI_DATA` 目标中添加 `pg_play.dat`。最后重新编译、安装并初始化数据库即可。

## 备注

1. 该方法适合于 PostgreSQL 11 以及后续版本，PostgreSQL 10 及之前的版本可能存在略微差异，但大致相同。