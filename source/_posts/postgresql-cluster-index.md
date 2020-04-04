---
title: "PostgreSQL 聚簇索引"
date: 2019-11-27 21:06:33 +0800
category: Database
tags:
  - PostgreSQL
---

聚簇索引是按照数据存放的物理位置为顺序的，每个表仅有一个聚簇索引。

MySQL 数据库中的 InnoDB 引擎中的主键即为聚簇索引，当我们在表上定义主键时，InnoDB 会将其用作聚簇索引，如果表上没有定义主键，那么 InnoDB 将会使用第一个全不为空的唯一性索引作为聚簇索引，如果表上即没有主键、也没有唯一性索引，那么 InnoDB 将会自动生成一个隐藏的 `GEN_CLUST_INDEX` 索引作为聚簇索引。

PostgreSQL 在创建表时并不能指定聚簇索引，但是我们可以通过 `CLUSTER` 来创建聚簇索引，本文主要介绍 PostgreSQL 数据库中的聚簇索引。

<!-- more -->

我们首先建立一个数据表，如下所示：

``` plpgsql
postgres=# CREATE TABLE account (id integer, nickname text, password text);
CREATE TABLE
postgres=# \d account
               Table "public.account"
  Column  |  Type   | Collation | Nullable | Default
----------+---------+-----------+----------+---------
 id       | integer |           |          |
 nickname | text    |           |          |
 password | text    |           |          |
```

随后，我们随机插入一些数据。

``` plpgsql
postgres=# INSERT INTO account SELECT id, 'user' || id::text, md5(id::text)
postgres-# FROM generate_series(1, 100) id ORDER BY random();
INSERT 0 100
postgres=# SELECT ctid, * FROM account LIMIT 20;
  ctid  | id | nickname |             password
--------+----+----------+----------------------------------
 (0,1)  | 85 | user85   | 3ef815416f775098fe977004015c6193
 (0,2)  | 22 | user22   | b6d767d2f8ed5d21a44b0e5886680cb9
 (0,3)  | 43 | user43   | 17e62166fc8586dfa4d1bc0e1742c08b
 (0,4)  | 89 | user89   | 7647966b7343c29048673252e490f736
 (0,5)  | 75 | user75   | d09bf41544a3365a46c9077ebb5e35c3
 (0,6)  | 81 | user81   | 43ec517d68b6edd3015b3edc9a11367b
 (0,7)  | 91 | user91   | 54229abfcfa5649e7003b83dd4755294
 (0,8)  | 65 | user65   | fc490ca45c00b1249bbe3554a4fdf6fb
 (0,9)  | 67 | user67   | 735b90b4568125ed6c3f678819b6e058
 (0,10) | 11 | user11   | 6512bd43d9caa6e02c990b0a82652dca
 (0,11) | 72 | user72   | 32bb90e8976aab5298d5da10fe66f21d
 (0,12) | 36 | user36   | 19ca14e7ea6328a42e0eb13d585e4c22
 (0,13) | 69 | user69   | 14bfa6bb14875e45bba028a21ed38046
 (0,14) | 32 | user32   | 6364d3f0f495b6ab9dcf8d3b5c6e0b01
 (0,15) | 17 | user17   | 70efdf2ec9b086079795c442636b55fb
 (0,16) | 15 | user15   | 9bf31c7ff062936a96d3c8bd1f8f2ff3
 (0,17) | 46 | user46   | d9d4f495e875a2e075a1a4a6e1b9770f
 (0,18) | 83 | user83   | fe9fc289c3ff0af142b6d3bead98a923
 (0,19) | 82 | user82   | 9778d5d219c5080b9a6a17bef029331c
 (0,20) | 20 | user20   | 98f13708210194c475687be6106a3b84
(20 rows)
```

PostgreSQL 在创建表的时候无法指定聚簇索引，我们必须使用 `CLUSTER` 命令来创建聚簇索引，此外，我们在初次创建聚簇索引时，需要指定使用的索引名。例如：

``` plpgsql
postgres=# CLUSTER account;
ERROR:  there is no previously clustered index for table "account"
```

上面我们没有指定索引名，因为我们还没有对其创建索引。接下来，我们在 `accout` 表上创建一个索引：

``` plpgsql
postgres=# CREATE INDEX account_id_idx ON account(id);
CREATE INDEX
postgres=# SELECT ctid, * FROM account LIMIT 20;
  ctid  | id | nickname |             password
--------+----+----------+----------------------------------
 (0,1)  | 85 | user85   | 3ef815416f775098fe977004015c6193
 (0,2)  | 22 | user22   | b6d767d2f8ed5d21a44b0e5886680cb9
 (0,3)  | 43 | user43   | 17e62166fc8586dfa4d1bc0e1742c08b
 (0,4)  | 89 | user89   | 7647966b7343c29048673252e490f736
 (0,5)  | 75 | user75   | d09bf41544a3365a46c9077ebb5e35c3
 (0,6)  | 81 | user81   | 43ec517d68b6edd3015b3edc9a11367b
 (0,7)  | 91 | user91   | 54229abfcfa5649e7003b83dd4755294
 (0,8)  | 65 | user65   | fc490ca45c00b1249bbe3554a4fdf6fb
 (0,9)  | 67 | user67   | 735b90b4568125ed6c3f678819b6e058
 (0,10) | 11 | user11   | 6512bd43d9caa6e02c990b0a82652dca
 (0,11) | 72 | user72   | 32bb90e8976aab5298d5da10fe66f21d
 (0,12) | 36 | user36   | 19ca14e7ea6328a42e0eb13d585e4c22
 (0,13) | 69 | user69   | 14bfa6bb14875e45bba028a21ed38046
 (0,14) | 32 | user32   | 6364d3f0f495b6ab9dcf8d3b5c6e0b01
 (0,15) | 17 | user17   | 70efdf2ec9b086079795c442636b55fb
 (0,16) | 15 | user15   | 9bf31c7ff062936a96d3c8bd1f8f2ff3
 (0,17) | 46 | user46   | d9d4f495e875a2e075a1a4a6e1b9770f
 (0,18) | 83 | user83   | fe9fc289c3ff0af142b6d3bead98a923
 (0,19) | 82 | user82   | 9778d5d219c5080b9a6a17bef029331c
 (0,20) | 20 | user20   | 98f13708210194c475687be6106a3b84
(20 rows)
```

从上面可以看到，创建索引之后，数据的物理位置并没有发生变化。现在我们使用 `account_id_idx` 作为 `account` 表的聚簇索引，如下所示：

``` plpgsql
postgres=# CLUSTER account USING account_id_idx;
CLUSTER
postgres=# SELECT ctid, * FROM account LIMIT 20;
  ctid  | id | nickname |             password
--------+----+----------+----------------------------------
 (0,1)  |  1 | user1    | c4ca4238a0b923820dcc509a6f75849b
 (0,2)  |  2 | user2    | c81e728d9d4c2f636f067f89cc14862c
 (0,3)  |  3 | user3    | eccbc87e4b5ce2fe28308fd9f2a7baf3
 (0,4)  |  4 | user4    | a87ff679a2f3e71d9181a67b7542122c
 (0,5)  |  5 | user5    | e4da3b7fbbce2345d7772b0674a318d5
 (0,6)  |  6 | user6    | 1679091c5a880faf6fb5e6087eb1b2dc
 (0,7)  |  7 | user7    | 8f14e45fceea167a5a36dedd4bea2543
 (0,8)  |  8 | user8    | c9f0f895fb98ab9159f51fd0297e236d
 (0,9)  |  9 | user9    | 45c48cce2e2d7fbdea1afc51c7c6ad26
 (0,10) | 10 | user10   | d3d9446802a44259755d38e6d163e820
 (0,11) | 11 | user11   | 6512bd43d9caa6e02c990b0a82652dca
 (0,12) | 12 | user12   | c20ad4d76fe97759aa27a0c99bff6710
 (0,13) | 13 | user13   | c51ce410c124a10e0db5e4b97fc2af39
 (0,14) | 14 | user14   | aab3238922bcc25a6f606eb525ffdc56
 (0,15) | 15 | user15   | 9bf31c7ff062936a96d3c8bd1f8f2ff3
 (0,16) | 16 | user16   | c74d97b01eae257e44aa9d5bade97baf
 (0,17) | 17 | user17   | 70efdf2ec9b086079795c442636b55fb
 (0,18) | 18 | user18   | 6f4922f45568161a8cdf4ad2299f6d23
 (0,19) | 19 | user19   | 1f0e3dad99908345f7439f8ffabdffc4
 (0,20) | 20 | user20   | 98f13708210194c475687be6106a3b84
(20 rows)
```

从上面可以看到，数据的物理位置发生了变化，数据的物理位置与索引相同。虽然，我们对 `account` 表创建了聚簇索引，但是在新插入数据时，PostgreSQL 并不会维护索引的正确性（即后续插入的数据并不是按照聚簇索引的顺序在物理上排序），我们需要再次使用 `CLUSTER` 命令来维护聚簇索引的正确性。

下面的示例展示了 PostgreSQL 在创建聚簇索引后再次插入数据后，数据的物理顺序，并再次进行 `CLUSTER` 后的物理顺序。

``` plpgsql
postgres=# INSERT INTO account SELECT id, 'test'||id::text, md5(id::text)
postgres-# FROM generate_series(200, 300) id ORDER BY random();
INSERT 0 101
postgres=# SELECT ctid, * FROM account WHERE nickname ~ 'test' LIMIT 20;
  ctid   | id  | nickname |             password
---------+-----+----------+----------------------------------
 (0,101) | 296 | test296  | d296c101daa88a51f6ca8cfc1ac79b50
 (0,102) | 292 | test292  | 1700002963a49da13542e0726b7bb758
 (0,103) | 208 | test208  | 091d584fced301b442654dd8c23b3fc9
 (0,104) | 210 | test210  | 6f3ef77ac0e3619e98159e9b6febf557
 (0,105) | 240 | test240  | 335f5352088d7d9bf74191e006d8e24c
 (0,106) | 211 | test211  | eb163727917cbba1eea208541a643e74
 (0,107) | 265 | test265  | e56954b4f6347e897f954495eab16a88
 (1,1)   | 269 | test269  | 06138bc5af6023646ede0e1f7c1eac75
 (1,2)   | 222 | test222  | bcbe3365e6ac95ea2c0343a2395834dd
 (1,3)   | 252 | test252  | 03c6b06952c750899bb03d998e631860
 (1,4)   | 230 | test230  | 6da9003b743b65f4c0ccd295cc484e57
 (1,5)   | 282 | test282  | 6a9aeddfc689c1d0e3b9ccc3ab651bc5
 (1,6)   | 235 | test235  | 577ef1154f3240ad5b9b413aa7346a1e
 (1,7)   | 213 | test213  | 979d472a84804b9f647bc185a877a8b5
 (1,8)   | 249 | test249  | 077e29b11be80ab57e1a2ecabb7da330
 (1,9)   | 200 | test200  | 3644a684f98ea8fe223c713b77189a77
 (1,10)  | 267 | test267  | eda80a3d5b344bc40f3bc04f65b7a357
 (1,11)  | 247 | test247  | 3cec07e9ba5f5bb252d13f5f431e4bbb
 (1,12)  | 228 | test228  | 74db120f0a8e5646ef5a30154e9f6deb
 (1,13)  | 262 | test262  | 36660e59856b4de58a219bcf4e27eba3
(20 rows)

postgres=# CLUSTER account ;
CLUSTER
postgres=# SELECT ctid, * FROM account WHERE nickname ~ 'test' LIMIT 20;
  ctid   | id  | nickname |             password
---------+-----+----------+----------------------------------
 (0,101) | 200 | test200  | 3644a684f98ea8fe223c713b77189a77
 (0,102) | 201 | test201  | 757b505cfd34c64c85ca5b5690ee5293
 (0,103) | 202 | test202  | 854d6fae5ee42911677c739ee1734486
 (0,104) | 203 | test203  | e2c0be24560d78c5e599c2a9c9d0bbd2
 (0,105) | 204 | test204  | 274ad4786c3abca69fa097b85867d9a4
 (0,106) | 205 | test205  | eae27d77ca20db309e056e3d2dcd7d69
 (0,107) | 206 | test206  | 7eabe3a1649ffa2b3ff8c02ebfd5659f
 (1,1)   | 207 | test207  | 69adc1e107f7f7d035d7baf04342e1ca
 (1,2)   | 208 | test208  | 091d584fced301b442654dd8c23b3fc9
 (1,3)   | 209 | test209  | b1d10e7bafa4421218a51b1e1f1b0ba2
 (1,4)   | 210 | test210  | 6f3ef77ac0e3619e98159e9b6febf557
 (1,5)   | 211 | test211  | eb163727917cbba1eea208541a643e74
 (1,6)   | 212 | test212  | 1534b76d325a8f591b52d302e7181331
 (1,7)   | 213 | test213  | 979d472a84804b9f647bc185a877a8b5
 (1,8)   | 214 | test214  | ca46c1b9512a7a8315fa3c5a946e8265
 (1,9)   | 215 | test215  | 3b8a614226a953a8cd9526fca6fe9ba5
 (1,10)  | 216 | test216  | 45fbc6d3e05ebd93369ce542e8f2322d
 (1,11)  | 217 | test217  | 63dc7ed1010d3c3b8269faf0ba7491d4
 (1,12)  | 218 | test218  | e96ed478dab8595a7dbda4cbcbee168f
 (1,13)  | 219 | test219  | c0e190d8267e36708f955d7ab048990d
(20 rows)
```

## 参考

[1] https://www.guru99.com/clustered-vs-non-clustered-index.html
[2] https://dev.mysql.com/doc/refman/5.7/en/innodb-index-types.html
