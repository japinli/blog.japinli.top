---
title: "PostgreSQL 作业调度器 - pg_cron"
date: 2021-11-18 22:03:19
categories: 数据库
tags:
  - PostgreSQL
---

[pg_cron](https://github.com/citusdata/pg_cron) 是 PostgreSQL 数据库的一个作业调度器插件，通过该插件我们可以定时的执行一些特殊的任务。它遵循 Linux crontab 的配置语法，您可以通过在线工具 [crontab.guru](http://crontab.guru/) 来验证您的 cron 表达式。目前，pg_cron 仅支持 PostgreSQL 10 及其之后的版本。本文将简要介绍 pg_cron 的安装及其使用。

<!--more-->

## 准备

在开始之前，我们需要安装 pg_cron 插件，这里采用源码编译的方式安装。

```shell
$ git clone https://github.com/citusdata/pg_cron.git
$ cd pg_cron
$ make && make install
```

在执行上面的命令之前，您需要配置好 PostgreSQL 的环境变量，以便 `make` 执行的时候可以找到 `pg_config` 命令来获取相关的信息（包括编译选项、安装路径等）。

接着，我们需要修改 PostgreSQL 的配置参数，并重启数据库，最后在创建 pg_cron 插件，您可以使用如下的命令来完成这些工作。

```sql
$ psql postgres -c 'ALTER SYSTEM SET shared_preload_libraries TO pg_cron;'
$ pg_ctl restart
$ psql postgres -c 'CREATE EXTENSION pg_cron;'
```

当我们成功执行上述命令之后，pg_cron 将创建一个 `cron` 的模式，并在该模式下创建如下函数：

- **alter_job** - 修改 job 信息
  ```sql
  void cron.alter_job(
      job_id bigint,
	  schedule text DEFAULT NULL::text,
	  command text DEFAULT NULL::text,
	  database text DEFAULT NULL::text,
	  username text DEFAULT NULL::text,
	  active boolean DEFAULT NULL::boolean);
  ```
- **job_cache_invalidate** - 清除 job 缓存信息触发器
  ```sql
  trigger cron.job_cache_invalidate();
  ```
- **schedule** - 创建 job 任务，支持匿名 job 和命名 job 两种类型
  ```sql
  bigint cron.schedule(schedule text, command text);
  bigint cron.schedule(job_name text, schedule text, command text);
  ```
- **schedule_in_database** - 为其他数据库创建 job
  ```sql
  bigint cron.schedule_in_database(
      job_name text,
	  schedule text,
	  command text,
	  database text,
	  username text DEFAULT NULL::text,
	  active boolean DEFAULT true);
  ```
- **unschedule** - 删除 job 任务，支持以 job id 和 job 名字两种方式来删除
  ```sql
  boolean cron.unschedule(job_id bigint);
  boolean cron.unschedule(job_name name);
  ```

以及 `job` 和 `job_run_details` 表。

- **job** - job 信息表，记录当前创建的所有 job 信息
- **job_run_details** - job 运行信息表，用于记录 job 运行后的状态及其相关信息

## 测试

我们创建一个 `mylog` 表来记录日志。

```sql
CREATE TABLE mylog(create_date timestamp, info text);
```

随后创建一个函数来向 `mylog` 中插入数据。

```sql
CREATE OR REPLACE FUNCTION insert_log_job() RETURNS void
AS $body$
BEGIN
    INSERT INTO mylog VALUES (now(), 'hello world');
END;
$body$ LANGUAGE plpgsql;
```

接下来我们创建便可以创建 job 了，这里我们将创建一个匿名 job 和一个命令 job。

```sql
SELECT cron.schedule(
    '*/1 * * * *',
	$$ BEGIN SELECT insert_log_job() END; $$
);
```

上面的命令创建的 job 存在语法问题，我们可以通过 `alter_job` 来对其进行修改。

```sql
select cron.alter_job(1, '*/1 * * * *', 'SELECT insert_log_job();');
```

现在我们可以在 `job_run_details` 中看到 job 的详细信息。

```sql
postgres=# select * from cron.job_run_details \gx
-[ RECORD 1 ]--+---------------------------------------------
jobid          | 1
runid          | 1
job_pid        | 1392744
database       | postgres
username       | px
command        |  BEGIN SELECT insert_log_job() END;
status         | failed
return_message | ERROR:  syntax error at or near "SELECT"    +
               | LINE 1:  BEGIN SELECT insert_log_job() END; +
               |                ^                            +
               |
start_time     | 2021-11-18 23:08:00.018493+08
end_time       | 2021-11-18 23:08:00.02138+08
-[ RECORD 2 ]--+---------------------------------------------
jobid          | 1
runid          | 2
job_pid        | 1392892
database       | postgres
username       | px
command        |  BEGIN SELECT insert_log_job() END;
status         | failed
return_message | ERROR:  syntax error at or near "SELECT"    +
               | LINE 1:  BEGIN SELECT insert_log_job() END; +
               |                ^                            +
               |
start_time     | 2021-11-18 23:09:00.018235+08
end_time       | 2021-11-18 23:09:00.020252+08
-[ RECORD 3 ]--+---------------------------------------------
jobid          | 1
runid          | 3
job_pid        | 1393038
database       | postgres
username       | px
command        |  BEGIN SELECT insert_log_job() END;
status         | failed
return_message | ERROR:  syntax error at or near "SELECT"    +
               | LINE 1:  BEGIN SELECT insert_log_job() END; +
               |                ^                            +
               |
start_time     | 2021-11-18 23:10:00.02294+08
end_time       | 2021-11-18 23:10:00.02633+08
-[ RECORD 4 ]--+---------------------------------------------
jobid          | 1
runid          | 4
job_pid        | 1393183
database       | postgres
username       | px
command        | SELECT insert_log_job();
status         | succeeded
return_message | 1 row
start_time     | 2021-11-18 23:11:00.011896+08
end_time       | 2021-11-18 23:11:00.016711+08
```

同时，我们也可以看到在 `mylog` 表中插入了一条新的记录。

```sql
postgres=# SELECT * FROM mylog;
        create_date         |    info
----------------------------+-------------
 2021-11-18 23:11:00.011996 | hello world
(1 row)
```

随后，我们修改一下其执行的周期，将 1 分钟执行一次改为 10 分钟执行一次（避免过多的日志）。

```sql
postgres=# SELECT cron.alter_job(1, '*/10 * * * *');
 alter_job
-----------

(1 row)
```

现在，我们再来创建一个命名的 job。

```sql
postgres=# SELECT cron.schedule('job1', '*/5 * * * *', 'SELECT insert_log_job()');
 schedule
----------
        2
(1 row)

postgres=# select * from cron.job;
 jobid |   schedule   |         command          | nodename  | nodeport | database | username | active | jobname
-------+--------------+--------------------------+-----------+----------+----------+----------+--------+---------
     1 | */10 * * * * | SELECT insert_log_job(); | localhost |     5432 | postgres | px       | t      |
     2 | */5 * * * *  | SELECT insert_log_job()  | localhost |     5432 | postgres | px       | t      | job1
(2 rows)
```

等待 job 执行后，我们可以查看 `job_run_details` 来验证 job 的执行。

```sql
postgres=# SELECT * FROM cron.job_run_details \gx
...
-[ RECORD 4 ]--+---------------------------------------------
jobid          | 1
runid          | 4
job_pid        | 1393183
database       | postgres
username       | px
command        | SELECT insert_log_job();
status         | succeeded
return_message | 1 row
start_time     | 2021-11-18 23:11:00.011896+08
end_time       | 2021-11-18 23:11:00.016711+08
-[ RECORD 5 ]--+---------------------------------------------
jobid          | 2
runid          | 5
job_pid        | 1394493
database       | postgres
username       | px
command        | SELECT insert_log_job()
status         | succeeded
return_message | 1 row
start_time     | 2021-11-18 23:20:00.021353+08
end_time       | 2021-11-18 23:20:00.033443+08
-[ RECORD 6 ]--+---------------------------------------------
jobid          | 1
runid          | 6
job_pid        | 1394494
database       | postgres
username       | px
command        | SELECT insert_log_job();
status         | succeeded
return_message | 1 row
start_time     | 2021-11-18 23:20:00.025503+08
end_time       | 2021-11-18 23:20:00.039575+08
```

最后，我们来看看如何删除 job。pg_cron 提供了两种方式。

```sql
postgres=# SELECT cron.unschedule(1);  -- 以 job id 的方式删除 job
 unschedule
------------
 t
(1 row)

postgres=# SELECT * FROM cron.job;
 jobid |   schedule   |         command          | nodename  | nodeport | database | username | active | jobname
-------+--------------+--------------------------+-----------+----------+----------+----------+--------+---------
     2 | */5 * * * *  | SELECT insert_log_job()  | localhost |     5432 | postgres | px       | t      | job1
(1 row)

postgres=# SELECT cron.unschedule('job1'); -- 以 job 名字的方式删除 job，仅支持命名 job
 unschedule
------------
 t
(1 row)

postgres=# SELECT * FROM cron.job;
 jobid | schedule | command | nodename | nodeport | database | username | active | jobname
-------+----------+---------+----------+----------+----------+----------+--------+---------
(0 rows)
```

## 进阶

在了解了 pg_cron 的基本使用之后，我们来看看其他的一些使用，我们首先创建一个用户和数据库，并切换到改数据库。

```sql
postgres=# CREATE USER japin WITH ENCRYPTED PASSWORD 'japin';
CREATE ROLE
postgres=# CREATE DATABASE testdb OWNER japin;
CREATE DATABASE
postgres=# \c testdb japin
You are now connected to database "testdb" as user "japin".
```

随后在 `testdb` 中新建表和函数。

```sql
CREATE TABLE log(info text, at timestmap);

CREATE OR REPLACE FUNCTION testdb_insert_log_job() RETURNS void
AS $body$
BEGIN
    INSERT INTO log VALUES ('hello, testdb', now());
END;
$body$ LANGUAGE plpgsql;
```

接着我们切换到超级用户并执行下面的语句，他就为 `testdb` 创建一个 job。

```sql
SELECT cron.schedule_in_database(
    'testdb_job1',
	'*/1 * * * *',
	'SELECT testdb_insert_log_job()',
	'testdb',
	'japin',
	true);
```

我们同样可以通过 `cron.job` 表查看 job 的信息，以及 `cron.job_run_details` 查看运行状态。

```sql
postgres=# SELECT * FROM cron.job;
 jobid |  schedule   |            command             | nodename  | nodeport | database | username | active |   jobname
-------+-------------+--------------------------------+-----------+----------+----------+----------+--------+-------------
     4 | */1 * * * * | SELECT testdb_insert_log_job() | localhost |     5432 | testdb   | japin    | t      | testdb_job1
(1 row)

postgres=# SELECT * FROM cron.job_run_details \gx
...
-[ RECORD 8 ]--+---------------------------------------------
jobid          | 3
runid          | 8
job_pid        | 1397538
database       | testdb
username       | japin
command        | SELECT testdb_insert_log_job()
status         | succeeded
return_message | 1 row
start_time     | 2021-11-18 23:41:00.028916+08
end_time       | 2021-11-18 23:41:00.03695+08
-[ RECORD 9 ]--+---------------------------------------------
jobid          | 3
runid          | 9
job_pid        | 1397689
database       | testdb
username       | japin
command        | SELECT testdb_insert_log_job()
status         | succeeded
return_message | 1 row
start_time     | 2021-11-18 23:42:00.028686+08
end_time       | 2021-11-18 23:42:00.033203+08
```

最后我们查看 `log` 表来验证 job 是否执行。

```sql
testdb=> SELECT * FROM log;
     info      |             at
---------------+----------------------------
 hello, testdb | 2021-11-18 23:40:00.022578
 hello, testdb | 2021-11-18 23:41:00.029197
(2 rows)
```

**注意：**在为其他数据创建 job 时，我们需要保证其能连接到相应的数据库，并且连接的用户有权限执行函数。因此您可能需要配置 pg_hba.conf 文件或者在 `~/.pgpass` 文件中提供连接信息。

## 参考

[1] https://github.com/citusdata/pg_cron

<div class="just-for-fun">
笑林广记 - 武弁夜巡

一武弁夜巡。
有犯夜者，自称书生会课归迟。
武弁曰：“既是书生，且考你一考。”
生请题，武弁思之不得，喝曰：“造化了你，今夜幸而没有题目。”
</div>
