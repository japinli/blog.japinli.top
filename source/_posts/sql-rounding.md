---
title: "PostgreSQL 中 ROUND 函数的使用"
date: 2019-03-14 21:38:35 +0800
category: Database
tags: PostgreSQL
---

在某些情况下我们可能需要对实数进行四舍五入，在 SQL 中我们可以通过 `ROUND` 函数来实现。

```
# SELECT ROUND(123.456)
 round
-------
   123
(1 row)

# SELECT ROUND(123.567)
 round
-------
   124
(1 row)
```

<!-- more -->

我们还可以给 `ROUND` 函数指定第二个参数，它表示四舍五入的位置。

```
# SELECT ROUND(123.456, 1)
 round
-------
 123.5
(1 row)

# SELECT ROUND(123.567, -2)
 round
-------
   100
(1 row)
```
