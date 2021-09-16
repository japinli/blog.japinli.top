---
title: "Ping 权限拒绝"
date: 2018-09-06 22:30:40 +0800
category: 杂项
tags:
  - ping
---

今天在 CentOS 上遇到一个奇怪的问题，ping 程序在 root 用户下能正常使用，但是在非 root 用户下则出现如下错误：

``` shell
user@host:~ $ ping 127.0.0.1
ping: socket: Permission denied
```

在 StackExchage 上也有人遇到了[类似的问题][]，他需要在 PHP 中调用 ping 命令，并且他通过执行 `setenforce 0` 可以让 ping 命令正常使用，但是经我测试发现这种方法对我无效。

之后在 LinuxQuestions 上发现[有人][]指出 ping 命名将创建原始套接字而非 TCP 套接字，然而 Linux 系统对于普通用户创建原开套接字是禁止的，因此我们就看到了文章开始的错误，针对这一问题他也提出了解决方案，即为 ping 命令添加 suid 权限。

``` shell
user@host:~ $ chmod +s /bin/ping
user@host:~ $ ls -al /bin/ping
-rwsr-xr-x 1 root root 64424 Mar 10  2017 /bin/ping
```

<!-- more -->

那么什么是 suid 权限呢？我们所熟悉的文件权限包括读、写和可执行 (r/w/x) 三种权限，其实在 Linux 系统中对所有文件还有三种特殊的权限说明，即 SUID, SGID 和 Sticky Bits。

### Sticky Bit

由于 Unix 是多用户操作系统并且设计为多个用户可以同时使用，而 Sticky Bit 则告诉 Unix 系统一旦程序被执行，那么他将一直保留在内存当中，这样可以避免不同用户执行同一程序进行多次加载。在设置了 Sticky Bit 位后，当一个用户使用了这个程序，另一个用户再次使用时可以避免初始化该程序的过程。Sticky Bit 的概念在快速磁盘访问 (Fast Disk Access) 和内存访问技术 (Memory Access Technologies) 出现之前非常有用。随着技术的发展程序加载到内存的时间的减少，Sticky Bit 的概念逐渐被废弃，因此，目前 Sticky Bit 的作用不是很明显。需要注意的是 Sticky Bit 只能用于可执行文件。

### SUID (Set User ID) Bit

SUID (Set User ID) 意味着当执行应用程序时，用户的 ID 将被设置为文件或程序所有者的 ID 而不是当前用户的 ID。例如，假设我有一个应用程序他的所有者为 root 并且设置和了 SUID 位，那么当我以普通用户运行该应用程序时，该应用程序依然会以 root 身份运行。这是由于 SUID 位告诉 Linux 系统为该应用程序设置 root 用户的 ID，并且在运行时始终以 root 用户的身份去运行该应用程序 (此处文件的所有者为 root 用户)。

``` shell
$ # 设置文件 SUID 位
$ chmod u+s filename
$ # 去掉文件 SUID 位
$ chmod u-s filename
```

### SGID (Set Group ID) Bit

SGID (Set Group ID) 与 SUID 类似，他意味着文件执行时设置其执行的用户组 ID。通常情况下，在 Linux/Unix 系统中程序运行时会继承当前登录用户的权限。SGID 则可以给运行的程序临时修改有效用户组为文件所属的组。

``` shell
$ # 设置文件 SGID 位
$ chmod g+s filename
$ # 去掉文件 SGID 位
$ chmod g-s filename
```

### 参考

1. [What are the SUID, SGID and the Sticky Bits?](http://www.codecoffee.com/tipsforlinux/articles/028.html)


[类似的问题]: https://unix.stackexchange.com/questions/385980/ping-socket-permission-denied
[有人]: https://www.linuxquestions.org/questions/linux-embedded-and-single-board-computer-78/socket-permission-denied-915704/
