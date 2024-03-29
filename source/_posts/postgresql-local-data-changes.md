---
title: "【译】PostgreSQL locale 设置更改"
date: 2022-01-11 16:23:46
categories:
tags:
---

以下信息侧重于使用 GNU C 库 (glibc) 的操作系统，其中包括最流行的 Linux 发行版。所有版本的 PostgreSQL 都会受到影响。其他操作系统原则上可能存在相同的问题，但我们尚未收集任何相关信息。

PostgreSQL 使用操作系统的 C 库提供的语言环境数据对文本进行排序。排序发生在各种上下文中，包括用户输出、合并连接、B 树索引和范围分区。在后两种情况下，排序后的数据被持久化到磁盘。如果 C 库中的语言环境在数据库的生命周期中发生变化，则持久化的数据可能会与预期的排序顺序不一致，从而导致错误的查询结果和其他不正确的行为。例如，如果索引未按照索引扫描所期望的方式进行排序，则查询可能无法找到实际存在的数据，并且更新可能会插入不应允许的重复数据。同样，在分区表中，查询可能会在错误的分区中查找，而更新可能会写入错误的分区。_因此，对于数据库的正确操作，避免语言环境在数据库的生命周期内发生不兼容的变化是至关重要的。_

操作系统供应商，尤其是 GNU C 库的作者，不时地以较小的方式更改语言环境以纠正错误或添加对更多语言的支持。虽然这在理论上违反了上述规则，但从历史上看，它影响的用户很少，也没有受到广泛关注。但是，**在 2018-08-01 发布的 glibc 版本 2.28 中，包含了对语言环境数据的重大更新，这可能会影响许多用户的数据**。需要注意的是，更新本身是合法的，因为它使语言环境符合当前的国际标准。但是，如果将这些更新应用于现有的 PostgreSQL 系统，则必然会出现问题。

操作系统供应商负责将 glibc 更新集成到 Linux 发行版中。我们希望长期支持 Linux 发行版的供应商不会在给定版本中对其发行版应用不兼容的语言环境更新，但这只是一种预期，因为我们无法预测或影响未来的行动。此外，PostgreSQL 目前无法检测到不兼容的 glibc 更新。因此，在规划任何更新或升级时需要一些手动操作。

<!--more-->

## 哪些将受到影响

可能受到影响的情况涉及将更改的语言环境应用于现有实例或二进制等效实例，特别是：
* 更改正在运行的实例上的语言环境（即使重新启动）。
  * 这尤其包括将 Linux 发行版升级到新的主要版本，同时保留 PostgreSQL 数据目录。
  * 使用 pg_upgrade（例如同时升级操作系统和 PostgreSQL 专业时）并不能避免问题。
* 使用流式复制到具有不同区域设置数据的备用实例。（然后备用数据库可能已损坏，但主数据库不受影响。）
* 在具有不同语言环境的系统上恢复二进制备份（例如 pg_basebackup）。
* 不受影响的是数据以逻辑（非二进制）方式传输的情况，包括：
  * 使用 pg_dump 备份/升级
  * 逻辑复制

### 测试

使用操作系统 `sort` 实用程序是查看排序规则是否已更改的简单方法：

```shell
( echo "1-1"; echo "11" ) | LC_COLLATE=en_US.UTF-8 sort
```

这两个字符串将在不同的语言环境版本上进行不同的排序。比较新旧操作系统版本的输出。

**注意：**如果这两个排序相同，则可能还有其他差异。

## 该如何应对

当实例需要升级到新的 glibc 版本时，例如升级操作系统，则在升级后：
* 所有涉及 `text`、`varchar`、`char` 和 `citext` 类型列的索引都应在实例投入生产之前重新建立索引。
* 应检查在分区键中使用这些类型的范围分区表，以验证所有行是否仍在正确的分区中。 （这不太可能成为问题，只有特别模糊的分区界限。）
* 为避免因重新索引或重新分区而导致停机，请考虑使用逻辑复制进行升级。
* 使用 C 或 POSIX 语言环境的数据库或表列不受影响。所有其他语言环境都可能受到影响。
* 使用 ICU 提供程序的排序规则的表列不受影响。

### 哪些索引受到了影响

我们可以在每个数据库中使用下面 SQL 查询来找出受影响的索引：

```sql
SELECT
    indrelid::regclass::text,
    indexrelid::regclass::text,
    collname,
    pg_get_indexdef(indexrelid)
FROM
    (SELECT
         indexrelid,
         indrelid,
         indcollation[i] coll
     FROM
         pg_index,
         generate_subscripts(indcollation, 1) g(i)
    ) s JOIN pg_collation c ON coll = c.oid
WHERE
    collprovider IN ('d', 'c') AND collname NOT IN ('C', 'POSIX');
```

## 哪些 Linux 发行版受到影响

为了帮助用户评估他们当前操作系统的情况，我们收集了以下信息。再次注意，这只是当前情况的报告，我们无法影响这些供应商在未来做什么或可能做什么。

### Debian

版本 8 (jessie) 和 9 (stretch) 使用旧的语言环境。我们预计这些版本中不会有任何不兼容的更改。从版本 8 升级到 9 是安全的。
*版本 10 (buster) 使用新的语言环境*，因此，升级时需要谨慎。

参看：https://lists.debian.org/debian-glibc/2019/03/msg00030.html

### Ubuntu

Ubuntu 最高版本 18.04（bionic）使用旧的语言环境。
新的 glibc 2.28 语言环境数据是在版本 18.10（cosmic）（不是 LTS）中引入的。从 bionic 或旧版本升级到 cosmic 或更新版本需要上述缓解步骤。

### RHEL/CentOS

版本 6 和 7 使用旧的语言环境。从版本 6 升级到 7 是安全的，<i>除非使用 `de_DE.UTF-8` 语言环境</i>，这在这些版本之间看到了类似的变化。（所有其他语言环境，包括其他 `de_*.UTF-8` 语言环境，如 `de_AT`，都是安全的。）
**版本 8 使用新的语言环境**。因此，升级时需要谨慎。

## 参考

[1] https://postgresql.verite.pro/blog/2018/08/27/glibc-upgrade.html
[2] Work is being done to track collation versions on the PostgreSQL side: [Collations](https://wiki.postgresql.org/wiki/Collations)


<div class="just-for-fun">
笑林广记 - 封君

有市井获封者，初见县官，甚跼蹐，坚辞上坐。
官曰：“叨为令郎同年，论理还该侍坐。”
封君乃张目问曰：“你也是属狗的么？”
</div>
