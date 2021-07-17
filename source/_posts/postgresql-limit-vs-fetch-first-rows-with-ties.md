---
title: "PostgreSQL LIMIT 与 FETCH FIRST ROWS ... WITH TIES"
date: 2021-07-17 12:24:39 +0800
category: 数据库
tags:
  - PostgreSQL
  - 翻译
---

在 SQL 和 PostgreSQL 社区中，大多数人都使用过许多数据库引擎提供的 `LIMIT` 子句。然而，很多人不知道的是，`LIMIT/OFFSET` 是不符合标准的，因此不能移植。处理 LIMIT 的正确方法基本上是使用 `SELECT ... FETCH FIRST ROWS`。然而，还有更多的东西没有被发现。

<!-- more -->

## LIMIT vs. FETCH FIRST ROWS

在我们深入研究一些更高级的功能之前，我们需要看看如何使用 `LIMIT` 和 `FETCH FIRST ROWS`。为了演示这个功能，我编译了一个简单的数据集：

```sql
test=# CREATE TABLE t_test (id int);
CREATE TABLE
test=# INSERT INTO t_test
VALUES  (1), (2), (3), (3),
(4), (4), (5);
INSERT 0 7
test=# TABLE t_test;
 id
----
  1
  2
  3
  3
  4
  4
  5
(7 rows)
```

我们的数据集有 7 条简单的行。让我们看看如果我们使用 `LIMIT` 会发生什么：

```sql
test=# SELECT * FROM t_test LIMIT 3;
 id
----
  1
  2
  3
(3 rows)
```

在这种情况下，将返回前三条记录。请注意，我们在这里讨论的是任何行。只要能先找到的就会被返回。没有什么特别的顺序。

与 ANSI SQL 兼容的写法如下：

```sql
test=# SELECT *
           FROM  t_test
           FETCH FIRST 3 ROWS ONLY;
 id
----
  1
  2
  3
(3 rows)
```

许多人可能以前从未使用过或见过这种语法，但这实际上是处理 `LIMIT` 的“正确”方法。

然而，还有一点。如果在 `LIMIT` 子句中使用 `NULL` 会怎样？其结果可能会让你吃惊：

```sql
test=# SELECT * FROM t_test LIMIT NULL;
 id
----
  1
  2
  3
  3
  4
  4
  5
(7 rows)
```

数据库引擎不知道什么时候停止返回行。记住，`NULL` 是未定义的，所以它并不意味着零。因此，所有的行都会被返回。你必须牢记这一点，以避免不愉快的意外......

## FETCH FIRST ... ROWS WITH TIES

`WITH TIES` 功能是在 PostgreSQL 13 版本中引入的，它修复了一个常见的问题：处理重复的数据。如果你取了前几行，PostgreSQL 会在固定的行数上停止。然而，如果同样的数据一次又一次地出现，会发生什么？这里有一个例子：

```sql
test=# SELECT *
           FROM  t_test
           ORDER BY id
           FETCH FIRST 3 ROWS WITH TIES;
 id
----
  1
  2
  3
  3
(4 rows)
```

在这种情况下，我们实际上得到了 4 行记录，而不仅仅是 3 行。原因是最后一个值在第 3 行之后又出现了，所以 PostgreSQL 觉得把它也包括进去。这里需要注意的是，`ORDER BY` 字句是需要的，如果没有，其结果是随机的。因此，如果你想要包括某一类的所有记录，而不是停留在一个固定的行数上，这时 `WITH TIES` 就很重要了。

假设再增加一行记录：

```sql
test=# INSERT INTO t_test VALUES (2);
INSERT 0 1
test=# SELECT *
           FROM  t_test
           ORDER BY id
           FETCH FIRST 3 ROWS WITH TIES;
 id
----
  1
  2
  2
(3 rows)
```

在这种情况下，我们确实得到了 3 行记录，因为它不是关于值为 3 类型的数据，而是真正关于数据集末尾的额外的、相同的数据。

## WITH TIES - 管理附加列

到目前为止，我们已经了解了一些关于只使用一列的最简单情况。然而，这与真实情况相差甚远。在真正的工作应用中，你肯定会有不止一列。因此，让我们增加一个：

```sql
test=# ALTER TABLE t_test
           ADD COLUMN x numeric DEFAULT random();
ALTER TABLE
test=# TABLE t_test;
 id |       x
----+--------------------
  1 |  0.258814135879447
  2 |  0.561647200043165
  3 |  0.340481941960185
  3 |  0.999635345010109
  4 |  0.467043266494571
  4 |  0.742426363498449
  5 | 0.0611112678267247
  2 |  0.496917052156565
(8 rows)
```

在 `LIMIT` 的情况下，没有任何变化。然而，`WITH TIES` 在这里有点特殊：

```sql
test=# SELECT *
            FROM  t_test
            ORDER BY id
            FETCH FIRST 4 ROWS WITH TIES;
 id |       x
----+-------------------
  1 | 0.258814135879447
  2 | 0.561647200043165
  2 | 0.496917052156565
  3 | 0.999635345010109
  3 | 0.340481941960185
(5 rows)
```

在这里你得到了 5 行记录。第 5 行被添加是因为 `id = 3` 出现了不止一次。注意 `ORDER BY` 子句：我们按 `id` 排序。因此，`id` 列与 `WITH TIES` 有关。

我们来看看当 `ORDER BY` 子句被扩展时会发生什么：

```sql
test=# SELECT *
           FROM  t_test
           ORDER BY id, x
           FETCH FIRST 4 ROWS WITH TIES;
 id |       x
----+-------------------
  1 | 0.258814135879447
  2 | 0.496917052156565
  2 | 0.561647200043165
  3 | 0.340481941960185
(4 rows)
```

我们按两列进行排序。因此，只有在两列都相同的情况下，`WITH TIES` 才会增加行数，而在我们的例子中，情况并非如此。

`WITH TIES` 是 PostgreSQL 提供的一个奇妙的新功能。然而，它不仅仅是用来限制数据的。如果你是一个窗口函数的爱好者，你也可以利用 `WITH TIES`，就像我的[另一篇博文](https://www.cybertec-postgresql.com/en/timeseries-exclude-ties-current-row-and-group/)中所展示的那样，它涵盖了 PostgreSQL 所提供的高级 SQL 功能。

## 译者著

* 本文翻译自 Hans-Jürgen Schönig 的 [POSTGRESQL: LIMIT VS FETCH FIRST ROWS … WITH TIES](https://www.cybertec-postgresql.com/en/postgresql-limit-vs-fetch-first-rows-with-ties/)。
* __Hans-Jürgen Schönig__ 从 90 年代起就有使用 PostgreSQL 的经验。他是 CYBERTEC 的首席执行官和技术负责人，该公司是该领域的市场领导者之一，自 2000 年以来为全球无数的客户提供服务。

<div class="just-for-fun">
笑林广记 - 比职

甲乙两同年初中。甲选馆职，乙授县令。
甲一日乃骄语之曰：“吾位列清华，身依宸禁，与年兄做有司者，资格悬殊。他不具论，即选拜客用大字帖儿，身份体面，何啻天渊。”
乙曰：“你帖上能用几字，岂如我告示中的字，不更大许多？晓谕通告，百姓无不凛遵恪守，年兄却无用处。”
甲曰：“然则金瓜黄盖，显赫炫耀，兄可有否？”
乙曰：“弟牌棍清道，列满街衢，何止多兄数倍？”
甲曰：“太史图章，名标上苑，年兄能无羡慕乎？”
乙曰：“弟有朝廷印信，生杀之权，惟吾操纵，视年兄身居冷曹，图章私刻，谁来惧你？”
甲不觉词遁，乃曰：“总之翰林声价值千金。”
乙笑曰：“吾坐堂时百姓口称青天老爷，岂仅千金而已耶！”
</div>
