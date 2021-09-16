---
title: "PostgreSQL 共享表"
date: 2020-08-08 15:15:41 +0800
category: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

PostgreSQL 数据库中提供的某些系统表是 Cluster 级别共享的，他们在数据库内部被称为 `shared_relation`，本文就介绍一下 PostgreSQL 是如何创建共享表的。

<!-- more -->

## SQL 查询

我们可以通过下面的语句查看系统中提供的共享表。

```sql
SELECT
    c.oid
    , c.relname
FROM
    pg_class c LEFT JOIN pg_tablespace t
        ON c.reltablespace = t.oid
WHERE
    c.relisshared = true
    AND c.relkind = 'r'
ORDER BY c.oid;
 oid  |        relname
------+-----------------------
 1136 | pg_pltemplate
 1213 | pg_tablespace
 1214 | pg_shdepend
 1260 | pg_authid
 1261 | pg_auth_members
 1262 | pg_database
 2396 | pg_shdescription
 2964 | pg_db_role_setting
 3592 | pg_shseclabel
 6000 | pg_replication_origin
 6100 | pg_subscription
(11 rows)
```

其实除了上述的基本表之外，这些表上的索引和 TOAST 也是共享的。

```sql
SELECT
    c.oid
    , c.relname
FROM
    pg_class c LEFT JOIN pg_tablespace t
        ON c.reltablespace = t.oid
WHERE
    c.relisshared = true
ORDER BY c.oid;
 oid  |                 relname
------+-----------------------------------------
 1136 | pg_pltemplate
 1137 | pg_pltemplate_name_index
 1213 | pg_tablespace
 1214 | pg_shdepend
 1232 | pg_shdepend_depender_index
 1233 | pg_shdepend_reference_index
 1260 | pg_authid
 1261 | pg_auth_members
 1262 | pg_database
 2396 | pg_shdescription
 2397 | pg_shdescription_o_c_index
 2671 | pg_database_datname_index
 2672 | pg_database_oid_index
 2676 | pg_authid_rolname_index
 2677 | pg_authid_oid_index
 2694 | pg_auth_members_role_member_index
 2695 | pg_auth_members_member_role_index
 2697 | pg_tablespace_oid_index
 2698 | pg_tablespace_spcname_index
 2846 | pg_toast_2396
 2847 | pg_toast_2396_index
 2964 | pg_db_role_setting
 2965 | pg_db_role_setting_databaseid_rol_index
 2966 | pg_toast_2964
 2967 | pg_toast_2964_index
 3592 | pg_shseclabel
 3593 | pg_shseclabel_object_index
 4060 | pg_toast_3592
 4061 | pg_toast_3592_index
 6000 | pg_replication_origin
 6001 | pg_replication_origin_roiident_index
 6002 | pg_replication_origin_roname_index
 6100 | pg_subscription
 6114 | pg_subscription_oid_index
 6115 | pg_subscription_subname_index
(35 rows)
```

PostgreSQL 中共享表的都是存储在 pg_global 这个表空间中的。

## 源码分析

在源码中，PostgreSQL 通过 `IsSharedRelation()` 函数来判断表是否为共享表。

```C
bool
IsSharedRelation(Oid relationId)
{
    /* These are the shared catalogs (look for BKI_SHARED_RELATION) */
    if (relationId == AuthIdRelationId ||
        relationId == AuthMemRelationId ||
        relationId == DatabaseRelationId ||
        relationId == PLTemplateRelationId ||
        relationId == SharedDescriptionRelationId ||
        relationId == SharedDependRelationId ||
        relationId == SharedSecLabelRelationId ||
        relationId == TableSpaceRelationId ||
        relationId == DbRoleSettingRelationId ||
        relationId == ReplicationOriginRelationId ||
        relationId == SubscriptionRelationId)
        return true;
    /* These are their indexes (see indexing.h) */
    if (relationId == AuthIdRolnameIndexId ||
        relationId == AuthIdOidIndexId ||
        relationId == AuthMemRoleMemIndexId ||
        relationId == AuthMemMemRoleIndexId ||
        relationId == DatabaseNameIndexId ||
        relationId == DatabaseOidIndexId ||
        relationId == PLTemplateNameIndexId ||
        relationId == SharedDescriptionObjIndexId ||
        relationId == SharedDependDependerIndexId ||
        relationId == SharedDependReferenceIndexId ||
        relationId == SharedSecLabelObjectIndexId ||
        relationId == TablespaceOidIndexId ||
        relationId == TablespaceNameIndexId ||
        relationId == DbRoleSettingDatidRolidIndexId ||
        relationId == ReplicationOriginIdentIndex ||
        relationId == ReplicationOriginNameIndex ||
        relationId == SubscriptionObjectIndexId ||
        relationId == SubscriptionNameIndexId)
        return true;
    /* These are their toast tables and toast indexes (see toasting.h) */
    if (relationId == PgAuthidToastTable ||
        relationId == PgAuthidToastIndex ||
        relationId == PgDatabaseToastTable ||
        relationId == PgDatabaseToastIndex ||
        relationId == PgDbRoleSettingToastTable ||
        relationId == PgDbRoleSettingToastIndex ||
        relationId == PgPlTemplateToastTable ||
        relationId == PgPlTemplateToastIndex ||
        relationId == PgReplicationOriginToastTable ||
        relationId == PgReplicationOriginToastIndex ||
        relationId == PgShdescriptionToastTable ||
        relationId == PgShdescriptionToastIndex ||
        relationId == PgShseclabelToastTable ||
        relationId == PgShseclabelToastIndex ||
        relationId == PgSubscriptionToastTable ||
        relationId == PgSubscriptionToastIndex ||
        relationId == PgTablespaceToastTable ||
        relationId == PgTablespaceToastIndex)
        return true;
    return false;
}
```

这和我们在上面看到的是一致的。

那么 PostgreSQL 是如何定义共享表的呢？我们知道 PostgreSQL 的系统表都是定义在 `src/include/catalog/` 目录下。那么我们看看 `pg_authid` 这个共享表是如何定义的。

```
CATALOG(pg_authid,1260,AuthIdRelationId) BKI_SHARED_RELATION BKI_ROWTYPE_OID(2842,AuthIdRelation_Rowtype_Id) BKI_SCHEMA_MACRO
{
    Oid         oid;            /* oid */
    NameData    rolname;        /* name of role */
    bool        rolsuper;       /* read this field via superuser() only! */
    bool        rolinherit;     /* inherit privileges from other roles? */
    bool        rolcreaterole;  /* allowed to create more roles? */
    bool        rolcreatedb;    /* allowed to create databases? */
    bool        rolcanlogin;    /* allowed to log in as session user? */
    bool        rolreplication; /* role used for streaming replication */
    bool        rolbypassrls;   /* bypasses row level security? */
    int32       rolconnlimit;   /* max connections allowed (-1=no limit) */

    /* remaining fields may be null; use heap_getattr to read them! */
#ifdef CATALOG_VARLEN           /* variable-length fields start here */
    text        rolpassword;    /* password, if any */
    timestamptz rolvaliduntil;  /* password expiration time, if any */
#endif
} FormData_pg_authid;
```

我们可以看到这里有一个 `BKI_SHARED_RELATION` 宏，因此，我们推测只要加上这个宏，那么这个系统表就是共享的。我们可以通过对比其他系统表来进行验证。

所有的系统表定义都将通过 `Catalog.pm` 来转换为 Perl 中的数据结构，最后通过 `genbki.pl` 脚步转换为 `postgres.bki` 文件，而 BKI 文件则用于初始化 PostgreSQL 模版数据库。

例如，`pg_authid` 经过转换之后在 `postgres.bki` 中的内容如下所示：

```
create pg_authid 1260 shared_relation rowtype_oid 2842
 (
 oid = oid ,
 rolname = name ,
 rolsuper = bool ,
 rolinherit = bool ,
 rolcreaterole = bool ,
 rolcreatedb = bool ,
 rolcanlogin = bool ,
 rolreplication = bool ,
 rolbypassrls = bool ,
 rolconnlimit = int4 ,
 rolpassword = text ,
 rolvaliduntil = timestamptz
 )
open pg_authid
insert ( 10 POSTGRES t t t t t t t -1 _null_ _null_ )
insert ( 3373 pg_monitor f t f f f f f -1 _null_ _null_ )
insert ( 3374 pg_read_all_settings f t f f f f f -1 _null_ _null_ )
insert ( 3375 pg_read_all_stats f t f f f f f -1 _null_ _null_ )
insert ( 3377 pg_stat_scan_tables f t f f f f f -1 _null_ _null_ )
insert ( 4569 pg_read_server_files f t f f f f f -1 _null_ _null_ )
insert ( 4570 pg_write_server_files f t f f f f f -1 _null_ _null_ )
insert ( 4571 pg_execute_server_program f t f f f f f -1 _null_ _null_ )
insert ( 4200 pg_signal_backend f t f f f f f -1 _null_ _null_ )
close pg_authid
```

当我们使用 initdb 初始化数据库时，`setup_data_file_paths()` 函数将会设置 `postgres.bki` 文件路径，随后通过 `initialize_data_directory()` 函数调用 `bootstrap_template1()` 函数来读取 `postgres.bki` 文件中的内容初始化模版数据库。

最后通过 `postgres --boot -x1 -X 16777216 -F` 命令来初始化 `template1` 数据库，在 src/backend/main/main.c 文件中，我们可以看到如下代码：

```c
int
main(int argc, char *argv[])
{
    ...
    if (argc > 1 && strcmp(argv[1], "--boot") == 0)
        AuxiliaryProcessMain(argc, argv);   /* does not return */
    else if (argc > 1 && strcmp(argv[1], "--describe-config") == 0)
        GucInfoMain();          /* does not return */
    else if (argc > 1 && strcmp(argv[1], "--single") == 0)
        PostgresMain(argc, argv,
                     NULL,      /* no dbname */
                     strdup(get_user_name_or_exit(progname)));  /* does not return */
    else
        PostmasterMain(argc, argv); /* does not return */
    abort();                    /* should not get here */
}
```

从上面可以看到，在 initdb 的时候执行的是 `AuxiliaryProcessMain()` 函数，该函数可以用于创建多种类型的辅助进程，例如，Checkpointer、WAL writer 和 WAL receiver 等进程，该函数通过参数 `-x num` 来创建不同的进程，有如下辅助进程：

```c
/*
 * Auxiliary-process type identifiers.  These used to be in bootstrap.h
 * but it seems saner to have them here, with the ProcessingMode stuff.
 * The MyAuxProcType global is defined and set in bootstrap.c.
 */

typedef enum
{
    NotAnAuxProcess = -1,
    CheckerProcess = 0,
    BootstrapProcess,
    StartupProcess,
    BgWriterProcess,
    CheckpointerProcess,
    WalWriterProcess,
    WalReceiverProcess,

    NUM_AUXPROCTYPES            /* Must be last! */
} AuxProcType;

extern AuxProcType MyAuxProcType;
```

从 `initdb` 中传递过来的参数可以看到，我们的辅助进程类型为 `BootstrapProcess`，最后执行下面的内容：

```c
AuxiliaryProcessMain(int argc, char *argv[])
{
    ...

    switch (MyAuxProcType)
    {
        case CheckerProcess:
            /* don't set signals, they're useless here */
            CheckerModeMain();
            proc_exit(1);       /* should never return */

        case BootstrapProcess:

            /*
             * There was a brief instant during which mode was Normal; this is
             * okay.  We need to be in bootstrap mode during BootStrapXLOG for
             * the sake of multixact initialization.
             */
            SetProcessingMode(BootstrapProcessing);
            bootstrap_signals();
            BootStrapXLOG();
            BootstrapModeMain();
            proc_exit(1);       /* should never return */
        ...
    }
}
```

这里我们关注一下 `BootStrapXLOG()` 函数，在{% post_link postgresql-system-identifier PostgreSQL 数据库系统标识符%}的文章中我们介绍了这个函数将会创建数据库标识符，此外，他还将创建 `pg_control` 文件，XLOG 日志文件以及 CLOG 文件。

接着我们看看 `BootstrapModeMain()` 函数，该函数以 `bootstrap` 模式运行，并且处理 PostgreSQL 提供的特殊的 `bootstrap` 语法，即 `postgres.bki` 文件中的内容。

```c
/*
 *   The main entry point for running the backend in bootstrap mode
 *
 *   The bootstrap mode is used to initialize the template database.
 *   The bootstrap backend doesn't speak SQL, but instead expects
 *   commands in a special bootstrap language.
 */
static void
BootstrapModeMain(void)
{
    int         i;

    Assert(!IsUnderPostmaster);
    Assert(IsBootstrapProcessingMode());

    /*
     * To ensure that src/common/link-canary.c is linked into the backend, we
     * must call it from somewhere.  Here is as good as anywhere.
     */
    if (pg_link_canary_is_frontend())
        elog(ERROR, "backend is incorrectly linked to frontend functions");

    /*
     * Do backend-like initialization for bootstrap mode
     */
    InitProcess();

    InitPostgres(NULL, InvalidOid, NULL, InvalidOid, NULL, false);

    /* Initialize stuff for bootstrap-file processing */
    for (i = 0; i < MAXATTR; i++)
    {
        attrtypes[i] = NULL;
        Nulls[i] = false;
    }

    /*
     * Process bootstrap input.
     */
    StartTransactionCommand();
    boot_yyparse();
    CommitTransactionCommand();

    /*
     * We should now know about all mapped relations, so it's okay to write
     * out the initial relation mapping files.
     */
    RelationMapFinishBootstrap();

    /* Clean up and exit */
    cleanup();
    proc_exit(0);
}
```

从代码的注释我们可以看到整个 `postgres.bki` 文件的处理是通过 `boot_yyparse()` 函数来进行的，这个函数是由 `bootparse.y` 文件提供的，其实就是处理有关 `postgres.bki` 文件的语法，并将其转化为不同的对象进而调用 PostgreSQL 内部提供的函数。例如，创建 `pg_authid` 这个系统表，将会执行以下内容：

```c
Boot_CreateStmt:
          XCREATE boot_ident oidspec optbootstrap optsharedrelation optrowtypeoid LPAREN
                {
                    do_start();
                    numattr = 0;
                    elog(DEBUG4, "creating%s%s relation %s %u",
                         $4 ? " bootstrap" : "",
                         $5 ? " shared" : "",
                         $2,
                         $3);
                }
          boot_column_list
                {
                    do_end();
                }
          RPAREN
                {
                    TupleDesc tupdesc;
                    bool    shared_relation;
                    bool    mapped_relation;

                    do_start();

                    tupdesc = CreateTupleDesc(numattr, attrtypes);

                    shared_relation = $5;

                    /*
                     * The catalogs that use the relation mapper are the
                     * bootstrap catalogs plus the shared catalogs.  If this
                     * ever gets more complicated, we should invent a BKI
                     * keyword to mark the mapped catalogs, but for now a
                     * quick hack seems the most appropriate thing.  Note in
                     * particular that all "nailed" heap rels (see formrdesc
                     * in relcache.c) must be mapped.
                     */
                    mapped_relation = ($4 || shared_relation);

                    if ($4)
                    {
                        TransactionId relfrozenxid;
                        MultiXactId relminmxid;

                        if (boot_reldesc)
                        {
                            elog(DEBUG4, "create bootstrap: warning, open relation exists, closing first");
                            closerel(NULL);
                        }

                        boot_reldesc = heap_create($2,
                                                   PG_CATALOG_NAMESPACE,
                                                   shared_relation ? GLOBALTABLESPACE_OID : 0,
                                                   $3,
                                                   InvalidOid,
                                                   HEAP_TABLE_AM_OID,
                                                   tupdesc,
                                                   RELKIND_RELATION,
                                                   RELPERSISTENCE_PERMANENT,
                                                   shared_relation,
                                                   mapped_relation,
                                                   true,
                                                   &relfrozenxid,
                                                   &relminmxid);
                        elog(DEBUG4, "bootstrap relation created");
                    }
                    else
                    {
                        Oid id;

                        id = heap_create_with_catalog($2,
                                                      PG_CATALOG_NAMESPACE,
                                                      shared_relation ? GLOBALTABLESPACE_OID : 0,
                                                      $3,
                                                      $6,
                                                      InvalidOid,
                                                      BOOTSTRAP_SUPERUSERID,
                                                      HEAP_TABLE_AM_OID,
                                                      tupdesc,
                                                      NIL,
                                                      RELKIND_RELATION,
                                                      RELPERSISTENCE_PERMANENT,
                                                      shared_relation,
                                                      mapped_relation,
                                                      ONCOMMIT_NOOP,
                                                      (Datum) 0,
                                                      false,
                                                      true,
                                                      false,
                                                      InvalidOid,
                                                      NULL);
                        elog(DEBUG4, "relation created with OID %u", id);
                    }
                    do_end();
                }
        ;
```

这里我们可以看到 `postgres.bki` 中的表也是通过 `heap_create_with_catalog()` 函数来创建的。需要注意的是，我们在通过 SQL 创建表的时候虽然也是通过 `heap_create_with_catalog()` 来新建表的，但是其参数 `shared_relation` 始终为 `false`。

PostgreSQL 的 BKI 文件提供了一下几种基本都命令：

```
create - 创建一个表
open - 打开一个表
close - 关闭一个表
declare toast - 创建 TOAST 表
insert - 向表中插入数据
declare index - 声明索引
declare unique index - 声明唯一性索引
build indices - 创建索引
```
关于各个命令的语法这里就不详细介绍了，感兴趣的朋友可以去看 `postgres.bki` 和 `bootstrap.y` 文件。至此，我们对 PostgreSQL 中的共享表的创建有了一个粗略的认识。
