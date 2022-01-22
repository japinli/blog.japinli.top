---
title: "PostgreSQL 15 特性 - 基础备份存储位置"
date: 2022-01-22 08:41:33
categories: 数据库
tags:
  - PostgreSQL
  - PG15
  - pg_basebackup
---

最近 Robert Haas 提交了一个关于 pg_basebackup 指定备份存储位置的功能，详细信息如下：

	commit 3500ccc39b0dadd1068a03938e4b8ff562587ccc
	Author: Robert Haas <rhaas@postgresql.org>
	Date:   Tue Nov 16 15:20:50 2021 -0500

	    Support base backup targets.

	    pg_basebackup now has a --target=TARGET[:DETAIL] option. If specfied,
	    it is sent to the server as the value of the TARGET option to the
	    BASE_BACKUP command. If DETAIL is included, it is sent as the value of
	    the new TARGET_DETAIL option to the BASE_BACKUP command.  If the
	    target is anything other than 'client', pg_basebackup assumes that it
	    will now be the server's job to write the backup in a location somehow
	    defined by the target, and that it therefore needs to write nothing
	    locally. However, the server will still send messages to the client
	    for progress reporting purposes.

	    On the server side, we now support two additional types of backup
	    targets.  There is a 'blackhole' target, which just throws away the
	    backup data without doing anything at all with it. Naturally, this
	    should only be used for testing and debugging purposes, since you will
	    not actually have a backup when it finishes running. More usefully,
	    there is also a 'server' target, so you can now use something like
	    'pg_basebackup -Xnone -t server:/SOME/PATH' to write a backup to some
	    location on the server. We can extend this to more types of targets
	    in the future, and might even want to create an extensibility
	    mechanism for adding new target types.

	    Since WAL fetching is handled with separate client-side logic, it's
	    not part of this mechanism; thus, backups with non-default targets
	    must use -Xnone or -Xfetch.

	    Patch by me, with a bug fix by Jeevan Ladhe.  The patch set of which
	    this is a part has also had review and/or testing from Tushar Ahuja,
	    Suraj Kharage, Dipesh Pandit, and Mark Dilger.

	    Discussion: http://postgr.es/m/CA+TgmoaYZbz0=Yk797aOJwkGJC-LK3iXn+wzzMx7KdwNpZhS5g@mail.gmail.com

<!--more-->

## 使用说明

该提交为 pg_basebackup 命令引入了一个新的选项 `--target=target, -t target`。该选择可以指定备份的存储的位置，可能的值为：

* `client` - 备份到运行 pg_basebackup 命令所在的机器，这是默认选项。
* `server` - 备份到运行数据库服务所在的机器，该选项还需给出记录的备份目录, 即 `server:/some/path`，在数据库服务器上备份需要超级用户权限。
* `blackhole` - 备份文件将被丢弃并不会被存储，这仅用于测试目的。

**注意：**由于 WAL 日志流是在 pg_basebackup 端，而不是数据库服务端实现的，因此这个选项不能和 `-Xstream` 一起使用。`-Xstream` 是默认选项，因此当使用该选项时，您需要指定 `-Xfetch` 或 `-Xnone` 选项。

## 示例

首先简要介绍一下环境，如下所示：

| 名称       | IP           | 类型          |
|------------|--------------|---------------|
| 数据库主机 | 172.16.105.2 | 数据库服务器  |
| 备份主机   | 172.16.105.3 | pg_basebackup |


关于数据库的远程访问以及流复制的相关配置就不再细说了，直接进入主题。

### 服务器端备份

我们首先来验证一下 `server` 模式的备份。首先在备份主机上执行 pg_basebackup 命令，如下所示：

```shell
$ pg_basebackup -v -h 172.16.105.2 -t server:/tmp/pgdata01 -d "dbname=postgres" -Xfetch
Password:
pg_basebackup: initiating base backup, waiting for checkpoint to complete
pg_basebackup: checkpoint completed
pg_basebackup: write-ahead log start point: 0/6000028 on timeline 1
pg_basebackup: write-ahead log end point: 0/6000100
pg_basebackup: base backup completed
```

接着我们在数据库主机上查看是否创建相关的备份文件。

```shell
$ cd /tmp/pgdata01/
$ ls
backup_manifest  base.tar
$ tar xf base.tar
$ ls
PG_VERSION        pg_commit_ts   pg_notify     pg_subtrans           postgresql.conf
backup_label.old  pg_dynshmem    pg_replslot   pg_tblspc             postmaster.opts
backup_manifest   pg_hba.conf    pg_serial     pg_twophase           tablespace_map.old
base              pg_ident.conf  pg_snapshots  pg_wal
global            pg_logical     pg_stat       pg_xact
log_backup        pg_multixact   pg_stat_tmp   postgresql.auto.conf
$ pg_ctl -l log_backup start
waiting for server to start.... done
server started
```

一切正常。当我们尝试用 `-Xstream` 来进行服务器端备份，可以看到如文档所说，不支持这种方式。

```shell
$ pg_basebackup -v -h 172.16.105.2 -t server:/tmp/pgdata02 -d "dbname=postgres"
pg_basebackup: error: WAL cannot be streamed when a backup target is specified
Try "pg_basebackup --help" for more information.
```

### 客户端备份

接着我们尝试客户端备份，在备份主机上执行 pg_basebackup 命令进行备份，随后在该主机上查看备份结果。如下所示：

```shell
$ pg_basebackup -v -h 172.16.105.2 -t client -D /tmp/pgdata01 -d "dbname=postgres" -Xfetch
Password:
pg_basebackup: initiating base backup, waiting for checkpoint to complete
pg_basebackup: checkpoint completed
pg_basebackup: write-ahead log start point: 0/8000028 on timeline 1
pg_basebackup: write-ahead log end point: 0/8000100
pg_basebackup: syncing data to disk ...
pg_basebackup: renaming backup_manifest.tmp to backup_manifest
pg_basebackup: base backup completed
$ ls /tmp/pgdata01/
PG_VERSION       global        pg_ident.conf  pg_replslot   pg_stat_tmp  pg_wal
backup_label     pg_commit_ts  pg_logical     pg_serial     pg_subtrans  pg_xact
backup_manifest  pg_dynshmem   pg_multixact   pg_snapshots  pg_tblspc    postgresql.auto.conf
base             pg_hba.conf   pg_notify      pg_stat       pg_twophase  postgresql.conf
```

**这里需要注意的是，客户端备份的结果是目录结构（可以通过 `-F format` 或 `--format=format` 选项来进行指定），而服务端备份的结果是压缩文件（服务端备份不能和 `-F format` 或 `--format=format` 选项一起使用）。**

```shell
$ pg_basebackup -v -h 172.16.105.2 -t server:/tmp/pgdata02 -d "dbname=postgres" -Xfetch -Fp
pg_basebackup: error: cannot specify both format and backup target
Try "pg_basebackup --help" for more information.
```

客户端备份与 `-F format` 选项结合使用。

```shell
$ pg_basebackup -v -h 172.16.105.2 -t client -D /tmp/pgdata02 -d "dbname=postgres" -Xfetch -Ft
Password:
pg_basebackup: initiating base backup, waiting for checkpoint to complete
pg_basebackup: checkpoint completed
pg_basebackup: write-ahead log start point: 0/A000028 on timeline 1
pg_basebackup: write-ahead log end point: 0/A000100
pg_basebackup: syncing data to disk ...
pg_basebackup: renaming backup_manifest.tmp to backup_manifest
pg_basebackup: base backup completed
$ ls /tmp/pgdata02/
backup_manifest  base.tar
```

### 黑洞备份

顾名思义，这种备份方式就好比数据掉进了黑洞，这种备份方式仅用于测试的目的。

```shell
$ pg_basebackup -v -h 172.16.105.2 -t blackhole -d "dbname=postgres" -Xfetch
Password:
pg_basebackup: initiating base backup, waiting for checkpoint to complete
pg_basebackup: checkpoint completed
pg_basebackup: write-ahead log start point: 0/C000028 on timeline 1
pg_basebackup: write-ahead log end point: 0/C000100
pg_basebackup: base backup completed
```

## 总结

pg_basebackup 新增的备份功能在使用时有如下限制的：

* 不能与 `-Xstream` 选项结合使用；
* 不能与 `-F format` 选项结合使用；
* 使用 `-t client` 需要结合 `-D /some/path` 给出数据存储目录。

此外，在 PostgreSQL 15 版本中对 pg_basebackup 的压缩选项也做了部分修改，支持指定压缩算法的压缩级别，扩展了原有的 `-Z level` 和 `--compress=level` 选项，`-Z method[:level]` 和 `--compress=method[:level]`。

* `-z/gizp` 是 `--compress=gzip` 的同义词。
* `--compress=NUM` 有如下含义：
  - 当 `NUM = 0` 时，等同于 `--compress=none`。
  - 当 `NUM > 0` 时，等同于 `--compress=gzip:NUM`。

## 参考

[1] https://postgresql.org/docs/devel/app-pgbasebackup.html
[2] https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=3500ccc39b0dadd1068a03938e4b8ff562587ccc
[3] https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=5c649fe153367cdab278738ee4aebbfd158e0546

<div class="just-for-fun">
笑林广记 - 纳粟诗

赠纳粟诗曰：“革车（言三百两）买得截然高（言大也），周子窗前满腹包（言草也）。有朝若遇高曾祖（言考也），焕乎其有没分毫（言文章）。”
</div>
