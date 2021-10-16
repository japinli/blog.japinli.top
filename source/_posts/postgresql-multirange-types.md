---
title: "【译】PostgreSQL 14 - multirange 类型"
date: 2021-10-16 19:38:14 +0800
category: 数据库
tags:
  - PostgreSQL
  - 翻译[]
---

在最近发布的 PostgreSQL 14 中，我们最兴奋的功能之一是引入了 multirange 类型。简而言之，multirange 类型是一组不重叠的范围（range）。与范围数组不同，它们防止重叠，因此允许你有效地建立有间隙的范围模型。

我们对它们的一个用例是建立时间模型。例如，如果您想记录累积的时间和某人在医院的天数，您可以将其存储为一个 datemultirange 类型。

在 PostgreSQL 14 中，有相当多的运算符和函数可用，但我们需要的一些明显的运算符和函数包括聚合，如联合聚合，目前还不存在。然而，还有一些标准的运算符，如 `+`（合并两个范围）和 `*` 表示两个范围相交，`-` 表示两个范围的差，以及常见的包含布尔运算符。

<!--more-->

## 定义 multirange 变量

multirange 类型的典型形式是由一个外层的 `{}` 和一个以逗号分隔的范围列表组成的。

```sql
SELECT '{[2021-05-01, 2021-06-01), [2020-09-01, 2020-10-01)
        , [2021-09-01, 2021-09-13)}'::datemultirange;
```

输出：

```
{[2020-09-01,2020-10-01),[2021-05-01,2021-06-01),[2021-09-01,2021-09-13)}
```

观察它是如何将排序改为按时间顺序排列的。

multirange 不能有重叠的范围，但是您可以把一个重叠的范围集写到一个 multirange 中而不会得到错误。让我们看看这里会发生了什么：

```sql
SELECT '{[2021-05-01, 2021-06-01), [2021-09-02, 2021-09-15)
        , [2021-09-01, 2021-09-13)}'::datemultirange;
```

输出：

```
{[2021-05-01,2021-06-01),[2021-09-01,2021-09-15)}
```

观察一下它是如何将最后两个日期范围合并成一个包含它们的联合体。


## 使用 multirange

假设您有一个普通的表，它只是记录了病人的住院时间（作为一个日期范围），每次住院有一条记录。我们并不关心住院时间是否重叠，因为它们可能代表某天去做某项手术，同一天又去做另一项手术，等等。如果是在同一天，在我们的一些计算中，这两套记录将被视为一天，但您仍然需要保留原因信息，以便计费。

您的表格将看起来像这样：

```sql
CREATE TABLE stays(id bigint GENERATED ALWAYS AS IDENTITY,
    id_patient bigint,
    period_stay daterange, reason text,
    CONSTRAINT pk_stays PRIMARY KEY (id) );
```

您将在其中插入如下数据：

```sql
INSERT INTO stays(id_patient, period_stay, reason)
VALUES (1, daterange('2021-05-10', '2021-06-01'), 'Operation and healing' ),
       (2, daterange('2021-05-12', '2021-05-13'), 'X-Ray' ),
       (2, daterange('2021-05-13', '2021-05-14'), 'Blood' ),
       (2, daterange('2021-05-13', '2021-05-14'), 'MRI' ),
       (2, daterange('2021-06-13', '2021-06-14'), 'Spinal Tap' );
```

如果您想创建一个查询，将这些记录汇总到每个病人的单一记录中，并且将住院时间表示为一个多区间，那么很遗憾，我们找不到任何聚合函数来为您做这个。您必须创建你自己的聚合函数，使用一些非常难看的 CTE，或者将您的范围聚合到一个范围数组中，然后以某种方式将其铸造成一个多范围。铸造部分将为您处理重叠问题。

这个例子演示了如何使用 `array_agg` 将范围聚合到一个数组中，然后使用规范的文本形式将其转换为 datemultirange。

```sql
SELECT id_patient,
       replace(array_agg(period_stay)::text, '"', '')::datemultirange AS period_total_stay
FROM stays
GROUP BY id_patient
ORDER BY id_patient;
```

上述查询的输出看起来像是这样的：

```sql
 id_patient |                 period_total_stay
------------+---------------------------------------------------
          1 | {[2021-05-10,2021-06-01)}
          2 | {[2021-05-12,2021-05-14),[2021-06-13,2021-06-14)}
```

上面的方法并不理想，因为它依赖于一个日期范围数组的典型形式，看起来就像下面这样，除了将日期范围用双引号括起来之外，与预期的 datemultirange 完全一样。

```
{"[2021-05-12,2021-05-13)",
"[2021-05-13,2021-05-14)",
"[2021-05-13,2021-05-14)","[2021-06-13,2021-06-14)"}
```

因此，本质上与 datemultirange 的规范形式相同，但每个 daterange 周围有双引号。

我们最喜欢的y一个函数是 **`unnest`**，**`unnest`** 函数支持 multirange 并返回一组范围。使用 **`array_agg`**、**`multirange`** 和 **`unnest`** 的组合，您可以从一组重叠的范围中创建一组不重叠的范围，如下所示：

```sql
SELECT id_patient,
    unnest(replace(array_agg(period_stay)::text, '"', '')::datemultirange) AS period_deduped_stay
FROM stays
GROUP BY id_patient
ORDER BY id_patient;
```

输出：

```
 id_patient |   period_deduped_stay
------------+-------------------------
          1 | [2021-05-10,2021-06-01)
          2 | [2021-05-12,2021-05-14)
          2 | [2021-06-13,2021-06-14)
(3 rows)
```

## 译者著

* 本文翻译自 [Postgres Online Journal](https://www.postgresonline.com/) 上的 [Multirange types in PostgreSQL 14](https://www.postgresonline.com/article_pfriendly/401.html)。

<div class="just-for-fun">
笑林广记 - 属牛

一官遇生辰，吏典闻其属鼠，乃醵黄金铸一鼠为寿。
官甚喜，曰：“汝等可知奶奶生辰亦在目下乎？”
众吏曰：“不知，请问其属？”
官曰：“小我一岁，丑年生的。”
</div>
