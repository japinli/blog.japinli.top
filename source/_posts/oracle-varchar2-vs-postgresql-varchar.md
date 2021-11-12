---
title: "Oracle VARCHAR2 与 PostgreSQL VARCHAR 异同"
date: 2021-11-12 23:54:51 +0800
categories: 数据库
tags:
  - Oracle
  - PostgreSQL
---

在 Oracle 迁移到 PostgreSQL 数据库的过程中，我们通常使用 PostgreSQL 中的 `VARCHAR` 类型替换 Oracle 中的 `VARCHAR2` 类型。本文将针对 Oracle 中的 `VARCHAR2` 类型和 PostgreSQL 中的 `VARCHAR` 类型进行简要的比较。

<!--more-->

## Oracle VARCHAR2 类型

在 Oracle 数据库中，我们通常使用 `VARCHAR2` 类型存储变长数据。Oracle 中的 `VARCHAR2` 存储范围为 1 到 4000 个字节。

当我们创建表时，必须指定字符长度。Oracle 提供了两种方式。

* `VARCHAR2(max_size BYTE)` - 以字节的方式给出最大值。
* `VARCHAR2(max_size CHAR)` - 以字的方式给出最大值。

默认情况下，Oracle 是以字节的方式给出最大值的，即 `VARCHAR2(max_size)` 等同于 `VARCHAR2(max_size BYTE)`。

在 Oracle 12c 中，您可以指定 `max_size` 为 32767。Oracle 通过参数 `MAX_STRING_SIZE` 来控制这个值，如果 `MAX_STRING_SIZE = STANDARD`，那么 `VARCHAR2` 的最大值仍然只能最大为 4000；若 `MAX_STRING_SIZE = EXTENDED`，那么 `VARCHAR2` 的最大值则可以设置为 32767。

### 示例

我们创建一张表，并插入一条记录。

```sql
CREATE TABLE tbl (s1 varchar2(3), s2 varchar2(3 char));
INSERT INTO tbl VALUES ('a', '您');
```

通过 `length()` 函数查看其长度，我们发现 `s2` 的长度为 3，这里需要注意的是在 `VARCHAR2` 包含多字节编码的字时他将在末尾添加一个 `0x00` 字节。

```sql
SELECT length(s1), length(s2) FROM tbl;

LENGTH(S1) LENGTH(S2)
---------- ----------
         1          3
```

当我们插入的字节大于指定的 `max_size` 将报错。
```sql
INSERT INTO tbl VALUES ('ab', '您a')
                              *
ERROR at line 1:
ORA-12899: value too large for column "SYS"."TBL"."S2" (actual: 4, maximum: 3)
```

此外，Oracle 中的 `length()` 针对 `VARCHAR2` 类型得到的是字节的长度，而不是字的长度。

以上测试基于 Oracle 12.1.0.2.0。

## PostgreSQL VARCHAR 类型

PostgreSQL 中的 `VARCHAR` 类型与 Oracle 有所不同，它不支持指定不同的类型，PostgreSQL 的 `VARCHAR` 是按字来计算的而不是字节。

### 示例

创建一张测试表，并插入一条记录。

```sql
CREATE TABLE tbl (s1 varchar(3));
INSERT INTO tbl VALUES ('你好啊');
```

一切都正常。我们再次尝试插入更多的字。

```sql
INSERT INTO tbl VALUES ('你好啊a');
ERROR:  value too long for type character varying(3)

INSERT INTO tbl VALUES ('你好啊啊');
ERROR:  value too long for type character varying(3)
```

这是无论我们插入什么，PostgreSQL 都将报错，并指出超出长度限制。

```sql
SELECT length(s1), octet_length(s1) FROM TBL;
 length | octet_length
--------+--------------
      3 |            9
(1 row)
```

字符串 `你好啊` 的 [UTF-8 编码](https://www.browserling.com/tools/utf8-encode)序列为 `\xe4\xbd\xa0\xe5\xa5\xbd\xe5\x95\x8a`，包含 9 个字节。

PostgreSQL 中的最大长度为 `10485760`，10MB 的数据。

## 总结

| 数据库类型         | 最大长度            | 申明方式                           | length() 函数 |
|--------------------|---------------------|------------------------------------|---------------|
| PostgreSQL VARCHAR | 10485760            | varchar(n)                         | 以字计算      |
| Oracle VARCHAR2    | 4000 or 32767 (12c) | varchar2(n byte), varchar2(n char) | 以字节计算    |


## 参考

[1] https://www.oracletutorial.com/oracle-basics/oracle-varchar2/
[2] https://www.postgresql.org/docs/13/datatype-character.html

<div class="just-for-fun">
笑林广记 - 州同

一人好古董，有持文王鼎求售者，以百金买之。
又一人持一夜壶至，铜色斑驳陆离，云是武王时物，亦索重价。
曰：“铜色虽好，只是肚里甚臭。”
答曰：“腹中虽臭，难道不是个周铜？”
</div>
