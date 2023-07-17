---
title: "PostgreSQL 表空间备份"
date: 2023-06-20 17:58:51
categories: 数据库
tags:
  - PostgreSQL
  - pg_basebackup
  - pg_probackup
---

本文简要记录一下 PostgreSQL 中关于表空间的备份，主要涉及到了 `pg_basebackup` 和 `pg_probackup` 两种备份方式。

<!--more-->

## 环境介绍

下表是本次实验的基本环境，每个节点都安装了 PostgreSQL 15 及 `pg_probackup` 2.5.12。

| IP           | 说明       |
|--------------|------------|
| 10.9.10.106  | 数据库节点 |
| 10.9.10.109  | 备份节点   |

## 准备工作

首先，我们在数据库节点初始化数据库，并进行相关的配置。

```bash
$ initdb -k -D testdb
$ cat <<EOF >> testdb/pg_hba.conf
host	all				all		10.9.10.0/24		scram-sha-256
host	replication		all		10.9.10.0/24		scram-sha-256
EOF
$ cat <<EOF >> testdb/postgresql.auto.conf
listen_addresses = '*'
EOF

$ pg_ctl start -l log -D testdb
$ psql postgres -c "CREATE USER u01 WITH replication PASSWORD 'helloworld'"
```

为了确保 `pg_probackup` 能够正常运行，我们还需要授权 `u01` 用户对于 `pg_backup_start()`、`pg_backup_stop()` 和 `pg_create_restore_point()` 函数的可执行权限。

```bash
$ psql postgres -c "GRANT EXECUTE ON FUNCTION pg_backup_start TO u01"
$ psql postgres -c "GRANT EXECUTE ON FUNCTION pg_backup_stop TO u01"
$ psql postgres -c "GRANT EXECUTE ON FUNCTION pg_create_restore_point TO u01"
```

接着我们创建两个表空间，一个用于存储表、一个用于存储索引。

```bash
$ mkdir tblspc idxspc
$ psql postgres -c "CREATE TABLESPACE tblspc LOCATION '/home/japin/lab/tblspc'"
$ psql postgres -c "CREATE TABLESPACE idxspc LOCATION '/home/japin/lab/idxspc'"
$ psql postgres -c 'SELECT oid, spcname, pg_tablespace_location(oid) FROM pg_tablespace'
  oid  |  spcname   | pg_tablespace_location
-------+------------+------------------------
  1663 | pg_default |
  1664 | pg_global  |
 16389 | tblspc     | /home/japin/lab/tblspc
 16390 | idxspc     | /home/japin/lab/idxspc
(4 rows)
```

最后，使用 `pgbench` 导入数据。

```bash
$ pgbench -i -s 50 --tablespace tblspc --index-tablespace idxspc postgres
dropping old tables...
NOTICE:  table "pgbench_accounts" does not exist, skipping
NOTICE:  table "pgbench_branches" does not exist, skipping
NOTICE:  table "pgbench_history" does not exist, skipping
NOTICE:  table "pgbench_tellers" does not exist, skipping
creating tables...
generating data (client-side)...
5000000 of 5000000 tuples (100%) done (elapsed 25.46 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 38.50 s (drop tables 0.01 s, create tables 0.01 s, client-side generate 25.71 s, vacuum 0.89 s, primary keys 11.89 s).
```

## 使用 `pg_basebackup` 备份恢复表空间

一切准备就绪，现在我们使用 `pg_basebackup` 来备份 PostgreSQL 表空间，在备份节点执行下面的命令：

```bash
$ pg_basebackup -h 10.9.10.106 -p 5432 -U u01 -D basebackupdb
Password:
$ ls -lh
total 16K
drwx------ 19 japin japin 4.0K Jun 20 18:42 basebackupdb
drwx------  3 japin japin 4.0K Jun 20 18:42 idxspc
-rw-rw-r--  1 japin japin  104 Jun 20 17:48 pg-env.sh
drwx------  3 japin japin 4.0K Jun 20 18:41 tblspc
```

可以看到表空间直接就备份过来了，无需任何额外的操作。我们将备库启动起来可以看到备份的数据。

```bash
$ pg_ctl start -l log -D basebackupdb
waiting for server to start.... done
server started
$ psql postgres -c 'SELECT spcname, pg_tablespace_location(oid) FROM pg_tablespace'
  spcname   | pg_tablespace_location
------------+------------------------
 pg_default |
 pg_global  |
 tblspc     | /home/japin/lab/tblspc
 idxspc     | /home/japin/lab/idxspc
(4 rows)
$ psql postgres
[local]:29726 postgres=# SELECT count(1) from pgbench_accounts;
  count
---------
 5000000
(1 row)
```

如果我们想要将表空间备份到不同的路径，那么我们需要使用 `--tablespace-mapping, -T` 选项，如下所示：

```bash
$ pg_basebackup -h 10.9.10.106 -p 5432 -U u01 -D basebackupdb \
  -T /home/japin/lab/tblspc=/mnt/workspace/tblspc -T /home/japin/lab/idxspc=/mnt/workspace/idxspc
Password:
b$ pg_ctl start -l log -D basebackupdb
waiting for server to start.... done
server started
$ psql postgres -c 'SELECT spcname, pg_tablespace_location(oid) FROM pg_tablespace'
  spcname   | pg_tablespace_location
------------+------------------------
 pg_default |
 pg_global  |
 tblspc     | /mnt/workspace/tblspc
 idxspc     | /mnt/workspace/idxspc
(4 rows)
```

从上面可以看到表空间 `tblspc, idxspc` 分别指向了 `/mnt/workspace/tblspc, /mnt/workspace/idxspc`。

## 使用 `pg_probackup` 备份恢复表空间

首先，初始化备份目录。

```bash
$ pg_probackup init -B /mnt/workspace/BackupTest
INFO: Backup catalog '/mnt/workspace/BackupTest' successfully initialized
```

接着，创建备份实例（您需要先配置备份节点到数据库节点的 SSH 互信）。

```bash
$ pg_probackup add-instance -B /mnt/workspace/BackupTest --instance lab --pgdata /home/japin/lab/testdb \
  --remote-host 10.9.10.106 --remote-port 22 --remote-user japin --remote-path /opt/pg/bin
INFO: Instance 'lab' successfully initialized
```

* `--pgdata` 指定数据库存储的路径
* `--remote-host` 指定 SSH 连接地址
* `--remote-port` 指定 SSH 连接端口
* `--remote-user` 指定 SSH 连接用户
* `--remote-path` 指定远端 `pg_probackup` 的路径

完成上述准备工作之后，现在我们可以执行备份操作了。这里我们以全备作为示例。

```bash
$ pg_probackup backup -B /mnt/workspace/BackupTest --instance lab --pgdata /home/japin/lab/testdb \
  --backup-mode FULL --stream --pghost 10.9.10.106 --pgport 5432 --pguser u01 --pgdatabase postgres \
  --remote-host 10.9.10.106 --remote-port 22 --remote-user japin --remote-path /opt/pg/bin
INFO: Backup start, pg_probackup version: 2.5.12, instance: lab, backup ID: RWSH8U, backup mode: FULL, wal mode: STREAM, remote: true, compress-algorithm: none, compress-level: 1
Password for user u01:
INFO: This PostgreSQL instance was initialized with data block checksums. Data block corruption will be detected
INFO: Database backup start
INFO: wait for pg_backup_start()
INFO: Wait for WAL segment /mnt/workspace/BackupTest/backups/lab/RWSH8U/database/pg_wal/000000010000000000000030 to be streamed
INFO: PGDATA size: 770MB
INFO: Current Start LSN: 0/30000028, TLI: 1
INFO: Start transferring data files
INFO: Data files are transferred, time elapsed: 12s
INFO: wait for pg_stop_backup()
INFO: pg_stop backup() successfully executed
INFO: stop_lsn: 0/30000168
INFO: Getting the Recovery Time from WAL
INFO: Syncing backup files to disk
INFO: Backup files are synced, time elapsed: 0
INFO: Validating backup RWSH8U
INFO: Backup RWSH8U data files are valid
INFO: Backup RWSH8U resident size: 803MB
INFO: Backup RWSH8U completed
```

通过查看备份目录我们可以看到 `pg_probackup` 在备份的时候是将表空间的信息直接备份到了 `pg_tblspc` 目录下面。

```bash
$ ls -al /mnt/workspace/BackupTest/backups/lab/RWSH8U/database/pg_tblspc/16389/PG_15_202209061/5/
total 656708
drwx------ 2 japin japin      4096 Jun 25 11:19 .
drwx------ 3 japin japin      4096 Jun 25 11:19 ..
-rw------- 1 japin japin 672137600 Jun 25 11:19 16403
-rw------- 1 japin japin    188416 Jun 25 11:19 16403_fsm
-rw------- 1 japin japin     24576 Jun 25 11:19 16403_vm
-rw------- 1 japin japin      8200 Jun 25 11:19 16404
-rw------- 1 japin japin     24576 Jun 25 11:19 16404_fsm
-rw------- 1 japin japin      8192 Jun 25 11:19 16404_vm
-rw------- 1 japin japin     24600 Jun 25 11:19 16406
-rw------- 1 japin japin     24576 Jun 25 11:19 16406_fsm
-rw------- 1 japin japin      8192 Jun 25 11:19 16406_vm
$ ls -al /mnt/workspace/BackupTest/backups/lab/RWSH8U/database/pg_tblspc/16390/PG_15_202209061/5/
total 109876
drwx------ 2 japin japin      4096 Jun 25 11:19 .
drwx------ 3 japin japin      4096 Jun 25 11:19 ..
-rw------- 1 japin japin     16400 Jun 25 11:19 16407
-rw------- 1 japin japin     32800 Jun 25 11:19 16409
-rw------- 1 japin japin 112446600 Jun 25 11:19 16411
```

最后，我们来测试恢复过程。

```bash
$ pg_probackup restore -B /mnt/workspace/BackupTest --instance lab --pgdata $PWD/db-backup
INFO: Tablespace 16390 will be restored using old path "/home/japin/lab/idxspc"
INFO: Tablespace 16389 will be restored using old path "/home/japin/lab/tblspc"
INFO: Validating backup RWSH8U
INFO: Backup RWSH8U data files are valid
INFO: Backup RWSH8U WAL segments are valid
INFO: Backup RWSH8U is valid.
INFO: Restoring the database from backup at 2023-06-25 11:19:42+08
INFO: Start restoring backup files. PGDATA size: 802MB
INFO: Backup files are restored. Transfered bytes: 802MB, time elapsed: 1s
INFO: Restore incremental ratio (less is better): 100% (802MB/802MB)
INFO: Syncing restored files to disk
INFO: Restored backup files are synced, time elapsed: 3s
INFO: Restore of backup RWSH8U completed.
```

可以看到表空间恢复到了 `/home/japin/lab/idxspc` 和 `/home/japin/lab/tblspc`，这与备份前的路径是一致的，我们启动数据库验证一下。

```bash
$ psql postgres -c 'SELECT oid, spcname, pg_tablespace_location(oid) FROM pg_tablespace';
  oid  |  spcname   | pg_tablespace_location
-------+------------+------------------------
  1663 | pg_default |
  1664 | pg_global  |
 16389 | tblspc     | /home/japin/lab/tblspc
 16390 | idxspc     | /home/japin/lab/idxspc
(4 rows)
```

同样地，我们可以在恢复的时候指定表空间的路径。

```bash
$ pg_ctl stop -l log -D $PWD/db-backup
waiting for server to shut down.... done
server stopped
$ rm -rf db-backup/ idxspc/ tblspc/
$ rm -rf /mnt/workspace/{tblspc,idxspc}/*

$ pg_probackup restore -B /mnt/workspace/BackupTest --instance lab --pgdata $PWD/db-backup \
  --tablespace-mapping /home/japin/lab/tblspc=/mnt/workspace/tblspc \
  --tablespace-mapping /home/japin/lab/idxspc=/mnt/workspace/idxspc
INFO: Tablespace 16390 will be remapped from "/home/japin/lab/idxspc" to "/mnt/workspace/idxspc"
INFO: Tablespace 16389 will be remapped from "/home/japin/lab/tblspc" to "/mnt/workspace/tblspc"
INFO: Validating backup RWSH8U
INFO: Backup RWSH8U data files are valid
INFO: Backup RWSH8U WAL segments are valid
INFO: Backup RWSH8U is valid.
INFO: Restoring the database from backup at 2023-06-25 11:19:42+08
INFO: Start restoring backup files. PGDATA size: 802MB
INFO: Backup files are restored. Transfered bytes: 802MB, time elapsed: 2s
INFO: Restore incremental ratio (less is better): 100% (802MB/802MB)
INFO: Syncing restored files to disk
INFO: Restored backup files are synced, time elapsed: 1s
INFO: Restore of backup RWSH8U completed.
```
从日志信息中可以看到 `/home/japin/lab/idxspc` 将被映射到 `/mnt/workspace/idxspc`，`/home/japin/lab/tblspc` 将被映射到 `/mnt/workspace/tblspc`。同样地，启动数据库服务器进行验证。

```bash
$ pg_ctl start -l log -D $PWD/db-backup
waiting for server to start.... done
server started
$ psql postgres -c 'SELECT oid, spcname, pg_tablespace_location(oid) FROM pg_tablespace';
  oid  |  spcname   | pg_tablespace_location
-------+------------+------------------------
  1663 | pg_default |
  1664 | pg_global  |
 16389 | tblspc     | /mnt/workspace/tblspc
 16390 | idxspc     | /mnt/workspace/idxspc
(4 rows)
```

## 总结

`pg_basebackup` 和 `pg_probackup` 均支持表空间的备份，它们的不同在于 `pg_basebackup` 在备份的时候需要指定表空间映射关系（在与源数据库不一致的情况下），而 `pg_probackup` 在备份时则不需要指定表空间映射，但是在恢复的时候需要提供映射关系（如果需要）。

<div class="just-for-fun">
笑林广记 - 鸽舌

有涩舌者，俗云鸽口是也。
来到市中买桐油，向店主曰：“我要买桐桐桐……”油字再也说不出口。
店主取笑曰：“你这人倒会打铜鼓，何不再敲通铜锣与我听？”
鸽者怒曰：“你不要当当当面来腾腾腾倒刮刮刮削我。”
</div>
