---
title: "【译】PostgreSQL 中生成假邮件地址"
date: 2022-04-27 21:10:33 +0800
categories: 数据库
tags:
  - PostgreSQL
  - 翻译
  - PG Casts
---

有时候您想要比较各种查询的相对性能或者您需要一个大表来测试 PostgreSQL 的新功能，这是您需要一堆假数据。在这一集中我们将使用 PostgreSQL 在短时间内生成一堆假邮件地址。

<!--more-->

我们将使用包含一个电子邮件字段的 `users` 表，如下所示：

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR NOT NULL unique
);
```

如果我们只需要 2 到 3 条记录，那么写几个插入语句就足够了。但是，如果我们需要很多记录，比如 10,000 条记录呢？

首先，如果我们需要 10,000 个。`generate_series()` 函数可以帮助我们实现这一点。

```sql
SELECT generate_series(1, 10000);
```

上面的 SQL 给了我们 10,000 个整数。现在我们需要一种方法将这些整数转换成电子邮件。我们可以通过一些字符串连接操作来实现。

```sql
SELECT 'person' || num || '@example.com'
FROM generate_series(1, 10000) AS num;
```

```
        ?column?
-------------------------
 person1@example.com
 person2@example.com
 person3@example.com
 person4@example.com
 person5@example.com
 person6@example.com
 [...]
 person9999@example.com
 person10000@example.com
(10000 rows)
```

太棒了。我们现在有 10,000 个唯一的假电子邮件地址。接下来我们需要将其插入到 `users` 表中。我们可以使用带有 `SELECT` 字句的 `INSERT` 语句来实现。

```sql
INSERT INTO users(email)
  SELECT 'person' || num || '@example.com'
  FROM generate_series(1, 10000) AS num;
```

我们可以使用 `TABLE` 语句来查看是否按预期插入了所有内容。

```sql
TABLE users;
```

```
  id   |          email
-------+-------------------------
     1 | person1@example.com
     2 | person2@example.com
     3 | person3@example.com
     4 | person4@example.com
     5 | person5@example.com
     6 | person6@example.com
[...]
  9999 | person9999@example.com
 10000 | person10000@example.com
(10000 rows)
```

我们甚至可以通过增加一些变化来改进这个。随机的电子邮件主机名怎么样？我们可以通过更多的字符串连接和嵌套在子查询中的 `CASE` 语句来实现这一点。

```sql
SELECT
  'person' || num || '@' ||
  (CASE (random() * 2)::integer
    WHEN 0 THEN 'gmail'
    WHEN 1 THEN 'hotmail'
    WHEN 2 THEN 'yahoo'
  END) || '.com'
FROM generate_series(1, 10000) AS num;
```

```
        ?column?
-------------------------
 person1@yahoo.com
 person2@gmail.com
 person3@hotmail.com
 person4@yahoo.com
 person5@hotmail.com
 person6@yahoo.com
[...]
 person9999@yahoo.com
 person10000@hotmail.com
(10000 rows)
```

在处理 `generate_series()` 生成的每一行时，我们将生成一个从 0 到 2 的随机数。`CASE` 语句将根据该随机数在三个候选主机名中选取一个，然后连接到电子邮件的其他部分。

## 译者著

本文翻译自 [PG Casts](https://www.pgcasts.com/) 的第四集 [Generating Fake Email Addresses](https://www.pgcasts.com/episodes/generating-fake-email-addresses)。

<div class="just-for-fun">
笑林广记 - 哭麟

孔子见死麟，哭之不置。
弟子谋所以慰之者，乃编钱挂牛体，告曰：“麟已活矣。”
孔子观之曰：“这明明是一只村牛，不过多得几个钱耳。”
</div>
