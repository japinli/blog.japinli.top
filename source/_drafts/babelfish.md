# Babelfish

Babelfish 向 PostgreSQL 添加了额外的语法、函数、数据类型等，以帮助从 SQL Server 进行迁移。

## 安装 PostgreSQL

Babelfish 扩展需要 PostgreSQL 内核支持，但是部分支持目前并没有合并到 PostgreSQL 代码库中，因此我们需要使用 Babelfish 提供的 PostgreSQL 版本 [postgresql_modified_for_babelfish][]。

```bash
$ mkdir $HOME/babelfish && cd $HOME/babelfish
$ sudo apt-get install -y pkg-config g++ build-essential bison openjdk-8-jre uuid-dev \
  libossp-uuid-dev libicu-dev libxml2-dev openssl libssl-dev python-dev libreadline-dev
$ git clone https://github.com/babelfish-for-postgresql/postgresql_modified_for_babelfish.git
$ cd postgresql_modified_for_babelfish
$ ./configure --prefix=$HOME/babelfish/pg --enable-debug --enable-cassert --with-libxml \
  --with-uuid=ossp --with-icu --with-openssl
$ make && make install
$ (cd contrib && make && make install)
```

## 安装 ANTLR

`babelfishpg_tsql` 包含一个由 ANTLR 生成的解析器，它依赖于 cmake 和 `antlr4-cpp-runtime-4.9.3`。

```bash
$ cd $HOME/babelfish
$ wget https://github.com/Kitware/CMake/releases/download/v3.20.6/cmake-3.20.6-linux-x86_64.sh
$ sh cmake-3.20.6-linux-x86_64.sh
$ git clone https://github.com/babelfish-for-postgresql/babelfish_extensions.git
$ sudo cp $(find . -name antlr-4.9.3-complete.jar) /usr/local/lib/
$ wget http://www.antlr.org/download/antlr4-cpp-runtime-4.9.3-source.zip
$ unzip -d antlr4 antlr4-cpp-runtime-4.9.3-source.zip
$ cd antlr4
$ mkdir build && cd build
$ cmake .. -DANTLR_JAR_LOCATION=/usr/local/lib/antlr-4.9.3-complete.jar \
  -DCMAKE_INSTALL_PREFIX=/usr/local -DWITH_DEMO=True
$ make && sudo make install
$ cp /usr/local/lib/libantlr4-runtime.so.4.9.3 $HOME/babelfish/pg/lib/
```

## 编译 Babelfish

在编译 Babelfish 扩展之前，需要配置相关环境变量，如 `pg_config` 路径、PostgreSQL 源码位置，cmake 路径。

```bash
$ export PG_CONFIG=$HOME/babelfish/pg/bin/pg_config
$ export PG_SRC=$HOME/babelfish/postgresql_modified_for_babelfish
$ export cmake=$HOME/cmake-3.20.6-linux-x86_64/bin/cmake
```

接着，编译 Babelfish 插件。

```bash
$ (cd contrib/babelfishpg_money && make install)
$ (cd contrib/babelfishpg_common && make install)
$ (cd contrib/babelfishpg_tds && make install)
$ (cd contrib/babelfishpg_tsql && make install)

$ for dir in $(ls -d contrib/babelfishpg_*); do (cd $dir && make install) done
```

## 安装 SQLCMD

接下来，需要安装 SQL Server 的命令行工具。

```bash
$ curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
$ curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
$ sudo apt-get update
$ sudo apt-get install mssql-tools18 unixodbc-dev
$ export PATH=/opt/mssql-tools18/bin:$PATH
```

## 测试

创建证书。

```bash
$ openssl req -new -x509 -days 365 -nodes -text -out server.crt \
  -keyout server.key -subj "/CN=dbhost.yourdomain.com"
$ chmod og-rwx server.key
```

```bash
$ initdb -D tdb
$ cat <<EOF >> tdb/postgresql.auto.conf
listen_addresses = '*'
shared_preload_libraries = 'babelfishpg_tds'
ssl = 'on'
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
EOF
$ cp server.{key,crt} tdb/
$ cat <<EOF >> tdb/pg_hba.conf
host	all		all		10.0.0.0/8		trust
hostssl	all		all		10.0.0.0/8		trust
EOF
$ pg_ctl -l log -D tdb start
$ cat <<EOF > babelfish.sql
CREATE USER babelfish_user WITH CREATEDB CREATEROLE PASSWORD '12345678' INHERIT;
DROP DATABASE IF EXISTS babelfish_db;
CREATE DATABASE babelfish_db OWNER babelfish_user;
\c babelfish_db
CREATE EXTENSION IF NOT EXISTS "babelfishpg_tds" CASCADE;
GRANT ALL ON SCHEMA sys to babelfish_user;
ALTER SYSTEM SET babelfishpg_tsql.database_name = 'babelfish_db';
ALTER DATABASE babelfish_db SET babelfishpg_tsql.migration_mode = 'single-db';
SELECT pg_reload_conf();
CALL SYS.INITIALIZE_BABELFISH('babelfish_user');
EOF
$ psql postgres -f babelfish.sql
```

```bash
$ sqlcmd -N -C -S localhost -U babelfish_user -P 12345678
1> SELECT * FROM pg_stat_ssl WHERE pid = @@spid
2> go
```

## 备注

1. 目前 babelfish 的编译不支持 VPATH，因此，在编译 postgresql_modified_for_babelfish 的时候需要在源码路径下编译。

## 参考

[1]: https://github.com/babelfish-for-postgresql
[2]: https://learn.microsoft.com/en-us/sql/linux/quickstart-install-connect-red-hat

[postgresql_modified_for_babelfish]: https://github.com/babelfish-for-postgresql/postgresql_modified_for_babelfish
