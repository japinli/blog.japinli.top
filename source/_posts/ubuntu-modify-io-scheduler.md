---
title: "Ubuntu 修改 I/O 调度算法"
date: 2019-03-11 21:39:41 +0800
category: Misc
tags:
  - Scheduler
  - Ubuntu
---

Linux I/O 调度器控制着内核读写磁盘的工作方式。系统管理员可以通过更改调度器来自定义磁盘调度算法，从而优化系统性能。有三种调度程序可供选择，每种调度程序都有其优点。这些调度器是：

* __Noop__ - 电梯调度算法，最简单的调度算法，该算法基于先进先出队列 (FIFO) 实现，所有的 I/O 请求都符合先进先出规则，适合于 SSD 设备。

* __Deadline__ - 绝对保障算法，它为读和写分别创建了 FIFO 队列，当内核收到请时，先尝试合并，不能合并则尝试排序或放入队列中，并且尽量保证在请求到达最终期限时进行调度，避免有一些请求长时间不能得到处理。该调度器适合虚拟机所在宿主机器或 I/O 压力比较重的场景，例如数据库服务器。

* __Completely Fair Queuing, CFQ__ - 绝对公平调度算法，它为每个进程和线程单独创建一个队列来管理该进程的 I/O 请求，然后为每个队列分配访问磁盘的时间片。时间片的长度以及允许队列提交的请求数取决于给定进程的 I/O 优先级。该调度器比较适合于通用服务器。

<!-- more -->

## 查询当前调度器

首先，我们需要知道系统目前使用的是哪种 I/O 调度器。假设我们有一块名为 `sda` 的磁盘，那么我们可以通过如下命令查看该磁盘使用的调度器类别。

``` shell
$ cat /sys/block/sda/queue/scheduler
noop [deadline] cfq
```

从上面可以看到我们的系统在 `sda` 磁盘上支持 `noop`，`deadline` 和 `cfq` 三种调度器，而默认采用的是 `deadline` 调度器。

## 修改调度器

Ubuntu 系统提供了两种方式来修改调度器：a) 临时修改；b) 永久修改。临时修改的方式在系统重启后将会恢复到默认设置。通常，我们可以通过临时修改的方式来确定哪种调度器能带来更大的性能提升，然后在永久的修改为这种调度器。

我们可以通过下面的命令将系统的调度器临时的修改为 `noop` 类型：

``` shell
$ sudo echo noop > /sys/block/sda/queue/scheduler
```

通过上述方式修改不需要重启机器而是立马生效。如果你需要永久的修改调度器，那么你需要修改 GRUB 的配置文件，即编辑配置文件 `/etc/default/grub` 修改

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
```

为

```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash elevator=noop"
```

通过这种方式修改我们需要重启机器以使修改生效，当然我们可以结合临时修改的方式，从而避免重启。

## 参考

[1] 谭峰，张文升《PostgreSQL 实战》
[2] [How to change the linux io scheduler to fit your needs](https://www.techrepublic.com/article/how-to-change-the-linux-io-scheduler-to-fit-your-needs/)
