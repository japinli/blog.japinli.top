---
title: "Git bisect 二分查找实践"
date: 2022-02-18 15:44:01
categories: 杂项
tags:
  - git
---

最近在分析 bug 的时候接触到了 `git bisect` 这个命令，虽然之前也知道这个命令，但是由于平时用的不多所以没有深入的研究，对它的使用方法也不是很熟悉。其实这个命令使用起来还是非常简单的，本文结合实际情况简要介绍一下 `git bisect` 的使用方法。

<!--more-->

## 介绍

`git bisect` 是一个使用二分查找来定位引入 bug 提交记录的命令。[官方文档](https://git-scm.com/docs/git-bisect)详细的说明了其使用方法，这里有一篇通俗易懂的 [`git bisect` 使用介绍](https://www.metaltoad.com/blog/beginners-guide-git-bisect-process-elimination)（您可能需要梯子才能打开）。

## 示例

我在分析 PostgreSQL [BUG #17409](https://www.postgresql.org/message-id/17409-52871dda8b5741cb%40postgresql.org) 的问题时，尝试用 `git bisect` 来定位问题，发现它真的是太香了。Bug 的提交者明确指出在之前的版本中是执行执行相应的操作的，但是在之后的版本中就报错了，那么可以肯定是在其中某个提交中引入了 bug，这种情况非常适合 `git bisect` 来快速定位到 bug 引入的提交。

由于 PotgreSQL 的版本历史记录非常清晰，我根据用户提供的版本信息找到 7966b79801 这个提交，并验证其可以正常工作，那么我们就可以以此作为起点，从这个点到目前 master 分支上最新的提交，少说也有 3k 个提交记录了，如果我们一个一个提交的验证，肯定不切实际，通过二分的方式，我们可以快速的完成这个过程。

首先我们执行 `git bisect start` 开始二分查找。接着我们标记 7966b79801 这个提交为正常的，标记 19252e8ec9 为异常的（不能正常工作），这两个点就是二分查找的起点和终点。

```shell
$ git bisect good 7966b79801
$ git bisect bad 19252e8ec9
Bisecting: 1902 revisions left to test after this (roughly 11 steps)
[c30f54ad732ca5c8762bb68bbe0f51de9137dd72] Detect POLLHUP/POLLRDHUP while running queries.
```

在标记异常的提交之后，它将给出一个新的提交，并且估算出整个查找过程的步数，从上面看到在 3k 多个提交中定位引入问题的提交大概只需要 11 步即可完成，是不是效率贼高啊！！！

现在我们来测试 c30f54ad73 这个提交，如果正常就用 good 标记，异常则用 bad 标记，重复这个过程，最后就可以找到引入 bug 的提交记录，如下所示。

```shell
$ git bisect bad
Bisecting: 950 revisions left to test after this (roughly 10 steps)
[24b83a5082541bdb1b333b7fcbe92f194128595c] Doc: clarify data type behavior of COALESCE and NULLIF.
$ git bisect good
Bisecting: 475 revisions left to test after this (roughly 9 steps)
[65330622441d7ee08f768c4326825ae903f2595a] doc: Clarify status of SELECT INTO on reference page
$ git bisect bad
Bisecting: 237 revisions left to test after this (roughly 8 steps)
[f234899353f8998bdbd265125ce4a505a312d910] remove missing reference to crypto test from patch 978f869b99
$ git bisect bad
Bisecting: 118 revisions left to test after this (roughly 7 steps)
[9c83b54a9ccdb111ce693ada2309475197c19d70] Fix a recently-introduced race condition in LISTEN/NOTIFY handling.
$ git bisect good
Bisecting: 59 revisions left to test after this (roughly 6 steps)
[c7aba7c14efdbd9fc1bb44b4cb83bedee0c6a6fc] Support subscripting of arbitrary types, not only arrays.
$ git bisect bad
Bisecting: 29 revisions left to test after this (roughly 5 steps)
[6114040711affa2b0bcf47fa2791187daf8455fb] Small code simplifications
$ git bisect good
Bisecting: 14 revisions left to test after this (roughly 4 steps)
[947789f1f5fb61daf663f26325cbe7cad8197d58] Avoid using tuple from syscache for update of pg_database.datfrozenxid
$ git bisect good
Bisecting: 7 revisions left to test after this (roughly 3 steps)
[f2a69b352de1dffc534c4835010e736018aa94de] Doc: clarify that CREATE TABLE discards redundant unique constraints.
$ git bisect good
Bisecting: 3 revisions left to test after this (roughly 2 steps)
[62ee70331336161cb44733b6c3e0811696d962aa] Teach contain_leaked_vars that assignment SubscriptingRefs are leaky.
$ git bisect good
Bisecting: 1 revision left to test after this (roughly 1 step)
[16c302f51235eaec05a1f85a11c1df04ef3a6785] Simplify code for getting a unicode codepoint's canonical class.
$ git bisect good
Bisecting: 0 revisions left to test after this (roughly 0 steps)
[8b069ef5dca97cd737a5fd64c420df3cd61ec1c9] Change get_constraint_index() to use pg_constraint.conindid
$ git bisect bad
8b069ef5dca97cd737a5fd64c420df3cd61ec1c9 is the first bad commit
commit 8b069ef5dca97cd737a5fd64c420df3cd61ec1c9
Author: Peter Eisentraut <peter@eisentraut.org>
Date:   Wed Dec 9 15:12:05 2020 +0100

    Change get_constraint_index() to use pg_constraint.conindid

    It was still using a scan of pg_depend instead of using the conindid
    column that has been added since.

    Since it is now just a catalog lookup wrapper and not related to
    pg_depend, move from pg_depend.c to lsyscache.c.

    Reviewed-by: Matthias van de Meent <boekewurm+postgres@gmail.com>
    Reviewed-by: Tom Lane <tgl@sss.pgh.pa.us>
    Reviewed-by: Michael Paquier <michael@paquier.xyz>
    Discussion: https://www.postgresql.org/message-id/flat/4688d55c-9a2e-9a5a-d166-5f24fe0bf8db%40enterprisedb.com

 src/backend/catalog/pg_depend.c      | 69 ------------------------------------
 src/backend/commands/tablecmds.c     |  1 -
 src/backend/optimizer/util/plancat.c |  1 -
 src/backend/utils/adt/ruleutils.c    |  3 +-
 src/backend/utils/cache/lsyscache.c  | 27 ++++++++++++++
 src/include/catalog/dependency.h     |  2 --
 src/include/utils/lsyscache.h        |  1 +
 7 files changed, 29 insertions(+), 75 deletions(-)
```

如上所示，经过 11 次操作我们就定位了引入 bug 的提交，并且使用起来也没有想象中那么复杂。如果您对 `git bisect` 不是很熟悉，想要找示例练手，本文的示例是一个不错的选择。

## 参考

[1] https://git-scm.com/docs/git-bisect
[2] https://www.metaltoad.com/blog/beginners-guide-git-bisect-process-elimination

<div class="just-for-fun">
笑林广记 - 入场

监生应试入场方出，一故人相遇揖之，并揖路旁猪屎。
生问：“此臭物，揖之何为？”
答曰：“他臭便臭，也从大肠（场）里出来的。”
</div>
