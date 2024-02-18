---
title: "pg-trunk 简化 PostgreSQL 插件安装"
date: 2023-12-19 22:08:18 +0800
categories: 数据库
tags:
  - PostgreSQL
  - pg-trunk
---

{% asset_img pg-trunk.jpg %}

最近发现一个可以快速、方便地安装 PostgreSQL 插件的工具 [pg-trunk](https://pgt.dev/)。它是由 [Tembo](https://tembo.io/) 提供的 PostgreSQL 扩展的开源包管理器和注册表。

<!--more-->

## 安装 pg-trunk

[pg-trunk](https://pgt.dev/) 的安装十分简单，它依赖 [rust](https://www.rust-lang.org)，因此需要先安装 [rust](https://www.rust-lang.org/tools/install)。

```bash
$ curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
$ source "$HOME/.cargo/env"
$ cargo install pg-trunk
```

执行完上述命令之后，[pg-trunk](https://pgt.dev/) 就安装完成了，它提供了一个名为 `trunk` 的程序，用于编译、安装和发布插件。

## 安装插件

在使用 `trunk` 时，需要确保 `pg_config` 在环境变量中，`trunk` 将使用 `pg_config` 来确认安装路径。

```bash
$ psql postgres -c "SELECT * FROM pg_available_extensions WHERE name = 'pgmq'"
 name | default_version | installed_version | comment
------+-----------------+-------------------+---------
(0 rows)

$ trunk install pgmq

$ psql postgres -c "SELECT * FROM pg_available_extensions WHERE name = 'pgmq'"
 name | default_version | installed_version |                               comment
------+-----------------+-------------------+---------------------------------------------------------------------
 pgmq | 1.1.0           |                   | A lightweight message queue. Like AWS SQS and RSMQ but on Postgres.
(1 row)
```

从上面可以看到，仅需要执行 `trunk install` 就可以完成 PostgreSQL 插件的安装，十分的方便。我们尝试在数据库中安装该插件：

## 编译 & 注册插件

`trunk` 除了安装插件外，还提供了编译插件与注册的功能，例如，我们想要编译 `pgmq` 插件，可以使用下面的命令进行。

```bash
$ git clone https://github.com/tembo-io/pgmq.git
$ cd pgmq
$ trunk build
[...]
Creating package at: ./.trunk/pgmq-1.1.0.tar.gz
Fetching extension_name from control file: extension/pgmq.control
Using extension_name: pgmq
Create Trunk bundle:
        pgmq.so
[...]
        extension/pgmq--1.1.0.sql
        extension/pgmq.control
        manifest.json
Packaged to ./.trunk/pgmq-1.1.0.tar.gz
```
上面的命令将使用 Docker 编译 `pgmq` 插件。我们可以使用 `trunk install -f .trunk/pgmq-1.1.0.tar.gz pgmq` 命令进行安装。

最后，我们可以将编译的插件发布如 `pgt.dev` 上。

```bash
$ trunk publish pgmq \
  --version 1.1.0 \
  --description "Message Queue for postgres" \
  --documentation "https://github.com/tembo-io/pgmq" \
  --repository "https://github.com/tembo-io/pgmq" \
  --license "Apache-2.0" \
  --homepage "https://www.tembo.io"
```

## 参考

[1] https://pgt.dev
[2] https://www.rust-lang.org

<div class="just-for-fun">
笑林广记 - 路上屁

昔有三人行令。要上山见一古人，下山又见一古人，半路见一物件，后句要总结前后二句。
一人曰：“上山遇见狄青，下山遇见李白，路上拾得一瓶酒，不知是青酒是白酒。”
一人曰：“上山遇见樊哙，下山遇见赵盾，路上拾得一把剑，不知是快剑是钝剑。”
一人云：“上山遇见林放，下山遇见贾岛，路上拾得一个屁，不知是放的屁、岛的屁。”
</div>
