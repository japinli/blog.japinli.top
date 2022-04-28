---
title: "【译】PostgreSQL 中 hstore 简介"
date: 2022-04-28 21:39:09 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
  - PG Casts
---

在本期节目中，我将演示如何在 PostgreSQL 数据库中使用 hstore 数据类型。我们将创建一个 hstore 列，并用一些数据来填充它，随后在它上面执行查询和删除操作。

<!--more-->

假设我们有一个应用程序，用户可以在不通的设备上、从多个位置登录。为了更好的了解我们的用户，我们希望收集每次用户登录的时间和 IP 地址。我们需要存储这些数据，但不会使用许多新的列来污染 `users` 表。我们不关心数据是否是关系数据，也不会经常使用它。

PostgreSQL 为这种情况提供了一种非关系型数据类型，hstore。hstore 是一组由逗号分割的零个或多个键值对。键值对都是文本字符串。

首先，我们看看 `users` 表。

```sql
\d users
```

```
                                   Table "public.users"
   Column   |       Type        | Collation | Nullable |              Default
------------+-------------------+-----------+----------+-----------------------------------
 id         | integer           |           | not null | nextval('users_id_seq'::regclass)
 first_name | character varying |           | not null |
 last_name  | character varying |           | not null |
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
```

注：您可以使用下面的 SQL 语句创建 `users` 表，并插入一条记录，从而获得与视频相同的表结构和数据。

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  first_name VARCHAR NOT NULL,
  last_name VARCHAR NOT NULL
);

INSERT INTO users (first_name, last_name) VALUES ('Jack', 'Donaghy');
```

现在我们有一个用户。

```sql
TABLE users;
```

```
 id | first_name | last_name
----+------------+-----------
  1 | Jack       | Donaghy
(1 row)
```

让我们创建一个 hstore 列来记录会话数据。首先我们需要创建 hstore 插件。

```sql
CREATE EXTENSION hstore;
```

接着我们为 `users` 表新增类型为 `hstore` 的 `session_data` 列。

```sql
ALTER TABLE users ADD COLUMN session_data hstore NOT NULL
  DEFAULT ''::hstore;
```

我们查看一下表结构。

```sql
\d users
```

```
                                    Table "public.users"
    Column    |       Type        | Collation | Nullable |              Default
--------------+-------------------+-----------+----------+-----------------------------------
 id           | integer           |           | not null | nextval('users_id_seq'::regclass)
 first_name   | character varying |           | not null |
 last_name    | character varying |           | not null |
 session_data | hstore            |           | not null | ''::hstore
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
```

现在我们有了 `hstore` 类型的列，接着，我们向其中插入数据。我们的 `Jack` 用户正在登录，让我们捕获他的 IP 和登录时间戳。

hstore 中的每个键都必须是唯一的，因此，对于该功能来说，时间戳是个不错的选择。

```sql
UPDATE users
  SET session_data = session_data || hstore(extract(epoch
  from now())::text, '64.107.86.0')
  WHERE id = 1;
```

让我们看看更新后的数据。

```sql
TABLE users;
```

```
 id | first_name | last_name |            session_data
----+------------+-----------+------------------------------------
  1 | Jack       | Donaghy   | "1650953727.046857"=>"64.107.86.0"
(1 row)
```

Jack 在几秒钟之后再次登录，我们同样记录他的登录信息。

```sql
UPDATE users
  SET session_data = session_data || hstore(extract(epoch
  from now())::text, '74.107.86.0')
  WHERE id = 1;
```

```sql
TABLE users;
```

```
 id | first_name | last_name |                              session_data
----+------------+-----------+------------------------------------------------------------------------
  1 | Jack       | Donaghy   | "1650953727.046857"=>"64.107.86.0", "1650953898.090952"=>"74.107.86.0"
(1 row)
```

使用此数据类型，您可以设置它，然后忘记它。稍后，您可以选择使用 psql 或者 ORM 来查询数据。对于这个问题，我们可以按时间过滤结果，或者搜索特定的 IP 地址。

键值对的删除也很容易。我们只是把这个键作为参数传递给 `delete` 即可。

```sql
UPDATE users SET session_data = delete(session_data, '1650953727.046857');
```

```sql
TABLE users;
```

```
 id | first_name | last_name |            session_data
----+------------+-----------+------------------------------------
  1 | Jack       | Donaghy   | "1650953898.090952"=>"74.107.86.0"
(1 row)
```

这只是 hstore 的一些基本特性而已。

## 拓展

PostgreSQL 提供了多种操作符和函数来处理 hstore 类型的数据，此外，您还可以在 hstore 上建立索引。

### 操作符

我们已经见到了如何构造 hstore 类型，下面我们来看看关于 hstore 的常用操作符。

操作符 `->` 用于获取给定键关联的值，该 key 可以是一个键、也可以是由数组组成的多个键，如果是多个键的话返回数组，如果键在 hstore 中不存在，则返回 `NULL`。

```sql
SELECT 'a=>hello, b=>world'::hstore -> 'a';
```

```
 ?column?
----------
 hello
(1 row)
```

```sql
SELECT 'a=>hello, b=>world'::hstore -> ARRAY['a', 'b'];
```

```
   ?column?
---------------
 {hello,world}
(1 row)
```

```sql
SELECT 'a=>hello, b=>world'::hstore -> ARRAY['a', 'b', 'c'];
```

```
      ?column?
--------------------
 {hello,world,NULL}
(1 row)
```

操作符 `||` 用于连接两个 hstore 对象，上面已经用过了，此处就不在赘述。

操作符 `?` 用于判断指定的键是否在当前的 hstore 对象中存在，它与 `exists()` 函数有相同的作用。

```sql
SELECT
  'a=>hello, b=>world'::hstore ? 'a',
  'a=>hello, b=>world'::hstore ? 'c';
```

```
 ?column? | ?column?
----------+----------
 t        | f
(1 row)
```

```psql
SELECT
  exist('a=>hello, b=>world'::hstore, 'a'),
  exist('a=>hello, b=>world'::hstore, 'c');
```

```
 exist | exist
-------+-------
 t     | f
(1 row)
```

操作符 `?&` 与 `?` 类似，它用于判断指定的键（数组）是否在当前的 hstore 对象中都存在。

```sql
SELECT
  'a=>hello, b=>world'::hstore ?& ARRAY['a', 'b'],
  'a=>hello, b=>world'::hstore ?& ARRAY['a', 'c'];
```

```
 ?column? | ?column?
----------+----------
 t        | f
(1 row)
```

您可以能已经猜到了还有一个 `?|` 操作符，用于判断当前的 hstore 对象是否包含指定的键（数组）中的任何一个。

```sql
SELECT
  'a=>hello, b=>world'::hstore ?| ARRAY['a', 'c'],
  'a=>hello, b=>world'::hstore ?| ARRAY['c', 'd'];
```

```
 ?column? | ?column?
----------+----------
 t        | f
(1 row)
```

hstore 也支持集合操作符。操作符 `@>` 用于判断左边的操作数是否包含右边的操作数，操作符 `<@` 则与之相反，用于判断右边的操作数是否包含左边的操作数。

```sql
SELECT
  'a=>hello, b=>world, c=>aha'::hstore @> 'a=>hello, b=>world'::hstore,
  'a=>hello, b=>world, c=>aha'::hstore @> 'z=>zoom'::hstore,
  'a=>hello'::hstore <@ 'a=>hello, b=>world, c=>aha'::hstore,
  'z=>zoom'::hstore <@ 'a=>hello, b=>world, c=>aha'::hstore;
```

```
 ?column? | ?column? | ?column? | ?column?
----------+----------+----------+----------
 t        | f        | t        | f
(1 row)
```

操作符 `-` 可以用于删除 hstore 对象的键值对，它与 `delete()` 函数有相同的效果 。

```sql
SELECT
  'a=>hello, b=>world, c=>aha'::hstore - 'a'::text,
  'a=>hello, b=>world, c=>aha'::hstore - ARRAY['a', 'b'],
  'a=>hello, b=>world, c=>aha'::hstore - ARRAY['a', 'z'],
  'a=>hello, b=>world, c=>aha'::hstore - 'a=>hello, b=>world'::hstore,
  'a=>hello, b=>world, c=>aha'::hstore - 'a=>hello, z=>zoom'::hstore;
```

```
         ?column?         |  ?column?  |         ?column?         |  ?column?  |         ?column?
--------------------------+------------+--------------------------+------------+--------------------------
 "b"=>"world", "c"=>"aha" | "c"=>"aha" | "b"=>"world", "c"=>"aha" | "c"=>"aha" | "b"=>"world", "c"=>"aha"
(1 row)
```

```sql
SELECT
  delete('a=>hello, b=>world, c=>aha'::hstore, 'a'::text),
  delete('a=>hello, b=>world, c=>aha'::hstore, ARRAY['a', 'b']),
  delete('a=>hello, b=>world, c=>aha'::hstore, ARRAY['a', 'z']),
  delete('a=>hello, b=>world, c=>aha'::hstore, 'a=>hello, b=>world'::hstore),
  delete('a=>hello, b=>world, c=>aha'::hstore, 'a=>hello, z=>zoom'::hstore);
```
ROW(1,3) #= 'f1=>11'::hstore → (11,3)
```
          delete          |   delete   |          delete          |   delete   |          delete
--------------------------+------------+--------------------------+------------+--------------------------
 "b"=>"world", "c"=>"aha" | "c"=>"aha" | "b"=>"world", "c"=>"aha" | "c"=>"aha" | "b"=>"world", "c"=>"aha"
```

操作符 `#=` 与 `populate_record()` 函数类似，但是我没太弄清楚是什么意思:(。

操作符 `%%` 用于将 hstore 转化为键和值的数组，操作符 `%#` 与 `%%` 类似，不同的是 `%#` 将其转换为二维的键值对数组。

```sql
SELECT %% 'a=>hello, b=>world, c=>aha'::hstore, %# 'a=>hello, b=>world, c=>aha'::hstore;
```

```
        ?column?         |           ?column?
-------------------------+-------------------------------
 {a,hello,b,world,c,aha} | {{a,hello},{b,world},{c,aha}}
(1 row)
```

### 函数

`hstore()` 函数用于构造一个 hstore 对象，它包含几种形式。

* `hstore(record)` 将记录或行转换为 hstore 对象。
  ```sql
  SELECT hstore(ROW('hello', 'world'));
  ```
  ```
              hstore
  ------------------------------
   "f1"=>"hello", "f2"=>"world"
  (1 row)
  ```
* `hstore(text[])` 将数组转换为 hstore 对象，可以是一个二维数组。
  ```sql
  SELECT
    hstore(ARRAY['a', 'hello', 'b', 'world']),
	hstore(ARRAY[['a', 'hello'], ['b', 'world']]);
  ```
  ```
             hstore           |           hstore
  ----------------------------+----------------------------
   "a"=>"hello", "b"=>"world" | "a"=>"hello", "b"=>"world"
  (1 row)
  ```
* `hstore(text, text)` 用于构造包含一个键值对的 hstore 对象。
  ```sql
  SELECT hstore('a', 'world');
  ```
  ```
      hstore
  --------------
   "a"=>"world"
  (1 row)
  ```

`akeys()` 函数获取 hstore 对象的所有键，并以数组的形式返回。

```sql
SELECT akeys('a=>hello, b=>world'::hstore);
```
```
 akeys
-------
 {a,b}
(1 row)
```

`skeys()` 函数同样是获取 hstore 对象的所有键，但它是以 setof 的形式返回。

```sql
SELECT skeys('a=>hello, b=>world'::hstore);
```
```
 skeys
-------
 a
 b
(2 rows)
```

与之类似的还有 `avals()` 函数和 `svals()` 函数，您应该知道它们是做什么的了。

```sql
SELECT avals('a=>hello, b=>world'::hstore);
```
```
     avals
---------------
 {hello,world}
(1 row)

```sql
SELECT svals('a=>hello, b=>world'::hstore);
```
```
 svals
-------
 hello
 world
(2 rows)
```

hstore 提供了一系列函数将 hstore 对象转换为特定的类型，这些函数以 `hstore_to` 开始。

* `hstore_to_array()` 将 hstore 对象转换为数组。
  ```sql
  SELECT hstore_to_array('a=>hello, b=>world'::hstore);
  ```
  ```
    hstore_to_array
  -------------------
   {a,hello,b,world}
  (1 row)
  ```
* `hstore_to_matrix()` 将 hstore 对象转换为二维数组。
  ```sql
  SELECT hstore_to_matrix('a=>hello, b=>world'::hstore);
  ```
  ```
     hstore_to_matrix
  -----------------------
   {{a,hello},{b,world}}
  (1 row)
  ```
* `hstore_to_json(), hstore_to_json_loose()` 将 hstore 对象转换为 json 对象。
  ```sql
  SELECT hstore_to_json('"a key"=>1, b=>t, c=>null, d=>12345, e=>012345, f=>1.234, g=>2.345e+4'),
         hstore_to_json_loose('"a key"=>1, b=>t, c=>null, d=>12345, e=>012345, f=>1.234, g=>2.345e+4');
  ```
  ```
                                           hstore_to_json                                          |                                   hstore_to_json_loose
  -------------------------------------------------------------------------------------------------+------------------------------------------------------------------------------------------
   {"b": "t", "c": null, "d": "12345", "e": "012345", "f": "1.234", "g": "2.345e+4", "a key": "1"} | {"b": true, "c": null, "d": 12345, "e": "012345", "f": 1.234, "g": 2.345e+4, "a key": 1}
  (1 row)
  ```
* `hstore_to_jsonb(), hstore_to_jsonb_loose()` 将 hstore 对象转换为 jsonb 对象。
  ```sql
  SELECT hstore_to_jsonb('"a key"=>1, b=>t, c=>null, d=>12345, e=>012345, f=>1.234, g=>2.345e+4'),
         hstore_to_jsonb_loose('"a key"=>1, b=>t, c=>null, d=>12345, e=>012345, f=>1.234, g=>2.345e+4');
  ```
  ```
                                           hstore_to_jsonb                                         |                                 hstore_to_jsonb_loose
  -------------------------------------------------------------------------------------------------+---------------------------------------------------------------------------------------
   {"b": "t", "c": null, "d": "12345", "e": "012345", "f": "1.234", "g": "2.345e+4", "a key": "1"} | {"b": true, "c": null, "d": 12345, "e": "012345", "f": 1.234, "g": 23450, "a key": 1}
  (1 row)
  ```

其中，带 `_loose` 针对数字类型和布尔类型将不会在值的周围加双引号，而没有 `_loose` 则会都加上双引号。

`slice()` 函数与 `->` 操作符有些类型，不同的是 `slice()` 函数返回 hstore 兑现，而 `->` 返回文本。

```sql
SELECT slice('a=>hello, b=>world'::hstore, ARRAY['a', 'c']);
```
```
    slice
--------------
 "a"=>"hello"
(1 row)
```

`each()` 函数可以用于遍历 hstore 对象中的键值对。

```sql
SELECT * FROM each('a=>hello, b=>world'::hstore);
```
```
 key | value
-----+-------
 a   | hello
 b   | world
(2 rows)
```

`defined()` 函数可以判断 hstore 对象中某个键的值是否为 `NULL`。

```sql
SELECT
  defined('a=>NULL'::hstore, 'a'),
  defined('a=>hello'::hstore, 'a'),
  defined('a=>hello'::hstore, 'b');
```
```
 defined | defined | defined
---------+---------+---------
 f       | t       | f
(1 row)
```

### 索引

hstore 在 `@>`, `?`, `?&` 和 `?|` 操作符上支持 GiST 和 GIN 索引。在 `=` 操作符上也支持 btree 和 hash 索引。

```sql
CREATE INDEX ON users USING gist (session_data);
CREATE INDEX ON users USING gin (session_data);
CREATE INDEX ON users USING btree (session_data);
CREATE INDEX ON users USING hash (session_data);
```

查看 `users` 表信息，如下所示。

```sql
\d users
```
```
                                    Table "public.users"
    Column    |       Type        | Collation | Nullable |              Default
--------------+-------------------+-----------+----------+-----------------------------------
 id           | integer           |           | not null | nextval('users_id_seq'::regclass)
 first_name   | character varying |           | not null |
 last_name    | character varying |           | not null |
 session_data | hstore            |           | not null | ''::hstore
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
    "users_session_data_idx" gist (session_data)
    "users_session_data_idx1" gin (session_data)
    "users_session_data_idx2" btree (session_data)
    "users_session_data_idx3" hash (session_data)
```

btree 和 hash 允许 hstore 列被声明为唯一的，或在 `GROUP BY`、`ORDER BY` 或 `DISTINCT` 表达式中使用。hstore 值的排序不是特别有用，但这些索引可能对等价性查找有用。

## 译者著

本文拓展之前的部分翻译自 [PG Casts](https://www.pgcasts.com/) 的第五集 [Intro to HStore](https://www.pgcasts.com/episodes/intro-to-hstore)；拓展之后的部分来自 PostgreSQL 文档以及实验结果。

## 参考

[1] https://www.postgresql.org/docs/current/hstore.html

<div class="just-for-fun">
笑林广记 - 江心赋

有富翁同友远出，泊舟江中，偶上岸散步，见壁间题“江心赋”三字，错认“赋”字为“贼”字，惊欲走匿。
友问故，指曰：“此处有贼。”
友曰：“赋也，非贼也。”
其人曰：“赋便赋了，终是有些贼形。”
</div>
