---
title: "【译】PostgreSQL 查询结果转为 JSON 格式"
date: 2019-09-16 22:59:56 +0800
category: 数据库
tags:
  - PostgreSQL
  - 翻译
---

{% asset_img postgresql-weekly.png %}

您知道 Postgres 提供了一个函数将查询结果集转为 JSON 数据类型吗？这个函数是 `row_to_json`。

<!-- more -->

我们先创建一个表，它包含两个用户记录以以及一个 `interests` 的属性列：

``` sql
CREATE TABLE people
	(name text, age int, interests text[]);

INSERT INTO people (name, age, interests)
	VALUES
    ('Jon', 12, ARRAY ['Golf', 'Food']),
    ('Jane', 45, ARRAY ['Art']);
```

`row_to_json` 函数最基本的使用方法是使用 `ROW` 行构造器，例如：

``` sql
SELECT row_to_json(ROW(name, age, interests)) FROM people;
                row_to_json
-------------------------------------------
 {"f1":"Jon","f2":12,"f3":["Golf","Food"]}
 {"f1":"Jane","f2":45,"f3":["Art"]}
(2 rows)
```

针对表中不同的类型，在最后的输出中都做了相应的转换，但是属性列的名称在输出中并没有体现出来。幸运的是我们可以通过子查询的方式来实现：

``` sql
SELECT row_to_json(q1) FROM (SELECT * FROM people LIMIT 1) q1;
                     row_to_json
-----------------------------------------------------
 {"name":"Jon","age":12,"interests":["Golf","Food"]}
(1 rows)
```

虽然与我们的示例无关，但我们还是需要提一下，`row_to_json` 提供了一个可选的参数 `prettifies` 用于格式化输出，想要启用它，您可以在上面的示例中使用 `row_to_json(q1, true)`。

``` sql
SELECT row_to_json(q1, true) FROM (SELECT * FROM people LIMIT 1) q1;
          row_to_json
-------------------------------
 {"name":"Jon",               +
  "age":12,                   +
  "interests":["Golf","Food"]}
(1 row)
```

## 原文

[1] https://postgresweekly.com/issues/322
