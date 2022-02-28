---
title: "PostgreSQL buffer usage 溢出"
date: 2022-02-28 18:45:00 +0800
categories: 数据库
tags:
  - PostgreSQL
  - BUG
mathjax: true
---

今天灿灿（微信公众号：PostgreSQL 学徒）发来一个问题，说是日志中 `buffer usage` 出现了负数，如下所示。

{% asset_img buffer-usage-overflow.png %}

<!--more-->

## 问题分析

其实这就是一个数据类型溢出的问题，我第一时间想到的时查看一下这个变量的类型，然而，我发现 `VacuumPageHit` 是 `int64` 类型（$2^{63} = 9223372036854775808$），那这个溢出的概率就很小了，在结合其运行的时间来看，几乎不可能发生溢出。

随后又询问了一下他当前的数据库版本，发现是 11.9 版本，而我查看的是 master 分支代码，因此，存在一定的误差。通过查看 11.9 的源码，发现 `VacuumPageHit` 被定义为 `int` 类型（$2^{31} = 2147483648$），那么这个溢出就有很大的概率发生。

```shell
$ ag 'VacuumPageHit'
src/backend/utils/init/globals.c
142:int                 VacuumPageHit = 0;

src/backend/storage/buffer/bufmgr.c
762:                    VacuumPageHit++;

src/backend/commands/vacuum.c
327:            VacuumPageHit = 0;

src/backend/commands/vacuumlazy.c
399:                                                     VacuumPageHit,

src/include/miscadmin.h
253:extern int  VacuumPageHit;
```

这说明在最新的版本中针对这个问题进行了修改，那可以确定这个 bug 被记录在案。

```shell
$ git blame -L 270,272 src/include/miscadmin.h
15d13e82911 (Alvaro Herrera 2020-02-05 16:59:29 -0300 270) extern int64 VacuumPageHit;
15d13e82911 (Alvaro Herrera 2020-02-05 16:59:29 -0300 271) extern int64 VacuumPageMiss;
15d13e82911 (Alvaro Herrera 2020-02-05 16:59:29 -0300 272) extern int64 VacuumPageDirty;
```

从上面可以看到 [15d13e82911](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=15d13e82911f7cc9f04f0bf419a96fd827fd1a9d) 这个提交针对 `VacuumPageHit` 的类型进行了修改，那么这个溢出的问题必定是在这个提交中被修复了，详细的提交信息如下所示。

	commit 15d13e82911f7cc9f04f0bf419a96fd827fd1a9d
	Author: Alvaro Herrera <alvherre@alvh.no-ip.org>
	Date:   Wed Feb 5 16:59:29 2020 -0300

    	Make vacuum buffer counters 64 bits wide

    	Using 32 bit counters means they can now realistically wrap around when
    	vacuuming extremely large tables.  Because they're signed integers,
    	stats printed by vacuum look very odd when they do.

    	We'd love to backpatch this, but refrain because the variables are
    	exported and could cause third-party code to break.

    	Reviewed-by: Julien Rouhaud, Tom Lane, Michael Paquier
    	Discussion: https://postgr.es/m/20200131205926.GA16367@alvherre.pgsql

提交信息验证了我的猜想，为了避免不必要的兼容性问题，这个 patch 并没有 backpatch 回其它分支，这个提交是在 13devel 中引入的，那么说明在 13 及其之后的版本都不会存在这个问题（前提是没有超过 `int64` 的范围）。

## 参考

[1] https://www.postgresql.org/message-id/20200131205926.GA16367@alvherre.pgsql

<div class="just-for-fun">
笑林广记 - 监生自大

城里监生与乡下监生各要争大，城里者耻之曰：“我们见多识广，你乡里人孤陋寡闻。”
两人争辩不已，因往大街同行各见所长。
到一大第门首，匾上“大中丞”三字，城里监生倒看指谓曰：“这岂不是‘丞中大’乃一徵验。”
又到一宅，匾额是“大理卿”，乡下监生以“卿”字认做“乡”字，忙亦倒念指之曰：“这是‘乡里大’了。”
两人各不见高下。又来一寺门首，上题“大士阁”，彼此平心和议曰：“原来阁（各）士（自）大。”
</div>
