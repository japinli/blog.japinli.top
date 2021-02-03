---
title: "PostgreSQL 空闲会话超时"
date: 2021-01-23 22:50:11 +0800
category: 数据库
tags:
  - PostgreSQL
---

经过约八个月的努力，终于完成了 PostgreSQL 空闲会话超时断开的功能，该功能将在版本 14 中发布。这是我第一次向 PostgreSQL 提供功能，虽然之前也有向社区提供过补丁，但是这次整个功能（相对比较简单）被接受还是比较高兴的，感谢社区各位大佬的帮助和反馈。

{% asset_img idle_session_timeout-commit-message.png %}

<!-- more -->

## 使用

正如提交日志所描述的，我们可以通过设置 `idle_session_timeout` 参数来指定空闲会话断开的时机。首先，我们看看该参数的说明。


```
postgres=# select * from pg_settings where name = 'idle_session_timeout' \gx
-[ RECORD 1 ]---+-------------------------------------------------------------------------------
name            | idle_session_timeout
setting         | 0
unit            | ms
category        | Client Connection Defaults / Statement Behavior
short_desc      | Sets the maximum allowed idle time between queries, when not in a transaction.
extra_desc      | A value of 0 turns off the timeout.
context         | user
vartype         | integer
source          | default
min_val         | 0
max_val         | 2147483647
enumvals        |
boot_val        | 0
reset_val       | 0
sourcefile      |
sourceline      |
pending_restart | f
```

接着，我们修改配置并重新载入，随后查看该功能是否有效。

```
postgres=# alter system set idle_session_timeout to 10000;
ALTER SYSTEM
postgres=# select pg_reload_conf();
 pg_reload_conf
----------------
 t
(1 row)

postgres=# SELECT 1;
 ?column?
----------
        1
(1 row)

postgres=# select * from pg_settings where name = 'idle_session_timeout' \gx
-[ RECORD 1 ]---+-------------------------------------------------------------------------------
name            | idle_session_timeout
setting         | 10000
unit            | ms
category        | Client Connection Defaults / Statement Behavior
short_desc      | Sets the maximum allowed idle time between queries, when not in a transaction.
extra_desc      | A value of 0 turns off the timeout.
context         | user
vartype         | integer
source          | configuration file
min_val         | 0
max_val         | 2147483647
enumvals        |
boot_val        | 0
reset_val       | 10000
sourcefile      | /Users/japinli/Codes/postgresql/Debug/pg/pgdata/postgresql.auto.conf
sourceline      | 3
pending_restart | f
```

随后，等待 10s，我们可以从日志中看到如下内容。

```
2021-01-23 23:26:38.350 CST [20695] FATAL:  terminating connection due to idle-session timeout
```

我们再返回之前的 session，确认连接是否已经断开。

```
postgres=# SELEC 1;
FATAL:  terminating connection due to idle-session timeout
server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.
The connection to the server was lost. Attempting reset: Succeeded.
```

从上面可以看到，之前的 session 已经断开连接，我们可以通过 ps 来查看对应的进程。

PostgreSQL 数据库是采用的进程模型，因此每个连接都会对应一个后端进程，该后端进程将分配系统资源（例如内存，work_mem），大量的空闲会话将导致内存无法得到有效的使用，有了空闲会话超时功能我们可以设置超时时间来避免空闲会话占用系统资源。

## 实现

该功能的实现与 `idle_in_transaction_session_timeout` 相似。

``` diff
diff --git a/doc/src/sgml/config.sgml b/doc/src/sgml/config.sgml
index 425f57901d..15b94c96c0 100644
--- a/doc/src/sgml/config.sgml
+++ b/doc/src/sgml/config.sgml
@@ -8310,15 +8310,52 @@ COPY postgres_log FROM '/full/path/to/logfile.csv' WITH csv;
       </term>
       <listitem>
        <para>
-       Terminate any session with an open transaction that has been idle for
-       longer than the specified amount of time. This allows any
-       locks held by that session to be released and the connection slot to be reused;
-       it also allows tuples visible only to this transaction to be vacuumed.  See
-       <xref linkend="routine-vacuuming"/> for more details about this.
+        Terminate any session that has been idle (that is, waiting for a
+        client query) within an open transaction for longer than the
+        specified amount of time.
+        If this value is specified without units, it is taken as milliseconds.
+        A value of zero (the default) disables the timeout.
+       </para>
+
+       <para>
+        This option can be used to ensure that idle sessions do not hold
+        locks for an unreasonable amount of time.  Even when no significant
+        locks are held, an open transaction prevents vacuuming away
+        recently-dead tuples that may be visible only to this transaction;
+        so remaining idle for a long time can contribute to table bloat.
+        See <xref linkend="routine-vacuuming"/> for more details.
+       </para>
+      </listitem>
+     </varlistentry>
+
+     <varlistentry id="guc-idle-session-timeout" xreflabel="idle_session_timeout">
+      <term><varname>idle_session_timeout</varname> (<type>integer</type>)
+      <indexterm>
+       <primary><varname>idle_session_timeout</varname> configuration parameter</primary>
+      </indexterm>
+      </term>
+      <listitem>
+       <para>
+        Terminate any session that has been idle (that is, waiting for a
+        client query), but not within an open transaction, for longer than
+        the specified amount of time.
+        If this value is specified without units, it is taken as milliseconds.
+        A value of zero (the default) disables the timeout.
        </para>
+
+       <para>
+        Unlike the case with an open transaction, an idle session without a
+        transaction imposes no large costs on the server, so there is less
+        need to enable this timeout
+        than <varname>idle_in_transaction_session_timeout</varname>.
+       </para>
+
        <para>
-       If this value is specified without units, it is taken as milliseconds.
-       A value of zero (the default) disables the timeout.
+        Be wary of enforcing this timeout on connections made through
+        connection-pooling software or other middleware, as such a layer
+        may not react well to unexpected connection closure.  It may be
+        helpful to enable this timeout only for interactive sessions,
+        perhaps by applying it only to particular users.
        </para>
       </listitem>
      </varlistentry>
diff --git a/src/backend/storage/lmgr/proc.c b/src/backend/storage/lmgr/proc.c
index 9b6aa2fe0d..0366a7cc00 100644
--- a/src/backend/storage/lmgr/proc.c
+++ b/src/backend/storage/lmgr/proc.c
@@ -61,6 +61,7 @@ int			DeadlockTimeout = 1000;
 int			StatementTimeout = 0;
 int			LockTimeout = 0;
 int			IdleInTransactionSessionTimeout = 0;
+int			IdleSessionTimeout = 0;
 bool		log_lock_waits = false;

 /* Pointer to this process's PGPROC struct, if any */
diff --git a/src/backend/tcop/postgres.c b/src/backend/tcop/postgres.c
index 9d98c028a2..2b53ebf97d 100644
--- a/src/backend/tcop/postgres.c
+++ b/src/backend/tcop/postgres.c
@@ -3242,14 +3242,28 @@ ProcessInterrupts(void)

 	if (IdleInTransactionSessionTimeoutPending)
 	{
-		/* Has the timeout setting changed since last we looked? */
+		/*
+		 * If the GUC has been reset to zero, ignore the signal.  This is
+		 * important because the GUC update itself won't disable any pending
+		 * interrupt.
+		 */
 		if (IdleInTransactionSessionTimeout > 0)
 			ereport(FATAL,
 					(errcode(ERRCODE_IDLE_IN_TRANSACTION_SESSION_TIMEOUT),
 					 errmsg("terminating connection due to idle-in-transaction timeout")));
 		else
 			IdleInTransactionSessionTimeoutPending = false;
+	}

+	if (IdleSessionTimeoutPending)
+	{
+		/* As above, ignore the signal if the GUC has been reset to zero. */
+		if (IdleSessionTimeout > 0)
+			ereport(FATAL,
+					(errcode(ERRCODE_IDLE_SESSION_TIMEOUT),
+					 errmsg("terminating connection due to idle-session timeout")));
+		else
+			IdleSessionTimeoutPending = false;
 	}

 	if (ProcSignalBarrierPending)
@@ -3826,7 +3840,8 @@ PostgresMain(int argc, char *argv[],
 	StringInfoData input_message;
 	sigjmp_buf	local_sigjmp_buf;
 	volatile bool send_ready_for_query = true;
-	bool		disable_idle_in_transaction_timeout = false;
+	bool		idle_in_transaction_timeout_enabled = false;
+	bool		idle_session_timeout_enabled = false;

 	/* Initialize startup process environment if necessary. */
 	if (!IsUnderPostmaster)
@@ -4228,6 +4243,8 @@ PostgresMain(int argc, char *argv[],
 		 * processing of batched messages, and because we don't want to report
 		 * uncommitted updates (that confuses autovacuum).  The notification
 		 * processor wants a call too, if we are not in a transaction block.
+		 *
+		 * Also, if an idle timeout is enabled, start the timer for that.
 		 */
 		if (send_ready_for_query)
 		{
@@ -4239,7 +4256,7 @@ PostgresMain(int argc, char *argv[],
 				/* Start the idle-in-transaction timer */
 				if (IdleInTransactionSessionTimeout > 0)
 				{
-					disable_idle_in_transaction_timeout = true;
+					idle_in_transaction_timeout_enabled = true;
 					enable_timeout_after(IDLE_IN_TRANSACTION_SESSION_TIMEOUT,
 										 IdleInTransactionSessionTimeout);
 				}
@@ -4252,7 +4269,7 @@ PostgresMain(int argc, char *argv[],
 				/* Start the idle-in-transaction timer */
 				if (IdleInTransactionSessionTimeout > 0)
 				{
-					disable_idle_in_transaction_timeout = true;
+					idle_in_transaction_timeout_enabled = true;
 					enable_timeout_after(IDLE_IN_TRANSACTION_SESSION_TIMEOUT,
 										 IdleInTransactionSessionTimeout);
 				}
@@ -4275,6 +4292,14 @@ PostgresMain(int argc, char *argv[],

 				set_ps_display("idle");
 				pgstat_report_activity(STATE_IDLE, NULL);
+
+				/* Start the idle-session timer */
+				if (IdleSessionTimeout > 0)
+				{
+					idle_session_timeout_enabled = true;
+					enable_timeout_after(IDLE_SESSION_TIMEOUT,
+										 IdleSessionTimeout);
+				}
 			}

 			/* Report any recently-changed GUC options */
@@ -4310,12 +4335,21 @@ PostgresMain(int argc, char *argv[],
 		DoingCommandRead = false;

 		/*
-		 * (5) turn off the idle-in-transaction timeout
+		 * (5) turn off the idle-in-transaction and idle-session timeouts, if
+		 * active.
+		 *
+		 * At most one of these two will be active, so there's no need to
+		 * worry about combining the timeout.c calls into one.
 		 */
-		if (disable_idle_in_transaction_timeout)
+		if (idle_in_transaction_timeout_enabled)
 		{
 			disable_timeout(IDLE_IN_TRANSACTION_SESSION_TIMEOUT, false);
-			disable_idle_in_transaction_timeout = false;
+			idle_in_transaction_timeout_enabled = false;
+		}
+		if (idle_session_timeout_enabled)
+		{
+			disable_timeout(IDLE_SESSION_TIMEOUT, false);
+			idle_session_timeout_enabled = false;
 		}

 		/*
diff --git a/src/backend/utils/errcodes.txt b/src/backend/utils/errcodes.txt
index 64ca2deec9..1d5a78e73d 100644
--- a/src/backend/utils/errcodes.txt
+++ b/src/backend/utils/errcodes.txt
@@ -109,6 +109,7 @@ Section: Class 08 - Connection Exception
 08004    E    ERRCODE_SQLSERVER_REJECTED_ESTABLISHMENT_OF_SQLCONNECTION      sqlserver_rejected_establishment_of_sqlconnection
 08007    E    ERRCODE_TRANSACTION_RESOLUTION_UNKNOWN                         transaction_resolution_unknown
 08P01    E    ERRCODE_PROTOCOL_VIOLATION                                     protocol_violation
+08P02    E    ERRCODE_IDLE_SESSION_TIMEOUT                                   idle_session_timeout

 Section: Class 09 - Triggered Action Exception

diff --git a/src/backend/utils/init/globals.c b/src/backend/utils/init/globals.c
index 3d5d6cc033..ea28769d6a 100644
--- a/src/backend/utils/init/globals.c
+++ b/src/backend/utils/init/globals.c
@@ -32,6 +32,7 @@ volatile sig_atomic_t QueryCancelPending = false;
 volatile sig_atomic_t ProcDiePending = false;
 volatile sig_atomic_t ClientConnectionLost = false;
 volatile sig_atomic_t IdleInTransactionSessionTimeoutPending = false;
+volatile sig_atomic_t IdleSessionTimeoutPending = false;
 volatile sig_atomic_t ProcSignalBarrierPending = false;
 volatile uint32 InterruptHoldoffCount = 0;
 volatile uint32 QueryCancelHoldoffCount = 0;
diff --git a/src/backend/utils/init/postinit.c b/src/backend/utils/init/postinit.c
index 59b3f4b135..e5965bc517 100644
--- a/src/backend/utils/init/postinit.c
+++ b/src/backend/utils/init/postinit.c
@@ -72,6 +72,7 @@ static void ShutdownPostgres(int code, Datum arg);
 static void StatementTimeoutHandler(void);
 static void LockTimeoutHandler(void);
 static void IdleInTransactionSessionTimeoutHandler(void);
+static void IdleSessionTimeoutHandler(void);
 static bool ThereIsAtLeastOneRole(void);
 static void process_startup_options(Port *port, bool am_superuser);
 static void process_settings(Oid databaseid, Oid roleid);
@@ -619,6 +620,7 @@ InitPostgres(const char *in_dbname, Oid dboid, const char *username,
 		RegisterTimeout(LOCK_TIMEOUT, LockTimeoutHandler);
 		RegisterTimeout(IDLE_IN_TRANSACTION_SESSION_TIMEOUT,
 						IdleInTransactionSessionTimeoutHandler);
+		RegisterTimeout(IDLE_SESSION_TIMEOUT, IdleSessionTimeoutHandler);
 	}

 	/*
@@ -1233,6 +1235,14 @@ IdleInTransactionSessionTimeoutHandler(void)
 	SetLatch(MyLatch);
 }

+static void
+IdleSessionTimeoutHandler(void)
+{
+	IdleSessionTimeoutPending = true;
+	InterruptPending = true;
+	SetLatch(MyLatch);
+}
+
 /*
  * Returns true if at least one role is defined in this database cluster.
  */
diff --git a/src/backend/utils/misc/guc.c b/src/backend/utils/misc/guc.c
index 1ccf7593ee..daf9c127cd 100644
--- a/src/backend/utils/misc/guc.c
+++ b/src/backend/utils/misc/guc.c
@@ -2509,7 +2509,7 @@ static struct config_int ConfigureNamesInt[] =

 	{
 		{"idle_in_transaction_session_timeout", PGC_USERSET, CLIENT_CONN_STATEMENT,
-			gettext_noop("Sets the maximum allowed duration of any idling transaction."),
+			gettext_noop("Sets the maximum allowed idle time between queries, when in a transaction."),
 			gettext_noop("A value of 0 turns off the timeout."),
 			GUC_UNIT_MS
 		},
@@ -2518,6 +2518,17 @@ static struct config_int ConfigureNamesInt[] =
 		NULL, NULL, NULL
 	},

+	{
+		{"idle_session_timeout", PGC_USERSET, CLIENT_CONN_STATEMENT,
+			gettext_noop("Sets the maximum allowed idle time between queries, when not in a transaction."),
+			gettext_noop("A value of 0 turns off the timeout."),
+			GUC_UNIT_MS
+		},
+		&IdleSessionTimeout,
+		0, 0, INT_MAX,
+		NULL, NULL, NULL
+	},
+
 	{
 		{"vacuum_freeze_min_age", PGC_USERSET, CLIENT_CONN_STATEMENT,
 			gettext_noop("Minimum age at which VACUUM should freeze a table row."),
diff --git a/src/backend/utils/misc/postgresql.conf.sample b/src/backend/utils/misc/postgresql.conf.sample
index 5298e18ecd..033aa335a0 100644
--- a/src/backend/utils/misc/postgresql.conf.sample
+++ b/src/backend/utils/misc/postgresql.conf.sample
@@ -663,6 +663,7 @@
 #statement_timeout = 0			# in milliseconds, 0 is disabled
 #lock_timeout = 0			# in milliseconds, 0 is disabled
 #idle_in_transaction_session_timeout = 0	# in milliseconds, 0 is disabled
+#idle_session_timeout = 0		# in milliseconds, 0 is disabled
 #vacuum_freeze_min_age = 50000000
 #vacuum_freeze_table_age = 150000000
 #vacuum_multixact_freeze_min_age = 5000000
diff --git a/src/include/miscadmin.h b/src/include/miscadmin.h
index 2c71db79c0..1bdc97e308 100644
--- a/src/include/miscadmin.h
+++ b/src/include/miscadmin.h
@@ -82,6 +82,7 @@ extern PGDLLIMPORT volatile sig_atomic_t InterruptPending;
 extern PGDLLIMPORT volatile sig_atomic_t QueryCancelPending;
 extern PGDLLIMPORT volatile sig_atomic_t ProcDiePending;
 extern PGDLLIMPORT volatile sig_atomic_t IdleInTransactionSessionTimeoutPending;
+extern PGDLLIMPORT volatile sig_atomic_t IdleSessionTimeoutPending;
 extern PGDLLIMPORT volatile sig_atomic_t ProcSignalBarrierPending;

 extern PGDLLIMPORT volatile sig_atomic_t ClientConnectionLost;
diff --git a/src/include/storage/proc.h b/src/include/storage/proc.h
index 989c5849d4..0786fcf103 100644
--- a/src/include/storage/proc.h
+++ b/src/include/storage/proc.h
@@ -378,6 +378,7 @@ extern PGDLLIMPORT int DeadlockTimeout;
 extern PGDLLIMPORT int StatementTimeout;
 extern PGDLLIMPORT int LockTimeout;
 extern PGDLLIMPORT int IdleInTransactionSessionTimeout;
+extern PGDLLIMPORT int IdleSessionTimeout;
 extern bool log_lock_waits;


diff --git a/src/include/utils/timeout.h b/src/include/utils/timeout.h
index 8adb4e14ca..ecb2a366a5 100644
--- a/src/include/utils/timeout.h
+++ b/src/include/utils/timeout.h
@@ -31,10 +31,11 @@ typedef enum TimeoutId
 	STANDBY_TIMEOUT,
 	STANDBY_LOCK_TIMEOUT,
 	IDLE_IN_TRANSACTION_SESSION_TIMEOUT,
+	IDLE_SESSION_TIMEOUT,
 	/* First user-definable timeout reason */
 	USER_TIMEOUT,
 	/* Maximum number of timeout reasons */
-	MAX_TIMEOUTS = 16
+	MAX_TIMEOUTS = USER_TIMEOUT + 10
 } TimeoutId;

 /* callback function signature */
```

这个功能虽然比较小众，但是用来练手是比较好的一个实践过程，通过这个功能我更加熟悉了 PostgreSQL 社区的工作流程。社区中的人都比较包容，对于一些比较基础的问题也能耐心的解释，对待事物很严谨，即使是文档也是如此。最后附上整个功能的讨论过程。

## 链接

[1] https://postgr.es/m/763A0689-F189-459E-946F-F0EC4458980B@hotmail.com
