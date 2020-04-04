---
title: "PostgreSQL 行级安全策略的使用"
date: 2019-07-10 22:37:11 +0800
category: Database
tags:
  - PostgreSQL
---

今天朋友咨询了下面一个问题：

> 一个信息系统中包含全省的数据，但是各个市州可以访问自己的数据，而不能访问其他市州的数据。
> 例如，四川省下辖的成都市、绵阳市等有自己的数据，它们可以使用自己的用户登陆并更新自己的数据，
> 而不能修改其他市的数据（不可见）；而四川省级别的用户则对下辖的所有市的数据均可见。

在我初看这个问题时，PostgreSQL 的行级安全策略 (Row Security Policy) 浮现在我的脑海中。PostgreSQL 的行级安全策略可以基于每个用户限制正常查询可以返回哪些行，或者由数据修改命令插入，更新或删除哪些行。默认情况下，PostgreSQL 中的表是不具备任何策略的。

<!-- more -->

## 启用行级安全策略

基于上述问题，假设我们有如下的表：

``` SQL
CREATE TABLE city_info (city text, people int);
```

默认情况下是没有启用行级安全策略，我们可以使用如下命令在该表上启用该特性：

``` SQL
ALTER TABLE city_info ENABLE ROW LEVEL SECURITY;
```

为了测试，我们先创建三个用户，它们分别为 `admin`, `chengdu` 以及 `mianyang`。

```
CREATE ROLE admin WITH LOGIN;
CREATE ROLE chengdu WITH LOGIN;
CREATE ROLE mianyang WITH LOGIN;
ALTER TABLE city_info OWNER TO admin;
```

接着，我们插入两条测试数据：

``` SQL
INSERT INTO city_info VALUES ('chengdu', 100), ('mianyang', 80);
```

## 创建策略

现在，我们为其创建策略使得相应的市只能访问其对应的数据。

``` SQL
CREATE POLICY city_policy ON city_info USING (city = current_user);
```

在创建好策略之后，我们使用 `chengdu` 用户登陆并查询数据时出现如下提示：

```
ERROR:  permission denied for relation city_info
```

这是由于我们还没有对用户授权。

``` SQL
GRANT ALL ON city_info TO chengdu;
GRANT ALL ON city_info TO mianyang;
```

## 验证方案

在授权完成之后，我们就可以查询数据了。

```
$ psql -U chengdu postgres
psql (10.4)
Type "help" for help.

postgres=> select * from city_info ;
  city   | people
---------+--------
 chengdu |    100
(1 row)
```

而我们使用 `admin` 用户登陆则可以查询所有数据。

```
$ psql -U admin postgres
psql (10.4)
Type "help" for help.

postgres=> select * from city_info ;
   city   | people
----------+--------
 chengdu  |    100
 mianyang |     80
(2 rows)
```

当我们尝试使用 `mianyang` 用户去修改数据时只能修改其可见的数据；而原本属于 `chengdu` 用户的数据是不会被修改的。

```
$ psql -U mianyang postgres
psql (10.4)
Type "help" for help.

postgres=> select * from city_info ;
   city   | people
----------+--------
 mianyang |     80
(1 row)

postgres=> update city_info set people = 90;
UPDATE 1
postgres=> select * from city_info ;
   city   | people
----------+--------
 mianyang |     90
(1 row)
```

## 参考

https://www.postgresql.org/docs/10/ddl-rowsecurity.html
