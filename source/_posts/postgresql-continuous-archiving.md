---
title: PostgreSQL 持续归档
date: 2018-10-24 20:25:24
category: 数据库
tags:
  - PostgreSQL
---

无论何时，PostgreSQL 总是在集群的数据目录 pg_wal 下面维护一个 _Write Ahead Log_ 日志记录。该日志记录了数据文件的所有变化。当数据库系统发生崩溃时，数据库系统可以通过重放最新检查点之后的 WAL 日志条目来恢复数据库的一致性。在 PostgreSQL 中，我们通过将文件系统级的备份与 WAL 日志的备份相结合可以实现三种策略的数据库备份。当需要进行数据库恢复时，我们先恢复文件系统的备份，随后通过重放备份的 WAL 日志使得数据库进入到当前状态。尽管该方法过于复杂，但是它拥有以下好处：

* 我们不需要完全一致的文件系统备份作为起点。备份中的任何内部不一致都将通过日志重放进行更正 (这与崩溃恢复期间发生的情况没有显着差异)。因此，我们不需要文件系统快照功能，只需要 tar 或类似的归档工具。
* 没有必要一直重放 WAL 条目到最后。我们可以在任何时候停止重放并拥有当时数据库的一致快照。因此，该技术支持时间点恢复 (Point-in-Time Recovery, PITR)。为此，我们可以将数据库还原到自从进行基本备份以后的任何状态。
* 如果我们持续地将一系列 WAL 日志文件提供给另一台已加载相同基本备份文件的计算机，此时，我们就拥有了一个热备系统：在任何时候我们都可以启动这台机器，它将拥有与原数据库几乎一致的状态。

与普通文件系统备份技术一样，该方法只能支持恢复整个数据库集群，而不能用于恢复其子集。同时，它也需要更多的归档空间：基本的文件系统备份可能很庞大，繁忙的系统将生成许多必须归档的 WAL 流量。尽管如此，在多数情况下，它仍然是需要高可靠性的首选备份技术。

我们需要一系列连续归档 WAL 日志文件，这些文件至少可以延伸到备份的开始时间，从而确保连续归档 (许多数据库供应商也称为“在线备份”) 成功恢复。

<!-- more -->

## WAL 日志归档

从抽象的意义上说，PostgreSQL 数据库系统会产生无限长的 WAL 日志记录序列。PostgreSQL 数据库该序列划分 WAL 段文件，通常每个段文件为 16MB (在构建 PostgreSQL 时可以更改段大小)。段文件的数字名称反映了它们在抽象 WAL 序列中的位置。当不使用 WAL 归档时，PostgreSQL 通常只需要创建几个段文件，然后通过将不再需要的段文件重命名为更高的段号来“回收”它们。

当使用 WAL 日志归档时，我们需要在每个段文件填充后捕获它们的内容，并在段文件被回收再利用之前将该数据保存在其他某处。PostgreSQL 允许管理员指定要执行的 shell 命令，以将已完成的段文件复制到需要的位置。该命令可以简单的 cp 命令，也可以是复杂的 shell 脚步，一切都取决于用户。

我们需要设置三个选项以便启用 WAL 日志归档： wal_level，archive_mode 和 archive_command。

__wal_level__ - 必须为 replica 或者更高的级别。
__archive_mode__ - 设置为 on。
__archive_command__ - 通常为归档命令，其中 `%p` 被替换为要归档的文件的路径名，`%f` 被替换为要归档的文件的文件名。如果需要在命令中嵌入实际的 `％` 字符，请使用 `%%`。


接下来我们尝试配置 WAL 日志归档，首先进行相关的准备工作，编译 PostgreSQL 10.4，初始化数据库，建立归档日志存储路径 (本例旨在使用 WAL 日志归档，因此就在本地建立目录来存储备份的 WAL 日志，通常的做法时备份到其他主机)，

```
$ pwd
/home/postgres/postgresql-10.4
$ ls
drwxr-xr-x  2 postgres postgres 4096 Oct 24 13:36 bin
drwx------ 19 postgres postgres 4096 Oct 24 13:49 data
drwxr-xr-x  6 postgres postgres 4096 Oct 24 13:36 include
drwxr-xr-x  4 postgres postgres 4096 Oct 24 13:36 lib
-rw-rw-r--  1 postgres postgres  177 Oct 24 13:39 pg-env.sh
drwxr-xr-x  6 postgres postgres 4096 Oct 24 13:36 share
$ cat pg-env.sh
export PGHOME=/home/postgres/postgresql-10.4
export PGDATA=/home/postgres/postgresql-10.4/data
export PATH=$PGHOME/bin:$PATH
export LD_LIBRARY_PATH=$PGHOME/lib:$LD_LIBRARY_PATH
$ mkdir wals            # 建立 WAL 日志备份目录
$ . pg-env.sh           # 初始化环境变量
$ initdb -D data        # 初始化数据库集群
```

接着修改 data/postgresql.conf 文件中的 wal_level，archive_mode 和 archive_command 参数。

```
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /home/postgres/postgresql-10.4/wals/%f && cp %p /home/postgres/postgresql-10.4/wals/%f'
```

按照上述操作进行，我们目前已经配置好了 WAL 日志归档，接下来我们运行数据库并创建一个基本备份 (即文件系统级备份) 并保存在当前目录。

```
$ pg_ctl -D data -l logfile start
$ psql -c "SELECT pg_start_backup('label');" postgres
$ tar -C data -czvf pg_basebackup_backup.tar.gz .
$ psql -c "SELECT pg_stop_backup();" postgres
```

此时，我们创建好了数据库集群的基本备份，之后我们便可以通过该基本备份并结合 WAL 日志备份进行恢复。紧接着，我们对数据库做一些修改，并停止数据库然后删除 data 目录。

```
$ psql postgres
psql (10.4)
Type "help" for help.

postgres=# create table test (id int, name varchar(10));
CREATE TABLE
postgres=# insert into test values (1, 'postgres');
INSERT 0 1
postgres=# select * from test ;
 id |   name
 ----+----------
   1 | postgres
(1 row)

postgres=# \q
$ pg_ctl -D data -l logfile stop
$ rm -rf data
```

下面将演示如何使用基础备份及 WAL 日志备份恢复数据库。

``` shell
$ initdb -D data1                    # 重新初始化一个数据库集群
$ tar -C data1 -xvf pg_basebackup_backup.tar.gz
$ cat <<END > data1/recovery.conf    # 创建恢复脚步
restore_command = 'cp /home/postgres/postgresql-10.4/wals/%f %p'
END
$ pg_ctl -D data1 -l logfile start   # 恢复
```

在恢复完成之后，PostgreSQL 将把 recovery.conf 文件重命名为 recovery.done。


## 参考

[1] https://www.postgresql.org/docs/10/static/continuous-archiving.html
