---
title: "Greenplum 数据库 semctl 失败之无效参数"
date: 2019-07-09 21:27:39 +0800
category: 数据库
tags:
  - Greenplum
---

在编译完成之后对 Greenplum 数据库进行安装测试时遇到如下问题，

```
psql: FATAL:  semctl(592740353, 7, SETVAL, 0) failed: Invalid argument (pg_sema.c:151)
```

从而导致数据库启动失败，从错误结果来看应该是与信号量相关。那么具体是怎么回事呢？

文献 <a href="https://wiki.postgresql.org/wiki/Systemd">[1]</a> 中给出了关于这个错误的详细说明，问题是由 System V IPC 对象导致的。

配置文件 `logind.conf` 中的 `RemoveIPC` 参数控制着 System V IPC 对象是否在用户完全退出的情况下被清除（系统用户排除在外）。在 `systemd 212` 版本之后这个选项默认是开启的，即 `RemoveIPC=yes`。仍在被使用的共享内存段不会被清理，因此 `systemd` 不会去清理正在使用的共享内存段；但是信号量没有进程附加的概念，因此，当用户退出或进程终止时，即便该信号量正在被使用也会被清理（这里的理解不一定正确，建议直接看原文）。

<!-- more -->

## 解决办法

在了解了问题的本质之后，我们来看看如何解决这个问题。正如前面所说的，系统用户可以免除这个问题的困扰，那么我们的第一种方法就是建立一个系统用户，然后使用这个用户来运行数据库（`useradd -r` 命令）。

不过，还是比较推荐第二种方式，即修改 `RemoveIPC` 为 `RemoveIPC=no`，随后重启 `systemd-logind`。Ubuntu 下的做法如下：

```
$ echo "RemoveIPC=no" >> /etc/systemd/logind.conf
$ systemctl restart systemd-logind
```

## 参考

[1] https://wiki.postgresql.org/wiki/Systemd
[2] https://www.postgresql.org/message-id/flat/1481075896588-5933635.post%40n3.nabble.com
[3] [BUG #13818: PostgreSQL crashes after cronjob runs as "postgres"](https://www.postgresql.org/message-id/CAK7tEys9-O4BTERbs3Xuk2BfFNNd55u2sM9j5R2Fi7v6BHjrQw@mail.gmail.com)
