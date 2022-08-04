---
title: "PostgreSQL pg_db_role_setting 参数修改"
date: 2022-08-03 22:48:10 +0800
categories: 数据库
tags:
  - PostgreSQL
---

在{% post_link postgresql-parameters-for-database-and-role 上一篇 %}文章中介绍了如何修改用户或数据库级别的参数，已经它们的存储位置（`pg_db_role_setting` 系统表），本文简要说明一下关于这里的参数配置不当，从而导致无法连接数据库的问题。

<!--more-->

## 示例

我尝试通过 `ALTER ROLE all SET local_preload_libraries TO fdafd;` 修改配置，退出之后，我尝试重新登录时遇到如下问题（这里仅供测试，不要在生成环境这样操作，修改用户或数据库参数时，请确保参数的合法性）。

```
$ psql postgres
psql: error: connection to server on socket "/tmp/.s.PGSQL.5432" failed: FATAL:  could not access file "$libdir/plugins/fdafd": No such file or directory
```

嗷了个熬... :( 登录不上了，现在也没有机会修改了。该咋个办呢？

## 解决方案

在{% post_link postgresql-parameters-for-database-and-role 前面的文章 %}中我们提到 `pg_db_role_setting` 里面的参数是通过 `process_setting()` 函数加载的，我们再看看其实现：

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

从上面的代码，我们可以得知 `pg_db_role_setting` 中的参数仅在 `IsUnderPostmaster = true` 时才会被加载，因此我们可以使用单用户模式运行数据库实例（感谢 Kyotaro Horiguchi 给的建议），从而来修改这个参数。

```bash
$ pg_ctl stop
$ postgres --single postgres

PostgreSQL stand-alone backend 16devel
backend> SELECT * FROM pg_db_role_setting;
         1: setdatabase (typeid = 26, len = 4, typmod = -1, byval = t)
         2: setrole     (typeid = 26, len = 4, typmod = -1, byval = t)
         3: setconfig   (typeid = 1009, len = -1, typmod = -1, byval = f)
        ----
         1: setdatabase = "0"   (typeid = 26, len = 4, typmod = -1, byval = t)
         2: setrole = "0"       (typeid = 26, len = 4, typmod = -1, byval = t)
         3: setconfig = "{local_preload_libraries=fdafd}"       (typeid = 1009, len = -1, typmod = -1, byval = f)
        ----
```

接着我们重值该参数：

```bash
backend> ALTER ROLE ALL RESET local_preload_libraries;
backend> SELECT * FROM pg_db_role_setting;
         1: setdatabase (typeid = 26, len = 4, typmod = -1, byval = t)
         2: setrole     (typeid = 26, len = 4, typmod = -1, byval = t)
         3: setconfig   (typeid = 1009, len = -1, typmod = -1, byval = f)
        ----
```

接着按 `Ctrl-D` 退出单用户模式，并重启数据库，再次连接数据库，一切就正常了。上述解决方案最大的问题是需要重启数据库服务。

## 思考

我们是否可以提供一种方式，让其在线修改 `pg_db_role_setting` 参数的加载呢？答案是肯定可以的，但是社区不接受这样的修改。下面是引用 Tom Lane 对此的看法。

> There is not, and never will be, a version of Postgres in which it's impossible for a superuser to shoot himself in the foot.
>
> Test your settings more carefully before applying them to a production database that you can't afford to mess up.

但是谁又能 100% 保证这种事情不会发生呢？这个功能实现起来也不困难，我们只需要在一个参数即可，下面是一个样例。

```diff
diff --git a/src/backend/utils/init/postinit.c b/src/backend/utils/init/postinit.c
index 29f70accb2..decd828248 100644
--- a/src/backend/utils/init/postinit.c
+++ b/src/backend/utils/init/postinit.c
@@ -82,6 +82,7 @@ static bool ThereIsAtLeastOneRole(void);
 static void process_startup_options(Port *port, bool am_superuser);
 static void process_settings(Oid databaseid, Oid roleid);

+bool load_db_role_settings = true;

 /*** InitPostgres support ***/

@@ -1221,7 +1222,7 @@ process_settings(Oid databaseid, Oid roleid)
 	Relation	relsetting;
 	Snapshot	snapshot;

-	if (!IsUnderPostmaster)
+	if (!IsUnderPostmaster || !load_db_role_settings)
 		return;

 	relsetting = table_open(DbRoleSettingRelationId, AccessShareLock);
diff --git a/src/backend/utils/misc/guc.c b/src/backend/utils/misc/guc.c
index af4a1c3068..c0d14a9c6c 100644
--- a/src/backend/utils/misc/guc.c
+++ b/src/backend/utils/misc/guc.c
@@ -151,6 +151,8 @@ extern bool trace_syncscan;
 extern bool optimize_bounded_sort;
 #endif

+extern bool load_db_role_settings;
+
 static int	GUC_check_errcode_value;

 static List *reserved_class_prefix = NIL;
@@ -2182,6 +2184,15 @@ static struct config_bool ConfigureNamesBool[] =
 		NULL, NULL, NULL
 	},

+	{
+		{"load_db_role_settings", PGC_SIGHUP, CLIENT_CONN_PRELOAD,
+			gettext_noop("Whether to load parameters from pg_db_role_setting."),
+		},
+		&load_db_role_settings,
+		true,
+		NULL, NULL, NULL
+	},
+
 	/* End-of-list marker */
 	{
 		{NULL, 0, 0, NULL, NULL}, NULL, false, NULL, NULL, NULL
diff --git a/src/backend/utils/misc/postgresql.conf.sample b/src/backend/utils/misc/postgresql.conf.sample
index b4bc06e5f5..c71b7891d9 100644
--- a/src/backend/utils/misc/postgresql.conf.sample
+++ b/src/backend/utils/misc/postgresql.conf.sample
@@ -745,6 +745,7 @@

 #dynamic_library_path = '$libdir'
 #gin_fuzzy_search_limit = 0
+#load_db_role_settings = on


 #------------------------------------------------------------------------------
```

原以为这就完了，Too young, too simple! Daniel Verite 给出了一个更为优雅的解决方案，即通过 `PGOPTIONS` 选项来覆盖 `pg_db_role_setting` 中的配置。

```bash
$ PGOPTIONS="-c local_preload_libraries=" psql postgres
psql (16devel)
Type "help" for help.

postgres=#
```

{% asset_img graceful.png %}

下面是关于 `PGOPTIONS` 和 `pg_db_role_setting` 的处理流程，可以看得到 `PGOPTIONS` 的处理先于 `pg_db_role_setting`，这里后面的配置并不会覆盖前面的配置，因此程序在启动时采用了 `PGOPTIONS` 中的 `local_preload_libraries` 配置，我们也可以通过调试，在后续的 `process_session_preload_libraries()` 函数中看到 `local_preload_libraries` 的值为空（即 `PGOPTIONS` 中给出的值。

```c
void
InitPostgres(const char *in_dbname, Oid dboid,
             const char *username, Oid useroid,
             bool load_session_libraries,
             bool override_allow_connections,
             char *out_dbname)
{
    [...]

    /*
     * Now process any command-line switches and any additional GUC variable
     * settings passed in the startup packet.   We couldn't do this before
     * because we didn't know if client is a superuser.
     */
    if (MyProcPort != NULL)
        process_startup_options(MyProcPort, am_superuser);

    /* Process pg_db_role_setting options */
    process_settings(MyDatabaseId, GetSessionUserId());

    [....]

	/*
     * If this is an interactive session, load any libraries that should be
     * preloaded at backend start.  Since those are determined by GUCs, this
     * can't happen until GUC settings are complete, but we want it to happen
     * during the initial transaction in case anything that requires database
     * access needs to be done.
     */
    if (load_session_libraries)
        process_session_preload_libraries();

	[...]
}
```


## 参考

[1] https://www.postgresql.org/docs/current/app-postgres.html
[2] https://www.postgresql.org/message-id/MEYP282MB166955E4B68992FC86C4DC48B69A9%40MEYP282MB1669.AUSP282.PROD.OUTLOOK.COM


<div class="just-for-fun">
笑林广记 - 吃乳饼

富翁与人论及童子多肖乳母，为吃其乳，气相感也。
其人谓富翁曰：“若是如此，想来足下从幼是吃乳饼长大的。”
</div>
