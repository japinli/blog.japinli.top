---
title: "PostgreSQL 修改用户或数据库参数"
date: 2022-08-01 22:27:02 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

PostgreSQL 支持不同级别的参数配置，最简单的是全局配置，此外还有针对用户级别和数据库级别的配置，本文就来看看 PostgreSQL 中用户级别和数据库级别的配置的实现。

我们可以实现下面的 SQL 命令来修改用户级别的配置：

```sql
ALTER ROLE { role_specification | ALL } [ IN DATABASE database_name ] SET configuration_parameter { TO | = } { value | DEFAULT }
ALTER ROLE { role_specification | ALL } [ IN DATABASE database_name ] SET configuration_parameter FROM CURRENT
ALTER ROLE { role_specification | ALL } [ IN DATABASE database_name ] RESET configuration_parameter
ALTER ROLE { role_specification | ALL } [ IN DATABASE database_name ] RESET ALL
```

从上面的语法可以看出 PostgreSQL 配置的灵活性，您可以针对某个用户进行配置，也可以针对某个用户连接某个数据库进行配置。

数据库级别的配置相对于用户级别来说就要简单一些了，如下所示：

```sql
ALTER DATABASE name SET configuration_parameter { TO | = } { value | DEFAULT }
ALTER DATABASE name SET configuration_parameter FROM CURRENT
ALTER DATABASE name RESET configuration_parameter
ALTER DATABASE name RESET ALL
```

<!--more-->

例如，我们想将当前用户连接数据库的 `work_mem` 修改为 `64M`，使用下面的命令即可：

```sql
ALTER ROLE current_user SET work_mem TO '64MB';
```

当我们重新登录时，可以发现 `work_mem` 变成了 `64MB`，如果我们换一个用户登录，可以发现其 `work_mem` 仍然为默认的 `4MB`。接下来我们新建一个 `testdb` 数据库，并修改当前用户登录该数据库的 `work_mem` 设置为 `32MB`。

```sql
CREATE DATABASE testdb;
ALTER USER current_user IN DATABASE testdb SET work_mem TO '32MB';
```

我们再次使用当前用户登录 `testdb` 数据库，可以发现此时 `work_mem` 是 `32MB`，而不是 `64MB`。

数据库的参数修改类似，例如，修改 `testdb` 的 `maintenance_work_mem` 为 `128MB`。

```sql
ALTER DATABASE testdb SET maintenance_work_mem TO '128MB';
```

接着使用当前用户登录 `testdb` 数据库时，`maintenance_work_mem` 被设置为 `128MB`，当我们切换到其他数据库时，`maintenance_work_mem` 还是默认的 `64MB`。

我们知道全局的配置信息是存储在配置文件（`postgresql.conf` 或 `postgresql.auto.conf`）中，那上述命令修改的配置存放在哪儿呢？

通过查看系统表，我们可以看到有一个 `pg_db_role_setting` 的表，大胆猜测一下就是这个表来存储上述的参数信息了。

```sql
# SELECT * FROM pg_db_role_setting;
 setdatabase | setrole |          setconfig
-------------+---------+------------------------------
           0 |      10 | {work_mem=64MB}
       16388 |      10 | {work_mem=32MB}
           0 |       0 | {work_mem=1MB}
       16388 |       0 | {maintenance_work_mem=128MB}
(4 rows)
```

不出所料，果然是该表存储了上述参数信息。如果不熟悉 PostgreSQL 的系统表，我们也可以从源码来分析其存放的位置。

既然可以通过 `ALTER ROLE` 的方式进行修改，那么我们看看 `gram.y` 中关于 `ALTER ROLE` 是如何做语法分析的。通过搜索 `AlterRole`，我们可以找到如下代码段：

```c
AlterRoleSetStmt:
            ALTER ROLE RoleSpec opt_in_database SetResetClause
                {
                    AlterRoleSetStmt *n = makeNode(AlterRoleSetStmt);

                    n->role = $3;
                    n->database = $4;
                    n->setstmt = $5;
                    $$ = (Node *) n;
                }
            | ALTER ROLE ALL opt_in_database SetResetClause
                {
                    AlterRoleSetStmt *n = makeNode(AlterRoleSetStmt);

                    n->role = NULL;
                    n->database = $4;
                    n->setstmt = $5;
                    $$ = (Node *) n;
                }
            | ALTER USER RoleSpec opt_in_database SetResetClause
                {
                    AlterRoleSetStmt *n = makeNode(AlterRoleSetStmt);

                    n->role = $3;
                    n->database = $4;
                    n->setstmt = $5;
                    $$ = (Node *) n;
                }
            | ALTER USER ALL opt_in_database SetResetClause
                {
                    AlterRoleSetStmt *n = makeNode(AlterRoleSetStmt);

                    n->role = NULL;
                    n->database = $4;
                    n->setstmt = $5;
                    $$ = (Node *) n;
                }
        ;
```

显然，关于 `ALTER ROLE ... SET ...` 是通过 `AlterRoleSetStmt` 来解析的，再次搜索：

```bash
$ grep 'AlterRoleSetStmt' -rn src/ --include '*.c'
src/backend/commands/user.c:828:AlterRoleSet(AlterRoleSetStmt *stmt)
src/backend/tcop/utility.c:159:         case T_AlterRoleSetStmt:
src/backend/tcop/utility.c:919:         case T_AlterRoleSetStmt:
src/backend/tcop/utility.c:921:                 AlterRoleSet((AlterRoleSetStmt *) parsetree);
src/backend/tcop/utility.c:2962:                case T_AlterRoleSetStmt:
src/backend/tcop/utility.c:3583:                case T_AlterRoleSetStmt:
```

可以发现其在 `src/backend/commands/user.c` 文件中有一个 `AlterRoleSet()` 的函数，那么一切就明朗了，查看 `AlterRoleSet()` 函数，其核心是调用 `AlterSetting()` 来修改配置。

```c
/*
 * ALTER ROLE ... SET
 */
Oid
AlterRoleSet(AlterRoleSetStmt *stmt)
{
    [...]

    AlterSetting(databaseid, roleid, stmt->setstmt);

    return roleid;
}
```

而 `AlterSetting()` 则是读写 `pg_db_role_setting` 系统表来完成配置的修改。

```c
void
AlterSetting(Oid databaseid, Oid roleid, VariableSetStmt *setstmt)
{
    [...]

    rel = table_open(DbRoleSettingRelationId, RowExclusiveLock);
    ScanKeyInit(&scankey[0],
                Anum_pg_db_role_setting_setdatabase,
                BTEqualStrategyNumber, F_OIDEQ,
                ObjectIdGetDatum(databaseid));
    ScanKeyInit(&scankey[1],
                Anum_pg_db_role_setting_setrole,
                BTEqualStrategyNumber, F_OIDEQ,
                ObjectIdGetDatum(roleid));
    scan = systable_beginscan(rel, DbRoleSettingDatidRolidIndexId, true,
                              NULL, 2, scankey);
    tuple = systable_getnext(scan);

    /*
     * There are three cases:
     *
     * - in RESET ALL, request GUC to reset the settings array and update the
     * catalog if there's anything left, delete it otherwise
     *
     * - in other commands, if there's a tuple in pg_db_role_setting, update
     * it; if it ends up empty, delete it
     *
     * - otherwise, insert a new pg_db_role_setting tuple, but only if the
     * command is not RESET
     */

    [...]

    InvokeObjectPostAlterHookArg(DbRoleSettingRelationId,
                                 databaseid, 0, roleid, false);

    systable_endscan(scan);

    /* Close pg_db_role_setting, but keep lock till commit */
    table_close(rel, NoLock);
}
```

类似的，您也可以找到 `AlterDatabaseSet()` 函数，其本质上也是调用 `AlterSetting()` 函数来进行修改。

从上面的配置，我们可以看出，这些选项可能在不同的级别上存在冲突。例如：

```sql
ALTER DATABASE testdb SET temp_buffers TO '10MB';
ALTER ROLE current_user SET temp_buffers TO '11MB';
ALTER ROLE current_user IN DATABASE testdb SET temp_buffers TO '12MB';
```

```sql
# SELECT * FROM pg_db_role_setting;
 setdatabase | setrole |                   setconfig
-------------+---------+------------------------------------------------
           0 |       0 | {work_mem=1MB}
       16388 |       0 | {maintenance_work_mem=128MB,temp_buffers=10MB}
           0 |      10 | {work_mem=64MB,temp_buffers=11MB}
       16388 |      10 | {work_mem=32MB,temp_buffers=12MB}
(4 rows)
```

我们重新登录，查看 `temp_buffers`，其结构如下所示：

```sql
testdb=# SHOW temp_buffers;
 temp_buffers
--------------
 12MB
(1 row)
```

那它是如何加载这些参数的呢？以及它们的优先级设怎样的呢？我们可以在 `src/backend/catalog/pg_db_role_setting.c` 文件中看到 `ApplySetting()` 函数，通过查找该函数，我们可以知道它是由 `process_settings()` 函数调用的，如下所示：

```c
/*
 * Load GUC settings from pg_db_role_setting.
 *
 * We try specific settings for the database/role combination, as well as
 * general for this database and for this user.
 */
static void
process_settings(Oid databaseid, Oid roleid)
{
    Relation    relsetting;
    Snapshot    snapshot;

    if (!IsUnderPostmaster)
        return;

    relsetting = table_open(DbRoleSettingRelationId, AccessShareLock);

    /* read all the settings under the same snapshot for efficiency */
    snapshot = RegisterSnapshot(GetCatalogSnapshot(DbRoleSettingRelationId));

    /* Later settings are ignored if set earlier. */
    ApplySetting(snapshot, databaseid, roleid, relsetting, PGC_S_DATABASE_USER);
    ApplySetting(snapshot, InvalidOid, roleid, relsetting, PGC_S_USER);
    ApplySetting(snapshot, databaseid, InvalidOid, relsetting, PGC_S_DATABASE);
    ApplySetting(snapshot, InvalidOid, InvalidOid, relsetting, PGC_S_GLOBAL);

    UnregisterSnapshot(snapshot);
    table_close(relsetting, AccessShareLock);
}
```

而 `process_settings()` 函数则是在 backend 进程起来之后由 `PostgresMain()` 到 `InitPostgres()` 调用，在之后便是接收客户端的请求，并执行相应的查询。至此，我们便找到了这些参数的加载过程。根据上面的参数应用规则，我们可以得到如下所示的参数优先级示意图：

{% asset_img parameter-priority.png %}

关于参数是如何应用的，不在本文的讨论范畴，感兴趣的朋友可以去看看 `ProcessGUCArray()` 函数以及 PostgreSQL guc 的相关处理过程。

## 参考

[1] https://www.postgresql.org/docs/current/sql-alterdatabase.html
[2] https://www.postgresql.org/docs/current/sql-alterrole.html
[3] https://www.postgresql.org/docs/current/catalog-pg-db-role-setting.html

<div class="just-for-fun">
笑林广记 - 江心赋

有富翁同友远出，泊舟江中，偶上岸散步，见壁间题“江心赋”三字，错认“赋”字为“贼”字，惊欲走匿。
友问故，指曰：“此处有贼。”
友曰：“赋也，非贼也。”
其人曰：“赋便赋了，终是有些贼形。”
</div>
