---
title: "PostgreSQL 12 流复制配置"
date: 2020-02-19 21:44:42 +0800
category: Database
tags:
  - PostgreSQL
---

PostgreSQL 12 的流复制与之前的版本有所不同，主要有以下几点区别：

1. PG12 将原有的属于 `recovery.conf` 配置文件中配置项迁移到了 `postgresql.conf` 文件中，在新系统中如果存在 `recovery.conf` 文件，数据库将无法启动；
2. 文件 `recovery.signal` 和 `standby.signal` 用于切换数据库为非主（non-primary）模式；
3. `trigger_file` 被修改为 `promote_trigger_file` 并且只能在 `postgresql.conf` 配置文件或服务器命令行进行配置；
4. 最后，`standby_mode` 参数被移除了。

详细说明请[移步官网](https://www.postgresql.org/docs/12/release-12.html)。本文将在 Ubuntu 18.04 LTS 下搭建 PG12 的流复制系统。

<!-- more -->

## 安装数据库

我们在主节点下载 PostgreSQL 12.2 源码，并采用如下命名进行编译安装：

``` shell
$ ./configure --prefix=$HOME/pg12.2
$ make -j 4 && make install
```

随后将其拷贝到从节点。为了方便我们可以先配置环境变量，如下所示：

``` shell
$ cd $HOME/pg12.2
$ cat <<END > pg12.2-env.sh
export PGHOME=$PWD
export PGDATA=\$PGHOME/pgdata
export PATH=\$PGHOME/bin:\$PATH
export LD_LIBRARY_PATH=\$PGHOME/lib:\$LD_LIBRARY_PATH
END

$ source pg12.2-env.sh
```

我们接下来将在主节点 192.168.56.3 和从节点 192.168.56.101 上搭建 PostgreSQL 流复制。

## 初始化数据库

在主节点上初始化并启动数据库。

``` shell
$ initdb
$ pg_ctl -l log start
```

## 配置数据库

接着，我们需要修改监听地址，当修改之后需要重启。

``` shell
$ psql -c "ALTER SYSTEM SET listen_addresses TO '*'" postgres
$ pg_ctl -l log restart
```
我们可以不必在主节点上设置任何其他参数来进行简单的复制设置，因为默认设置已经适用。

现在，我们需要一个用户用于流复制。

``` shell
$ psql -c "CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'P@ssw0rd'" postgres
```

最后，我们需要配置连接以便从节点可以连接主节点进行复制，我需要修改 `pg_hba.conf` 配置文件。如果我们允许故障切换，那么可能还需要主节点可以连接从节点。

``` shell
$ echo "host replication replicator 192.168.56.0/24 md5" >> $PGDATA/pg_hba.conf
$ psql -c "SELECT pg_reload_conf()" postgres
```

## 备份数据库

现在，我们可以在从节点使用 `pg_basebackup` 来做一个主库的基础备份。当我们创建备份时可以指定 `-R` 选项在数据目录中生成特定于复制的文件和配置。

``` shell
$ source $HOME/pg12.2/pg12.2-env.sh
$ pg_basebackup -h 192.168.56.3 -U replicator -D $PGDATA -R -Fp -Xs -P
Password:
23652/23652 kB (100%), 1/1 tablespace

$ ls $PGDATA
PG_VERSION    pg_commit_ts   pg_logical    pg_serial     pg_subtrans  pg_xact
backup_label  pg_dynshmem    pg_multixact  pg_snapshots  pg_tblspc    postgresql.auto.conf
base          pg_hba.conf    pg_notify     pg_stat       pg_twophase  postgresql.conf
global        pg_ident.conf  pg_replslot   pg_stat_tmp   pg_wal       standby.signal

$ cat $PGDATA/postgresql.auto.conf
# Do not edit this file manually!
# It will be overwritten by the ALTER SYSTEM command.
listen_addresses = '*'
primary_conninfo = 'user=replicator password=''P@ssw0rd'' host=192.168.56.3 port=5432 sslmode=disable sslcompression=0 gssencmode=disable krbsrvname=postgres target_session_attrs=any'
```

从下面我们可以看到，备库有一个名为 `standby.signal` 的文件，该文件没有任何内容，它仅仅是用于 PostgreSQL 确定其状态。如果该文件不存在，我们应该在备库上创建该文件。

此外，我们还需要注意到 `postgresql.auto.conf` 文件中的 `primary_conninfo` 参数，该参数在 PG12 之前是存放在 `recovery.conf` 文件中，并且还有一个参数 `standby_mode = on`。

## 启动备库

现在我们使用下面的命令启动备库：

``` shell
$ pg_ctl -l log start
```

我们可以在主库上查看流复制相关信息：

```
postgres=# \x
Expanded display is on.
postgres=# select * from pg_stat_replication ;
-[ RECORD 1 ]----+------------------------------
pid              | 31970
usesysid         | 16385
usename          | replicator
application_name | walreceiver
client_addr      | 192.168.56.101
client_hostname  |
client_port      | 60384
backend_start    | 2020-02-19 23:07:21.410168+08
backend_xmin     |
state            | streaming
sent_lsn         | 0/3000148
write_lsn        | 0/3000148
flush_lsn        | 0/3000148
replay_lsn       | 0/3000148
write_lag        |
flush_lag        |
replay_lag       |
sync_priority    | 0
sync_state       | async
reply_time       | 2020-02-19 23:07:31.644624+08
```

我们可以看到，默认情况下 PG 采用异步复制。

## 同步复制

我们接下来可以修改 `synchronous_standby_names` 从而使从节点由异步节点改变为同步节点。首先我们在主节点上做如下改变：

```
$ psql -c "ALTER SYSTEM SET synchronous_standby_names TO 'standby'" postgres
$ psql -c "SELECT pg_reload_conf()" postgres
```

接着，在从节点修改 `primary_conninfo` 参数，并在其中加入 `application_name=standby`，并重启，如下所示：

```
$ cat $PGDATA/postgresql.auto.conf
# Do not edit this file manually!
# It will be overwritten by the ALTER SYSTEM command.
listen_addresses = '*'
primary_conninfo = 'user=replicator password=''P@ssw0rd'' host=192.168.56.3 port=5432 sslmode=disable sslcompression=0 gssencmode=disable krbsrvname=postgres target_session_attrs=any application_name=standby'

$ pg_ctl -l log restart
```

接下来我们可以在主节点进行验证：

```
postgres=# select * from pg_stat_replication ;
-[ RECORD 1 ]----+------------------------------
pid              | 32052
usesysid         | 16385
usename          | replicator
application_name | standby
client_addr      | 192.168.56.101
client_hostname  |
client_port      | 60386
backend_start    | 2020-02-19 23:18:30.358057+08
backend_xmin     |
state            | streaming
sent_lsn         | 0/3025410
write_lsn        | 0/3025410
flush_lsn        | 0/3025410
replay_lsn       | 0/3025410
write_lag        | 00:00:00.001529
flush_lag        | 00:00:00.001529
replay_lag       | 00:00:00.001529
sync_priority    | 1
sync_state       | sync
reply_time       | 2020-02-19 23:18:30.480227+08
```

## 提升从节点

当主节点掉线时，我们可能希望将从节点提升为主节点，此时，我们需要使用到 `promote_trigger_file` 参数。

首先，我们在主节点和从节点看看它们各自的状态。

```
$ postgres=# select pg_is_in_recovery();  -- 主节点
 pg_is_in_recovery
-------------------
 f
(1 row)
```

```
postgres=# select pg_is_in_recovery();    -- 从节点
 pg_is_in_recovery
-------------------
 t
(1 row)
```

接着，我们在从节点的 `postgresql.conf` 文件中加入 `promote_trigger_file=/tmp/.tfile` 配置，这是，当主节点掉线时，我们在从节点创建 `/tmp/.tfile` 文件，那么从节点将自动提升为主。

## 参考

[1] https://www.postgresql.org/docs/12/release-12.html
[2] https://www.postgresql.org/docs/12/runtime-config-replication.html#GUC-PROMOTE-TRIGGER-FILE
[3] https://www.percona.com/blog/2019/10/11/how-to-set-up-streaming-replication-in-postgresql-12/