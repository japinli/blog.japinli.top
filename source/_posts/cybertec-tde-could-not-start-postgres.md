---
title: "Cybertec TDE 无法启动 PostgreSQL 数据库"
date: 2023-12-09 21:19:40 +0800
categories: 数据库
tags:
  - PostgreSQL
  - TDE
---

{% asset_img cover.png %}

最近 [Cybertec 发布了新的 TDE 解决方案](https://github.com/cybertec-postgresql/postgresql)，通过在制作安装包时打补丁的方式添加数据库透明加解密功能，不得不说这种方式比之前的引入到整个代码库中要清晰的多。

<!--此外，原有的仓库则在 Github 上无法访问，从而导致很多 issue 信息无法查看。-->

<!--more-->

## 打补丁

Cybertec 提供了 PostgreSQL 12 到 15 的透明加解密补丁，我采用 15 的版本进行实验，在 `debian/patches` 目录下有一个名为 `10-cybertec-tde.patch` 的补丁文件，该文件包含了所有关于透明加解密的功能。

接下来需要确定补丁基于那个 PostgreSQL 提交生产的，在 `10-cybertec-tde.patch` 我们可以看到如下内容，这说明 PG 15 的透明加解密是基于 PG 15.1 生成的补丁。

```diff
diff --git a/configure b/configure
index 2270417f8e..f06fc12cfb 100755
--- a/configure
+++ b/configure
@@ -580,12 +580,12 @@ MFLAGS=
 MAKEFLAGS=

 # Identity of this package.
-PACKAGE_NAME='PostgreSQL'
-PACKAGE_TARNAME='postgresql'
-PACKAGE_VERSION='15.1'
-PACKAGE_STRING='PostgreSQL 15.1'
-PACKAGE_BUGREPORT='pgsql-bugs@lists.postgresql.org'
-PACKAGE_URL='https://www.postgresql.org/'
+PACKAGE_NAME='PostgreSQL-TDE'
+PACKAGE_TARNAME='postgresql-tde'
+PACKAGE_VERSION='15.1_TDE_1.1.2'
+PACKAGE_STRING='PostgreSQL 15.1 TDE 1.1.2'
+PACKAGE_BUGREPORT='bugs-tde@cybertec.at'
+PACKAGE_URL='https://www.cybertec.at/'
```

如果本地有 PostgreSQL 的 git 仓库，可以用如下方式打补丁：

```bash
$ cd postgresql
$ wget https://raw.githubusercontent.com/cybertec-postgresql/postgresql/15tde/debian/patches/10-cybertec-tde.patch
$ git checkout -b 15.1-tde REL_15_1
$ git apply 10-cybertec-tde.patch
```

如果本地没有 PostgreSQL 的 git 参考，可以选择下载 PostgreSQL 的源码的方式打补丁：

```bash
$ wget https://ftp.postgresql.org/pub/source/v15.1/postgresql-15.1.tar.gz
$ tar xf postgresql-15.1.tar.gz
$ cd postgresql-15.1
$ wget https://raw.githubusercontent.com/cybertec-postgresql/postgresql/15tde/debian/patches/10-cybertec-tde.patch
$ patch -p1 < 10-cybertec-tde.patch
```

## 编译安装

常规操作，需要注意的时编译时要带上 `--with-openssl` 选项。

```bash
$ mkdir build && cd build
$ ../configure --prefix=$PWD/tde --with-openssl && make install
$ cat <<EOF > env.sh
export PGHOME=$PWD/tde
export PATH=\$PGHOME/bin:\$PATH
export LD_LIBRARY_PATH=\$PGHOME/lib:\$LD_LIBRARY_PATH
export PGDATA=\$PGHOME/pgdata
export PGPORT=9815
EOF
$ source env.sh
```

为了方便查看使用手册可以编译文档。

```bash
$ make -C doc install
$ $ ls -l tde/share/doc/html/ | head -n 5
total 17568
-rw-rw-r-- 1 japin japin  21420 Dec  8 22:19 acronyms.html
-rw-rw-r-- 1 japin japin  17874 Dec  8 22:19 admin.html
-rw-rw-r-- 1 japin japin   8939 Dec  8 22:19 adminpack.html
-rw-rw-r-- 1 japin japin  26943 Dec  8 22:19 amcheck.html
```
在文档的 33 章有介绍如何使用透明加解密功能。

## Bug 复现

这里的 Bug 出现在从用户输入获取密码的情况，即使用文档中的 `read -sp "Cluster encryption password: "` 这种方式获取密码，如下所示：

```bash
$ initdb -K '(read -sp "Cluster encryption password: " PGENCRPWD; echo $PGENCRPWD | pg_keytool -D %D -w)'
The files belonging to this database system will be owned by user "japin".
This user must also own the server process.

The database cluster will be initialized with locale "en_US.UTF-8".
The default database encoding has accordingly been set to "UTF8".
The default text search configuration will be set to "english".

Data page checksums are disabled.
Data encryption is enabled.

creating directory /home/japin/postgresql-15.1/build/tde/pgdata ... ok
creating subdirectories ... ok
sh: 1: read: Illegal option -s
pg_keytool: error: The password is too short, the minimum length is 8 characters
initdb: error: could not read encryption key from command "(read -sp "Cluster encryption password: " PGENCRPWD; echo $PGENCRPWD | pg_keytool -D /home/japin/postgresql-15.1/build/tde/pgdata -w)"
initdb: removing data directory "/home/japin/postgresql-15.1/build/tde/pgdata"
```

这是由于 `sh` 的 `read` 命令不执行 `-s` 选项（该选项是禁止回显，即不显示我们输入的内容），我们可以稍作调整：

```bash
$ rm -rf $PGDATA
$ initdb -K '(read -p "Cluster encryption password: " PGENCRPWD; echo $PGENCRPWD | pg_keytool -D %D -w)'
The files belonging to this database system will be owned by user "japin".
This user must also own the server process.

The database cluster will be initialized with locale "en_US.UTF-8".
The default database encoding has accordingly been set to "UTF8".
The default text search configuration will be set to "english".

Data page checksums are disabled.
Data encryption is enabled.

creating directory /home/japin/postgresql-15.1/build/tde/pgdata ... ok
creating subdirectories ... ok
Cluster encryption password: helloworld
selecting dynamic shared memory implementation ... posix
selecting default max_connections ... 100
selecting default shared_buffers ... 128MB
selecting default time zone ... Asia/Shanghai
creating configuration files ... ok
running bootstrap script ... ok
performing post-bootstrap initialization ... ok
syncing data to disk ... ok

initdb: warning: enabling "trust" authentication for local connections
initdb: hint: You can change this by editing pg_hba.conf or using the option -A, or --auth-local and --auth-host, the next time you run initdb.

Success. You can now start the database server using:

    pg_ctl -D /home/japin/postgresql-15.1/build/tde/pgdata -l logfile start
```

可以看到在我们输入密码之后，数据库初始化成功了，我们可以看到初始化完成之后 `-K` 选项的内容被写入到 `postgresql.conf` 配置文件，这样可以避免每次启动的时候指定 `-K` 选项。

```bash
$ grep 'encryption_key_command' $PGDATA/postgresql.conf
encryption_key_command = '(read -p "Cluster encryption password: " PGENCRPWD; echo $PGENCRPWD | pg_keytool -D %D -w)'
```

现在我们尝试启动数据库：

```bash
$ pg_ctl start
2023-12-08 22:31:16.140 CST [1018742] LOG:  starting PostgreSQL 15.1_TDE_1.1.2 on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0, 64-bit
2023-12-08 22:31:16.141 CST [1018742] LOG:  listening on IPv4 address "127.0.0.1", port 9815
2023-12-08 22:31:16.146 CST [1018742] LOG:  listening on Unix socket "/tmp/.s.PGSQL.9815"
pg_keytool: error: The password is too short, the minimum length is 8 characters
2023-12-08 22:31:16.164 CST [1018742] FATAL:  could not read encryption key from command "(read -p "Cluster encryption password: " PGENCRPWD; echo $PGENCRPWD | pg_keytool -D /home/japin/postgresql-15.1/build/tde/pgdata -w)"
2023-12-08 22:31:16.171 CST [1018742] LOG:  database system is shut down
 stopped waiting
pg_ctl: could not start server
Examine the log output.
```

这里的错误提示是 `The password is too short, the minimum length is 8 characters`，但是我们压根就没有输入密码，为啥会是密码太短了？

## 分析

通过分析 `pg_ctl` 的代码，我们可以看到在 `start_postmaster()` 函数中启动 `postgres` 进程时采用了输入重定向，

```c
static pgpid_t
start_postmaster(void)
{
	[...]

        /*
         * Since there might be quotes to handle here, it is easier simply to pass
         * everything to a shell to process them.  Use exec so that the postmaster
         * has the same PID as the current child process.
         */
        if (log_file != NULL)
                cmd = psprintf("exec \"%s\" %s%s < \"%s\" >> \"%s\" 2>&1",
                                           exec_path, pgdata_opt, post_opts,
                                           DEVNULL, log_file);
        else
                cmd = psprintf("exec \"%s\" %s%s < \"%s\" 2>&1",
                                           exec_path, pgdata_opt, post_opts, DEVNULL);
	[...]
}
```

这就导致在有输入需要的时候，进程会从 `/dev/null` 设备获取内容，从而导致失败，我们可以删除输入重定向来验证。

```diff
$ cat 11-pg_ctl-tde.patch
diff --git a/src/bin/pg_ctl/pg_ctl.c b/src/bin/pg_ctl/pg_ctl.c
index e26b065f50..59b1a7a527 100644
--- a/src/bin/pg_ctl/pg_ctl.c
+++ b/src/bin/pg_ctl/pg_ctl.c
@@ -520,12 +520,12 @@ start_postmaster(void)
 	 * has the same PID as the current child process.
 	 */
 	if (log_file != NULL)
-		cmd = psprintf("exec \"%s\" %s%s < \"%s\" >> \"%s\" 2>&1",
+		cmd = psprintf("exec \"%s\" %s%s >> \"%s\" 2>&1",
 					   exec_path, pgdata_opt, post_opts,
-					   DEVNULL, log_file);
+					   log_file);
 	else
-		cmd = psprintf("exec \"%s\" %s%s < \"%s\" 2>&1",
-					   exec_path, pgdata_opt, post_opts, DEVNULL);
+		cmd = psprintf("exec \"%s\" %s%s 2>&1",
+					   exec_path, pgdata_opt, post_opts);

 	(void) execl("/bin/sh", "/bin/sh", "-c", cmd, (char *) NULL);

$ patch -p1 <11-pg_ctl-tde.patch
$ cd build && make install
```

现在我们再次尝试启动数据库：

```bash
$ pg_ctl start
2023-12-08 22:49:35.783 CST [1019738] LOG:  starting PostgreSQL 15.1_TDE_1.1.2 on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0, 64-bit
2023-12-08 22:49:35.784 CST [1019738] LOG:  listening on IPv4 address "127.0.0.1", port 9815
2023-12-08 22:49:35.793 CST [1019738] LOG:  listening on Unix socket "/tmp/.s.PGSQL.9815"
Cluster encryption password: waiting for server to start.....he.llowor.ld
.2023-12-08 22:49:40.808 CST [1019749] LOG:  database system was shut down at 2023-12-08 22:27:04 CST
2023-12-08 22:49:40.816 CST [1019738] LOG:  database system is ready to accept connections
 done
server started
```

可以看到 `Cluster encryption password: ` 提示符出来了，我们可以输入密码了，但是由于 `pg_ctl` 进程同时也在显标准输出打印字符，因此可以看到比较混乱的结果，如上所示 `he.llowor.ld`，但这并不影响密码的获取。如果您尝试使用 `-l log` 选项，则不会显示提示符，因为它会被重定向到日志文件中。

## 参考

[1] https://github.com/cybertec-postgresql/postgresql

<div class="just-for-fun">
笑林广记 - 善屁

有善屁者，往铁匠铺打铁锛，方讲价，连撒十余屁。
匠曰：“汝屁直恁多，若能连撒百个，我当白送一把铁锛与你。”
其人便放百个。匠只得打成送之。临出门又撒数个屁。
乃谓匠曰：“算不得许多，这几个小屁，乞我几只钯头钉罢。”
</div>
