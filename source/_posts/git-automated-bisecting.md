---
title: "Git bisect 自动二分查找"
date: 2022-12-08 13:45:41 +0800
categories: 杂项
tags:
  - git
---

在 {% post_link git-bisect-in-practice Git bisect 二分查找实践 %}这篇文章中我们知道了如何通过 `git bisect` 来进行快速定位，但是，我们需要手动的去执行测试命令以确定哪个提交是正常的，哪个提交是异常的。本文记录了如何将 `git bisect` 的二分查找自动化。

<!--more-->

## 自动二分查找

`git bisect` 提供了一个 `run` 子命令，它将运行一个用户指定的命令来测试当前的提交是否符合预期。如果当前提交符合用户预期，那么用户提供的命令需要以 `0` 退出，否则用户命令需要以 `[1,127)` 的值退出，其中 `125` 保留特殊用途，其他任何值都将导致 `git bisect` 进程退出。

如果某个提交不能被测试，那么用户命令应返回 `125`，此时这个提交将被跳过，相当于执行 `git bisect skip`。

我们拿 PostgreSQL 中一个[关于 ICU 的示例](https://www.postgresql.org/message-id/CALDQics_oBEYfOnu_zH6yw9WR1waPCmcrqxQ8%2B39hK3Op%3Dz2UQ%40mail.gmail.com)来演示 `git bisect run` 的使用。我们可以写个简单的脚本来测试这个功能，脚本如下所示：

```bash
#!/bin/bash

export PGHOME=$PWD/pg
export PATH=$PGHOME/bin:$PATH
export LD_LIBRARY_PATH=$PGHOME/lib:$LD_LIBRARY_PATH
export PGDATA=$PGHOME/pgdata
export PGPORT=9230

cd /home/japin/Codes/postgresql/build
pg_ctl stop >stop.log 2>&1
rm -rf $(ls -I '*.sh')

../configure \
    --prefix=$PWD/pg \
    --enable-tap-tests \
    --enable-debug \
    --enable-cassert \
    --enable-depend \
    --with-icu \
    --with-llvm \
    --with-openssl \
    --with-python \
    --with-pam \
    CFLAGS='-O0 -Wmissing-prototypes -Wincompatible-pointer-types' \
    >configure.log 2>&1
make -j $(nproc) -s && make install -s
(cd contrib/ && make -j $(nproc) -s && make install -s)

initdb >initdb.log 2>&1 && pg_ctl -l log start >start.log 2>&1
psql postgres -c "CREATE COLLATION t (LC_COLLATE = 'en', LC_CTYPE = 'en', PROVIDER = 'icu', DETERMINISTIC = false);" 2>&1 | grep 'ERROR'
if test "$?" == "0" ; then
    exit 1
else
    exit 0
fi
```

`40b1491357` 为已知存在问题的提交，而 `bafad2c5b2` 是已知可以正常执行的提交。

```bash
$ git bisect start 40b1491357 bafad2c5b2
Bisecting: 1684 revisions left to test after this (roughly 11 steps)
[53ef6c40f1e7ff6c9ad9a221cd9999dd147ec3a2] Expose a few more PL/pgSQL functions to debugger plugins.
```

接着我们通过 `git bisect run` 来执行我们的脚本。

```bash
$ git bisect run build/myscript.sh
running ./build/myscrip.sh
ERROR:  parameter "locale" must be specified
Bisecting: 841 revisions left to test after this (roughly 10 steps)
[335474691054a74d771f0e7c24d25e800e3a37b6] Report any XLogReadRecord() error in XlogReadTwoPhaseData().
running ./build/myscrip.sh
Bisecting: 420 revisions left to test after this (roughly 9 steps)
[ba15f16107bea8a93edc505f3013cd7df4ac90fc] Add PostgreSQL::Test::Cluster::config_data()
running ./build/myscrip.sh
Bisecting: 210 revisions left to test after this (roughly 8 steps)
[3a46a45f6f009785b46188ed862afbccfb4cf56a] Add API of sorts for transition table handling in trigger.c
running ./build/myscrip.sh
Bisecting: 105 revisions left to test after this (roughly 7 steps)
[1c6bb380e5aba195204a9c6d0b4713bd1b3dec9c] Don't call fwrite() with len == 0 when writing out relcache init file.
running ./build/myscrip.sh
ERROR:  parameter "locale" must be specified
Bisecting: 52 revisions left to test after this (roughly 6 steps)
[eb8399cf1f3dd8ad02633e3bb84e2289d2debb44] Improve handling of SET ACCESS METHOD for ALTER MATERIALIZED VIEW
running ./build/myscrip.sh
ERROR:  parameter "locale" must be specified
Bisecting: 25 revisions left to test after this (roughly 5 steps)
[7e74aafc4335e743199c6c68ca9dd539053db9e5] Fix default signature length for gist_ltree_ops
running ./build/myscrip.sh
Bisecting: 12 revisions left to test after this (roughly 4 steps)
[f512efb2d50ab78e7610f0e3801925f22ebec611] Fix header inclusion order in pg_receivewal.c
running ./build/myscrip.sh
ERROR:  parameter "locale" must be specified
Bisecting: 6 revisions left to test after this (roughly 3 steps)
[25e777cf8e547d7423d2e1e9da71f98b9414d59e] Split ExecUpdate and ExecDelete into reusable pieces
running ./build/myscrip.sh
ERROR:  parameter "locale" must be specified
Bisecting: 2 revisions left to test after this (roughly 2 steps)
[c91f71b9dc91ef95e1d50d6d782f477258374fc6] Fix publish_as_relid with multiple publications
running ./build/myscrip.sh
Bisecting: 0 revisions left to test after this (roughly 1 step)
[f2553d43060edb210b36c63187d52a632448e1d2] Add option to use ICU as global locale provider
running ./build/myscrip.sh
ERROR:  parameter "locale" must be specified
Bisecting: 0 revisions left to test after this (roughly 0 steps)
[f6f0db4d62400ff88f523dcc4d7e25f9506bc0d8] Fix pg_tablespace_location() with in-place tablespaces
running ./build/myscrip.sh
f2553d43060edb210b36c63187d52a632448e1d2 is the first bad commit
commit f2553d43060edb210b36c63187d52a632448e1d2
Author: Peter Eisentraut <peter@eisentraut.org>
Date:   Thu Mar 17 11:11:21 2022 +0100

    Add option to use ICU as global locale provider

    This adds the option to use ICU as the default locale provider for
    either the whole cluster or a database.  New options for initdb,
    createdb, and CREATE DATABASE are used to select this.

    Since some (legacy) code still uses the libc locale facilities
    directly, we still need to set the libc global locale settings even if
    ICU is otherwise selected.  So pg_database now has three
    locale-related fields: the existing datcollate and datctype, which are
    always set, and a new daticulocale, which is only set if ICU is
    selected.  A similar change is made in pg_collation for consistency,
    but in that case, only the libc-related fields or the ICU-related
    field is set, never both.

    Reviewed-by: Julien Rouhaud <rjuju123@gmail.com>
    Discussion: https://www.postgresql.org/message-id/flat/5e756dd6-0e91-d778-96fd-b1bcb06c161a%402ndquadrant.com

[...]
bisect run success
```

从上面的结果我们可以看到，整个过程不需要人为介入，通过 11 次查询，我们就找到了引入问题的提交，相当的方便。

## 参考

[1] https://lwn.net/Articles/317154/
[2] https://git-scm.com/docs/git-bisect/#_bisect_run

<div class="just-for-fun">
笑林广记 - 蒜治口臭

一口臭者问人曰：“治口臭有良方乎？”
答曰：“吃大蒜极好。”
问者讶其臭，曰：“大蒜虽臭。还臭得正路。”
</div>
