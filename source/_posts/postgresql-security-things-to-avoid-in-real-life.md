---
title: "【译】PostgreSQL 安全：现实生活中需要避免的事情"
date: 2021-08-08 08:20:32 +0800
category: 数据库
tags:
  - PostgreSQL
  - 翻译
---

强化 PostgreSQL 变得越来越重要。如今，安全是王道，人们想知道如何确保 PostgreSQL 的安全。我们中的一些人可能还记得近年来发生在 [MongoDB 身上的事情][1]，我们当然希望在 PostgreSQL 世界中避免类似的安全问题。MongoDB 的遭遇实际上是令人震惊的：数以千计的数据库因为糟糕的默认安全设置而被勒索--这绝对是一场噩梦，不仅大大损害了 MongoDB 的声誉，也损害了整个行业的声誉。PostgreSQL 人员尽其所能避免在我们的生态系统中重复出现这种情况。

当有人在谈论您的公司时，标签 `#ransomware` （勒索软件）并不是您想要看到的。为了避免一些最常见的问题，我们编制了一个 “PostgreSQL 最佳安全问题”，它可以作为改进设置的 12 个步骤的指南。

## 1. 避免宽松的 `listen_addresses` 设置

PostgreSQL 是作为一个服务器进程运行的，人们想要连接到该数据库。问题是：这些连接是从哪里来的？在 `postgresql.conf` 中可以找到 `listen_addresses` 设置，它控制着这些绑定地址。

换句话说：如果 `listen_addresses` 被设置为 `'*'`，PostgreSQL 将监听所有的网络设备，考虑这些连接并进入下一个阶段，即评估 `pg_hba.conf` 的内容。在所有设备上监听是一个问题，因为一个坏的行为者可以很容易地向您发送身份认证请求的垃圾邮件--那么灾难就只在一个 `pg_hba.conf` 条目之外。

建议：

* 如果只需要本地连接：
  设置 `listen_addresses = 'localhost'`
* 如果需要远程连接：
  设置 `listen_addresses = 'localhost, <IP of network device>'`

如果您根本不监听，您肯定会更安全。如果您已经限制网络访问，PostgreSQL 甚至不必拒绝您的连接。

## 2. 在 `pg_hba.conf` 中使用 `trust`

在处理了 `listen_addresses (= bind addresses)` 之后，PostgreSQL 将处理 `pg_hba.conf` 以确定是否允许连接。出现的主要问题是：在谈论 `pg_hba.conf` 的时候，有什么可能出错？好吧，有一些事情是值得一提的。

我们经常看到的是，人们使用 `trust` 来确保人们无需密码即可连接到 PostgreSQL。如果您正在强化 PostgreSQL，那么使用 `trust` 基本上是最糟糕的事情。对于本地连接，`peer` 可能是一个有效的选择—— `trust` 当然不是。

建议：

* 如果您正在强化 PostgreSQL，请不要使用 `trust`（尤其不要用于远程连接）。
* 改用 `scram-sha-256` 和 `SSL`。
* 如果可能的话，尽量避免允许来自任何地方的连接的条目（网络掩码 `0.0.0.0/0`）。相反，将访问限制在那些真正需要访问的主机和子网中。
* 不要创建允许连接到所有数据库或所有用户的 `pg_hba.conf` 条目。要有针对性。
* 为文件中的每一行添加文档，以便您知道为什么需要该权限，谁要求的，以及在需要时与谁联系。否则，您几乎没有机会清理和删除不再需要的条目。此外，如果需要修改密码，您知道该与谁联系。

## 3. 摆脱 PostgreSQL 中的 `md5` 密码

许多年来，`md5` 是 PostgreSQL 中进行密码验证的首选方法。然而，`md5` 的时代早已过去。你甚至可以从网上下载包含最常用的哈希值的现成文件，破解密码的速度更快。

换句话说：忘记 `md5`，转而使用更强的哈希算法。如果您想知道如何从 `md5` 迁移到 `scram-sha-256`，请确保您[查看我们的帖子“在 PostgreSQL 中从 MD5 到 scram-sha-256”][2]。

建议：

* 使用 `scram-sha-256` 替代 `md5`。

## 4. 处理模式和数据库的 `PUBLIC` 权限


在 PostgreSQL 中，有一个东西叫做 `PUBLIC`。它基本上相当于数据库中的 “UNIX世界”。正如您将看到的，它可能会引起一些问题--然而，这些问题是可以避免的。

以下是通常发生的情况：

```
postgres=# CREATE USER joe;
CREATE ROLE
postgres=# \c postgres joe
You are now connected to database "postgres" as user "joe".
postgres=> SELECT current_user;
current_user
--------------
joe
(1 row)
```

我们已经创建了一个用户，并以 `joe` 的身份登录。我们在这里看到的是，`joe` 不被允许创建一个新的数据库，这正是我们所期望的。但是：`joe` 被允许连接到其他一些我们甚至至今都没有听说过的数据库。幸运的是，`joe` 不被允许读取这个数据库中的任何对象。

```
postgres=> CREATE DATABASE joedb;
ERROR: permission denied to create database
postgres=> \c demo
You are now connected to database "demo" as user "joe".
demo=> SELECT * FROM t_demo;
ERROR: permission denied for table t_demo
```

但是，默认情况下允许 `joe` 创建表（`public` 模式），这当然不是一个好主意：

```
demo=> CREATE TABLE bad_idea (id int);
CREATE TABLE
```

因此，我们确定了两个关键问题：

* 允许 `joe` 连接到其他数据库
* `joe` 被允许向 `public` 模式发送垃圾（译者注：实际上就是创建一些对象，例如表）

这比乍看之下更糟糕。经验表明，多年来在 PostgreSQL 中发现的大多数特权升级攻击载体都是通过在数据库中创建恶意对象来实现的。

所以，我们必须修复它：

```
demo=# REVOKE ALL ON DATABASE demo FROM public;
REVOKE
demo=# REVOKE ALL ON SCHEMA public FROM public;
REVOKE
```

现在我们已经做到了，我们可以以 `joe` 的身份重新连接到演示数据库。在 psql 中，我们可以使用 `\c` 命令来做这件事。如果你使用的是图形用户界面，只需改变你的数据库连接并以用户 `joe` 的身份登录：

```
demo=# \c demo joe
FATAL: permission denied for database "demo"
DETAIL: User does not have CONNECT privilege.
Previous connection kept
```

首先，我们已经撤销了 `PUBLIC` 的权限，以确保数据库连接不再可行。然后我们修复 `public` 模式固定的权限。如您所见，连接不再可能。

建议：

* 从您的数据库权限中删除 `PUBLIC` 权限
* 从您的 `public` 模式中移除 `PUBLIC` 权限

从所有不需要临时权限的用户处撤销数据库上的临时权限也是一个好主意。某些权限提升攻击也适用于临时对象。此外，确保正确测试设置，以确保没有泄漏。

## 5. 避免 `ALTER USER ... SET PASSWORD ...`

在 PostgreSQL 中更改密码很容易。大多数人使用 `ALTER USER ... SET PASSWORD` 来做到这一点。但是，有一个问题：这条 SQL 语句最终会以 PLAIN 文本形式出现在您的数据库日志中，这当然是一个主要问题。

建议：

* 使用受信任的 PostgreSQL 客户端设施更改密码，而不是 `ALERT ROLE`。例如，psql具有 `\password`，pgAdmin 具有“更改密码”对话框。

这项建议似乎很荒谬。然而，这背后有一些道理。要更改密码，可以通过协议支持绕过日志中的纯文本密码问题。通过直观地执行操作，而不是通过简单的 SQL，大多数 GUI 将为您解决问题。

__提示：__ [CYBERTEC PostgreSQL 企业版 (PGEE)][3] 甚至明确禁止 `ALTER USER ... SET PASSWORD` 以避免日志流中的风险密码。

## 6. 使用 `ALTER DEFAULT PRIVILEGES`

假设您正在运行一个应用程序。您的数据库包含 200 个表。权限是为无数用户完美设置的。假设我们想要更新这个应用程序，以便执行 DDL 来进行更改。但是如果有人犯了错误怎么办？如果权限设置不正确怎么办？小问题将开始积累。

此问题的解决方案是 `ALTER DEFAULT PRIVILEGES`：

```
demo=# \h ALTER DEFAULT
Command: ALTER DEFAULT PRIVILEGES
Description: define default access privileges
Syntax:
ALTER DEFAULT PRIVILEGES
[ FOR { ROLE | USER } target_role [, ...] ]
[ IN SCHEMA schema_name [, ...] ]
abbreviated_grant_or_revoke

where abbreviated_grant_or_revoke is one of:

GRANT { { SELECT | INSERT | UPDATE | DELETE |
TRUNCATE | REFERENCES | TRIGGER }
[, ...] | ALL [ PRIVILEGES ] }
ON TABLES
TO { [ GROUP ] role_name | PUBLIC } [, ...]
[ WITH GRANT OPTION ]
…
```

其思想是在创建对象之后不久就定义默认权限。无论何时创建数据库对象，默认权限都会自动生效并为您解决问题。在这种情况下，PostgreSQL 将通过自动设置新对象的权限，大大简化强化过程。

__译者注：__ 这里的原文是 `The idea is to define default permissions long before objects are created.`，可能翻译的不是很准确。

## 7. 使用 SSL

SSL 是 PostgreSQL 安全领域中最重要的主题之一。如果您想强化 PostgreSQL 数据库，则无法绕过 SSL。

PostgreSQL 提供各种级别的 SSL，并允许您加密客户端和服务器之间的连接。通常，我们建议至少使用 [TLS][4] 1.2 以确保足够高的安全级别。

如果您想了解有关 SSL 的更多信息，并想知道如何设置它，请[查看我们的页面][5]。

## 8. 安全地编写 `SECURITY DEFINER` 函数

存储过程和服务器端功能通常是一个主要的安全问题。 PostgreSQL 中有两种执行函数的方式：

* 以“你是谁”的身份执行函数
* 以代码作者身份执行函数

默认情况下，函数以当前用户身份执行。换句话说：如果您当前是 `joe` 用户，该函数将作为 `joe` 运行。但是，有时以函数的作者身份运行代码，从而使用不同的安全设置会很有用。这样，您可以让具有低权限的用户以受控方式执行某些需要提升权限的操作。这样做的方法是在创建函数时使用 `SECURITY DEFINER` 选项。

但是强大的工具也很危险，因此您必须仔细定义这些功能。有关详细信息，请阅读我们关于 [SECURITY DEFINER 函数][6]的文章。

## 9. 避免数据库函数中的 SQL 注入

SQL 注入不仅是应用程序（客户端）端的问题，它还会影响数据库中的过程代码。如果您想避免 SQL 注入，我们建议您继续阅读并了解更多信息。

考虑这个愚蠢的函数：

```
CREATE FUNCTION tally(table_name text) RETURNS bigint
LANGUAGE plpgsql AS
$$DECLARE
result bigint;
BEGIN
EXECUTE 'SELECT count(*) FROM ' || table_name
INTO result;
RETURN result;
END;$$;
```

现在，任何可以控制提供给函数的参数的攻击者都可以发起拒绝服务攻击：

```sql
SELECT tally('generate_series(1, 100000000000000000000)');
```

或者他们可以找出您帐户上的金额：

```sql
SELECT tally('generate_series(1, 1000000)
UNION
SELECT amount::bigint FROM account WHERE name = ''loser''');
```

使用通常的安全预防措施：

* 仅在必要时使用动态 SQL。
* 仅在必要时将字符串数据类型用于参数。
* 始终使用 `format()` 来构造 SQL 查询字符串。

## 10. 尽可能限制超级用户访问

如果对安全关键系统具有管理访问权限的人数尽可能少，那总是好的。您想要走多远取决于您的安全需求：

* 加固数据库机器，以便除数据库管理员之外的任何人都无法获得对机器的 shell 访问权限。任何作为 PostgreSQL 操作系统用户具有 shell 访问权限的人都可以完全控制数据库。
* 为管理员使用个性化的超级用户帐户，以便您可以在需要时快速撤销对管理员的访问权限。
* 仅在真正需要的地方使用超级用户。例如，复制连接或备份不需要超级用户。
* 使用 `pg_hba.conf` 中的超级用户帐户限制访问。理想情况下，只允许本地连接。如果您不想这样做，请限制对管理员个人系统的访问。
* 对于非常高的安全要求，请确保没有人知道超级用户密码，并将其放在至少只能由两个人打开的保险箱中。每次使用后更改密码。


一般来说，使用超级用户是危险的。

建议：

* 永远不要以超级用户身份运行应用程序
* 尽可能限制超级用户

## 11. 定期更新您的 PostgreSQL 数据库

最后，定期更新 PostgreSQL 很重要。请记住，大多数次要版本更新（例如 13.0 -> 13.2 等）都带有与安全相关的更新，这些更新对于减少系统的攻击面至关重要。

PostgreSQL 会定期提供安全更新，我们建议您尽快应用它们。

## 12. 加密整个服务器：PostgreSQL TDE

到目前为止，您已经学习了如何加密客户端和服务器之间的连接。但是，有时需要对包括存储在内的整个服务器进行加密。 PostgreSQL TDE 正是这样做的：

{% asset_img tde-architecture.png %}

要了解更多信息，请查看我们关于 [PostgreSQL TDE][7] 的网站。我们提供完全加密的堆栈来帮助您实现最大的 PostgreSQL 安全性。TDE 可免费使用（开源）。

## 写在最后

物化视图是包括 PostgreSQL 在内的大多数数据库的重要特性。它们可以帮助加速大型计算——或者至少可以缓存它们。

如果您想确保[您的物化视图是最新的][8]，如果您现在想阅读更多关于 PostgreSQL 的信息，请查看我们关于 [pg_timetable 的博客][9]，该博客向您展示了如何在 PostgreSQL 中安排作业。为什么 [pg_timetable][10] 如此有用？我们的调度程序确保相同的作业不能重叠，但如果相同的作业已经在运行，就不再执行。当您运行长作业时，这一点非常重要——特别是如果您想要使用物化视图的话。

## 译者注

* 本文本文翻译自 Hans-Jürgen Schönig 的 [POSTGRESQL SECURITY: THINGS TO AVOID IN REAL LIFE][11]。

<div class="just-for-fun">
笑林广记 - 糊涂

一青盲人涉讼，自诉眼瞎。
官曰：“你明明一双清白眼，如何诈瞎。”
答曰：“老爷看小人是清白的，小人看老爷却是糊涂得紧。”
</div>

[1]: https://www.zdnet.com/article/hacker-ransoms-23k-mongodb-databases-and-threatens-to-contact-gdpr-authorities/
[2]: https://www.cybertec-postgresql.com/en/from-md5-to-scram-sha-256-in-postgresql/
[3]: https://www.cybertec-postgresql.com/en/products/cybertec-postgresql-enterprise-edition/
[4]: https://www.cybertec-postgresql.com/en/tls-demystifying-communication-encryption-in-postgresql/
[5]: https://www.cybertec-postgresql.com/en/setting-up-ssl-authentication-for-postgresql/
[6]: https://www.cybertec-postgresql.com/en/abusing-security-definer-functions/
[7]: https://www.cybertec-postgresql.com/en/products/postgresql-transparent-data-encryption/
[8]: https://www.cybertec-postgresql.com/en/pg_timetable-asynchronous-chain-execution/
[9]: https://www.cybertec-postgresql.com/en/?s=pg_timetable
[10]: https://www.cybertec-postgresql.com/en/products/pg_timetable/
[11]: https://www.cybertec-postgresql.com/en/postgresql-security-things-to-avoid-in-real-life/
