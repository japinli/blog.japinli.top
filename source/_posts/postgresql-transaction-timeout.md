---
title: "PostgreSQL 事务超时"
date: 2024-02-18 15:22:24 +0800
categories: 数据库
tags:
  - PostgreSQL
  - PG17
---

继空闲会话超时之后，PostgreSQL 在 17 中又引入了事务超时 [`transaction_timeout`][]。

{% asset_img transaction_timeout-commit-message.jpg %}

<!--more-->

## 使用

我们可以通过设置 `transaction_timeout` 参数来指定事务的超时时间，这样可以避免长事务导致的一系列问题。首先，我们看看该参数的说明。

```psql
postgres=# SELECT * FROM pg_settings WHERE name = 'transaction_timeout' \gx
-[ RECORD 1 ]---+--------------------------------------------------------------------------------------------
name            | transaction_timeout
setting         | 0
unit            | ms
category        | Client Connection Defaults / Statement Behavior
short_desc      | Sets the maximum allowed time in a transaction with a session (not a prepared transaction).
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

接着我们连接数据库并尝试设置 `transaction_timeout` 的值。

```psql
postgres=# SET transaction_timeout to '10s';
SET
postgres=# BEGIN;
BEGIN
postgres=*# SELECT pg_sleep(20);
FATAL:  terminating connection due to transaction timeout
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
The connection to the server was lost. Attempting reset: Succeeded.
postgres=# \! cat log | grep timeout
2024-02-18 15:46:37.018 CST [87421] FATAL:  terminating connection due to transaction timeout
```

从上面可以看到 `pg_sleep(20)` 在睡眠的过程中，事务由于 `transaction_timeout` 超时而终止了。PostgreSQL 中除了 `transaction_timeout` 之外还包含 `statement_timeout` 和 `idle_in_transaction_timeout`，当启用事务超时并且 `transaction_timeout` 的值小于 `statement_timeout` 或 `idle_in_transaction_timeout` 时，后面两个参数实际上不会生效。

通常是不建议全局配置该参数，您可以在会话级别进行配置。

**注意：** `prepared transaction` 不受 `transaction_timeout` 超时参数的限制。

## 参考

[1] https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=51efe38cb92f4b15b68811bcce9ab878fbc71ea5
[2] https://www.postgresql.org/docs/devel/runtime-config-client.html


[`transaction_timeout`]: https://www.postgresql.org/docs/devel/runtime-config-client.html#GUC-TRANSACTION-TIMEOUT

<div class="just-for-fun">
笑林广记 - 不默

各行酒令要默饮。
席中有撒屁者，令官曰：“不默，罚一杯。”
其人曰：“是屁响。”
令官曰：“又不默，再罚一杯。” 举座为之大笑。
令官曰：“通座皆不默，各罚一杯。”
</div>
