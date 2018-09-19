---
title: 列存数据库 cstore_fdw 入门
date: 2018-09-18 21:40:00
category: Database
tags: 
  - cstore_fdw
  - columnar store
  - PostgreSQL
---

Cstore_fdw 是 Citus Data 开发的一款开放源码的 PostgreSQL 列存扩展插件。列存储在数据批量导入的分析场景能够提供更好的性能。Cstore_fdw 通过只读取磁盘上相关的列数据来提升性能，同时，由于每列的数据来自同一个域，因此更利于数据压缩，cstore_fdw 提供 6~10 倍的数据压缩能力，从而减小了对磁盘存储的需求。

Cstore_fdw 采用 Optimized Row Columnar (ORC) 格式作为其数据的物理存储格式。ORC 优化了 Facebook 的 RCFile 存储格式，并具有以下优点：

* 压缩 (Compression) - 大约减少了 2~4 倍的内存和磁盘存储空间。易于扩展以支持不同的编码。
* 列投影 (Column Projections) - 仅仅读取与该查询有关的数据列，提高了 I/O 效率。
* 跳跃索引 (Skip Indexes) - 为每个行组 (Row Groups) 存储其最大值和最小值，并利用他们来跳过不相关的数据行。

除此之外，cstore_fdw 使用了 PostgreSQL 的数据类型和 fdw API 编程接口，这样做的好处有以下几点：

* 支持 40+ 的 PostgreSQL 数据类型，用户也可以创建并使用新的类型。
* 统计信息收集，PostgreSQL 使用这些统计信息来评估不同的查询计划并选择最优查询计划的来执行。
* 配置简单，用户只需要创建外部表并导入数据，之后就可以使用 SQL 进行查询。

<!-- more -->

### 编译

Cstore_fdw 依赖 protobuf-c 来序列化和反序列化表的元数据信息，因此需要先安装 protobuf-c 套件：

``` shell
$ sudo apt-get install protobuf-c-compiler libprotobuf-c-dev
```

首先，编译安装 PostgreSQL 数据库，命令如下：

``` shell
$ wget https://ftp.postgresql.org/pub/source/v9.3.24/postgresql-9.3.24.tar.gz
$ tar xf postgresql-9.3.24.tar.gz
$ cd postgresql-9.3.24
$ ./configure --prefix=/home/postgres/postgresql-9.3.24/Debug --enable-debug --enable-cassert CFLAGS='-O0 -g'
$ make && make install
$ cd Debug
$ cat <<END >pg-9.3.24.env
export PGHOME=$PWD
export PGDATA=\$PGHOME/pgdata
export PATH=\$PGHOME/bin:\$PATH
export LD_LIBRARY_PATH=\$PGHOME/lib:\$LD_LIBRARY_PATH
END
```

为了使用方便，我将 PostgreSQL 的环境变量配置到了 pg-9.3.24.env 文件中，当需要使用是只需要 source 以下即可。
接着，编译安装 cstore_fdw 插件，命令如下：

``` shell
$ git clone https://github.com/citusdata/cstore_fdw
$ cd cstore_fdw
$ . /path/to/pg-9.3.24.env
$ make && make install
```

**备注：** Cstore_fdw 支持 PostgreSQL 9.3, 9.4, 9.5, 9.6 和 10 的版本，更早的版本则不支持。

### 使用

在使用 cstore_fdw 之前，我们需要将他添加到 postgresql.conf 文件的 shared_preload_libraries 中，并重启 PostgreSQL 数据库。

```
shared_preload_libraries = 'cstore_fdw' # (change requires restart)
```

以下四个选项可以在创建 cstore 外部表的时候指定：

* filename (可选) - 存放列存表数据的绝对路径，如果没有指定该选项，那么 cstore_fdw 则采用默认的 $PGHOME/cstore_fdw 来存储列存表数据。如果为该参数指定了值，则使用该值作为前缀来存储列存表数据信息。例如，当指定的 filename 值为 /cstore_fdw/my_table，那么 cstore_fdw 将使用 /cstore_fdw/my_table 来存储列存表用户数据，同时，使用 /cstore_fdw/my_table.footer 来存储列存表的元数据信息。
* compression (可选) - 该参数用于指定用户数据的压缩算法，目前仅支持 none 和 pglz 两个值，即不压缩或者使用 pglz 压缩算法进行压缩，默认值为 none。
* stripe_row_count (可选) - 该参数指定每个 stripe 中行记录数，默认值为 150000。该值越小，加载数据或者查询时使用的内存也就越小，相反，其性能也就越低。
* block_row_count (可选) - 该参数指定每个列数据块 (column block) 中的行记录数，默认为 10000。Cstore_fdw 压缩数据、创建跳跃索引以及磁盘读取时都是以块 (block) 为最小单元。该值越大，则利用数据压缩，并可以减少磁盘读取的次数量，然而，这将影响到跳过不相关的数据块的概率。

Cstore_fdw 提供了两种方式用于向其导入数据：

* 使用 `COPY` 命令将文件、程序或者标准输入中导入数据；
* 使用 `INSERT INTO cstore_table SELECT ...` 语法从其他表导入数据。

我们可以使用 `ANALYZE` 命令收集列存表的统计信息，从而帮助优化器选择最优的查询计划。

**注意：** Cstore_fdw 目前并不支持使用 `UPDATE` 或 `DELETE` 命令来对表进行更新。同样，他也不支持单条记录的插入，这是由于每次导入数据都会形成至少一个数据块，若是支持单条记录插入，那么每个 `INSERT` 命令插入一条纪律，将导致数据块过多从而影响性能，为此，Cstore_fdw 不支持单条记录的插入。


### 示例

为了展示 cstore_fdw，我们可以使用官方给出的测试数据用以验证。

``` shell
$ wget http://examples.citusdata.com/customer_reviews_1998.csv.gz
$ wget http://examples.citusdata.com/customer_reviews_1999.csv.gz

$ gzip -d customer_reviews_1998.csv.gz
$ gzip -d customer_reviews_1999.csv.gz
```

接着初始化数据库并修改 `shared_preload_libraries` 参数，然后启动并登陆到 postgres 数据库，然后执行下面的命令创建列存储外部表：

``` psql
-- 在首次安装完成之后加载 cstore_fdw 插件
CREATE EXTENSION cstore_fdw;

-- 创建服务对象
CREATE SERVER cstore_server FOREIGN DATA WRAPPER cstore_fdw;

-- 创建外部表
CREATE FOREIGN TABLE customer_reviews
(
    customer_id TEXT,
    review_date DATE,
    review_rating INTEGER,
    review_votes INTEGER,
    review_helpful_votes INTEGER,
    product_id CHAR(10),
    product_title TEXT,
    product_sales_rank BIGINT,
    product_group TEXT,
    product_category TEXT,
    product_subcategory TEXT,
    similar_product_ids CHAR(10)[]
)
SERVER cstore_server
OPTIONS(compression 'pglz');
```

最后，我们使用 `COPY` 命令导入数据到列存储外部表中，并使用 `ANALYZE` 命令收集统计信息。

``` psql
COPY customer_reviews FROM '/path/to/customer_reviews_1998.csv' WITH CSV;
COPY customer_reviews FROM '/path/to/customer_reviews_1999.csv' WITH CSV;
```

在执行完上述操作之后，我们就可以在列存表上执行查询操作了。例如，执行下面的查询：

``` psql
-- 查找特定客户在 1998 年对 Dune 系列所做的所有评论
SELECT
    customer_id, review_date, review_rating, product_id, product_title
FROM
    customer_reviews
WHERE
    customer_id ='A27T7HVDXA3K2A' AND
    product_title LIKE '%Dune%' AND
    review_date >= '1998-01-01' AND
    review_date <= '1998-12-31';

-- 我们是否有书的标题长度和评论评级之间的相关性？
SELECT
    width_bucket(length(product_title), 1, 50, 5) title_length_bucket,
    round(avg(review_rating), 2) AS review_average,
    count(*)
FROM
   customer_reviews
WHERE
    product_group = 'Book'
GROUP BY
    title_length_bucket
ORDER BY
    title_length_bucket;
```

### 卸载

在卸载 cstore_fdw 之前，我们需要删除所有的 cstore 列存表、server 和扩展：

``` psql
DROP FOREIGN TABLE customer_reviews;
DROP SERVER cstore_server;
DROP EXTENSION cstore_fds;
```

Cstore_fdw 会自动的创建目录来存储列存相关的数据，我们可以执行下面的命令来删除：

``` shell
$ rm -rf $PGDATA/cstore_fdw
```

注意，上面给出的是 cstore_fdw 的默认路径，若在建表的时候指定了 filename，其位置可能不同。

此外，别忘了将 postgresql.conf 文件中 `shared_preload_libraries` 中的 `cstore_fdw` 移除掉。最后，我们可以到 cstore_fdw 的源码目录执行 `make uninstall` 删除已安装的 cstore_fdw 相关的文件。

### 参考

[1] https://github.com/citusdata/cstore_fdw
