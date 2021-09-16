---
title: "PostgreSQL 优化 setitimer 系统调用"
date: 2020-08-31 22:46:59 +0800
category: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

当我们在使用 PostgreSQL 数据库并启用 `statement_timeout` 时，可以看到 `setitimer()` 函数的调用次数明显偏多。本文分析了 [Thomas Munro 给出的关于 `setitimer()` 函数的优化](https://www.postgresql.org/message-id/CA%2BhUKG%2Bo6pbuHBJSGnud%3DTadsuXySWA7CCcPgCt2QE9F6_4iHQ%40mail.gmail.com)。

<!-- more -->

## 基准测试

为了方便分析，我们首先需要有一个基本的基准测试。我们使用下面的命令初始化数据库：

```
$ initdb -D pgdata
$ pg_ctl -l log -D pgdata start
$ createdb testdb
$ pgbench -i -s 10 testdb
```

接着修改配置 `statement_timeout`，将其设置为 `10s`，可以使用如下命令：

```
$ psql postgres -c "ALTER SYSTEM SET statement_timeout TO '10s'"
$ pg_ctl -l log -D pgdata start
```

接着我们使用 `pgbench -T60 -Mprepared -S testdb` 来进行测试，我们在另一个终端中通过 `strace` 来分析系统调用，可以得到如下结果：

```
$ strace -c -p 31561
strace: Process 31561 attached
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 41.11    0.334739           1    424545           sendto
 26.54    0.216100           1    424449           recvfrom
 24.33    0.198094           0    424448           setitimer
  8.02    0.065268           1     71339           pread64
  0.00    0.000000           0         1           epoll_ctl
------ ----------- ----------- --------- --------- ----------------
100.00    0.814201               1344782           total
```

从结果可以看到，整个测试过程中 `setitimer()` 系统调用调用了 424448 次。

## 补丁测试

接下来，我们将 patch 应用到 PostgreSQL 中，重新编译，并进行测试，其结果如下：

```
$ strace -c -p 1375
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 54.16    0.351467           1    520065           sendto
 35.17    0.228279           0    519963           recvfrom
 10.67    0.069251           1     88036           pread64
  0.00    0.000001           0         6           rt_sigreturn
  0.00    0.000000           0         5           setitimer
  0.00    0.000000           0         1           epoll_ctl
------ ----------- ----------- --------- --------- ----------------
100.00    0.648998               1128076           total
```

从结果可以看到，此时的 `setitimer()` 系统调用仅调用了 5 次，远比之前的次数低。从最终的统计结果来看，应用了补丁程序的 PostgreSQL 整个测试过程中的系统调用比原有的系统调用降低了约 16%。

## 实现

这个补丁程序的思路其实非常简单，实现起来也不复杂，整个 diff 文件不足 100 行。

``` diff
diff --git a/src/backend/utils/misc/timeout.c b/src/backend/utils/misc/timeout.c
index f1c9518b0c..b5027815db 100644
--- a/src/backend/utils/misc/timeout.c
+++ b/src/backend/utils/misc/timeout.c
@@ -51,6 +51,13 @@ static bool all_timeouts_initialized = false;
 static volatile int num_active_timeouts = 0;
 static timeout_params *volatile active_timeouts[MAX_TIMEOUTS];

+/*
+ * State used to avoid installing a new timer interrupt when the previous one
+ * hasn't fired yet, but isn't too late.
+ */
+static TimestampTz sigalrm_due_at = PG_INT64_MAX;
+static volatile sig_atomic_t sigalrm_delivered = false;
+
 /*
  * Flag controlling whether the signal handler is allowed to do anything.
  * We leave this "false" when we're not expecting interrupts, just in case.
@@ -195,12 +202,13 @@ schedule_alarm(TimestampTz now)
 		struct itimerval timeval;
 		long		secs;
 		int			usecs;
+		TimestampTz	nearest_timeout;

 		MemSet(&timeval, 0, sizeof(struct itimerval));

 		/* Get the time remaining till the nearest pending timeout */
-		TimestampDifference(now, active_timeouts[0]->fin_time,
-							&secs, &usecs);
+		nearest_timeout = active_timeouts[0]->fin_time;
+		TimestampDifference(now, nearest_timeout, &secs, &usecs);

 		/*
 		 * It's possible that the difference is less than a microsecond;
@@ -244,9 +252,18 @@ schedule_alarm(TimestampTz now)
 		 */
 		enable_alarm();

+		/*
+		 * Try to avoid having to set the interval timer, if we already know
+		 * that there is an undelivered signal due at the same time or sooner.
+		 */
+		if (nearest_timeout >= sigalrm_due_at && !sigalrm_delivered)
+			return;
+
 		/* Set the alarm timer */
 		if (setitimer(ITIMER_REAL, &timeval, NULL) != 0)
 			elog(FATAL, "could not enable SIGALRM timer: %m");
+		sigalrm_due_at = nearest_timeout;
+		sigalrm_delivered = false;
 	}
 }

@@ -266,6 +283,8 @@ handle_sig_alarm(SIGNAL_ARGS)
 {
 	int			save_errno = errno;

+	sigalrm_delivered = true;
+
 	/*
 	 * Bump the holdoff counter, to make sure nothing we call will process
 	 * interrupts directly. No timeout handler should do that, but these
@@ -591,8 +610,9 @@ disable_timeouts(const DisableTimeoutParams *timeouts, int count)
 }

 /*
- * Disable SIGALRM and remove all timeouts from the active list,
- * and optionally reset their timeout indicators.
+ * Remove all timeouts from the active list, and optionally reset their timeout
+ * indicators.  Leave any existing itimer installed, because it may allow us to
+ * avoid having to set it again soon.
  */
 void
 disable_all_timeouts(bool keep_indicators)
@@ -601,20 +621,6 @@ disable_all_timeouts(bool keep_indicators)

 	disable_alarm();

-	/*
-	 * Only bother to reset the timer if we think it's active.  We could just
-	 * let the interrupt happen anyway, but it's probably a bit cheaper to do
-	 * setitimer() than to let the useless interrupt happen.
-	 */
-	if (num_active_timeouts > 0)
-	{
-		struct itimerval timeval;
-
-		MemSet(&timeval, 0, sizeof(struct itimerval));
-		if (setitimer(ITIMER_REAL, &timeval, NULL) != 0)
-			elog(FATAL, "could not disable SIGALRM timer: %m");
-	}
-
 	num_active_timeouts = 0;

 	for (i = 0; i < MAX_TIMEOUTS; i++)
```

其基本思想是通过 alarm 来取代频繁地调用 `setitimer()` 函数，而不是针对每个 timeout 都去调用 `setitimer()` 函数，这真的是将性能挖掘到了极限啊！

变量 `sigalrm_due_at` 记录了最近一个定时器的到期时间，`sigalrm_delivered` 则记录是否已经触发了 sigalrm 信号。当最近的定时器的超时时间大于或等于 `sigalrm_due_at` 并且不存在没有交付的定时器时，它将不会对其调用 `setitimer()` 来设置定时器。

## 更新

* __2020-11-21__ - 最近该功能在被 Review 的时候发现一个问题，由于我们仅设置了最近的一个 timeout，那么当 `handle_sig_alarm()` 被中断时，可能出现后续的 timeout 无法正常工作，因此我们需要在故障恢复的时候重新调用 `setitimer()` 函数设置 timeout，[详细实现](https://www.postgresql.org/message-id/2B9BB40C-DDEA-4CDB-B37E-C2738E739416%40hotmail.com)。
