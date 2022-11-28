---
title: "PostgreSQL 调试 checkpointer 进程"
date: 2022-11-28 13:44:28 +0800
categories: 数据库
tags:
  - PostgreSQL
---

Checkpointer 进程负责将 PostgreSQL 数据库中的脏页刷到磁盘中，当我们通过 GDB 附加到 checkpointer 进程之后，通过执行 `CHECKPOINT` 语句发现不能触发后续的 checkpoint 代码。本文针对这个问题简要介绍一下如何调试 PostgreSQL 数据库的 checkpointer 进程。

<!--more-->

## 现象

当我们通过 GDB 附加到 checkponter 进程之后，我们可以在 `CheckpointerMain()` 函数的 `for` 循环中打断点来跟踪其执行流程，这里我断点打在 `HandleCheckpointerInterrupts()` 函数上，因此，每次循环都将执行该函数。

```bash
$ sudo gdb -p $(ps -ef | awk '$NF ~ /checkpointer/ {print $2}')
(gdb) b HandleCheckpointerInterrupts
```

随后，我们新建一个连接，并执行 `CHECKPOINIT` 语句。

```bash
$ psql postgres
postgres=# CHECKPOINT;
```

我们在 GDB 的窗口中，可以看到如下所示的信息。

```bash
Program received signal SIGINT, Interrupt.
0x00007f83751d342a in epoll_wait (epfd=8, events=0x55afd620a668, maxevents=1, timeout=299000) at ../sysdeps/unix/sysv/linux/epoll_wait.c:30
30      ../sysdeps/unix/sysv/linux/epoll_wait.c: No such file or directory.
(gdb)
Continuing.
```

此时，psql 进程也阻塞在了 `CHECKPOINT` 语句上，我们可以通过 `Ctrl-C` 来结束 `CHECKPOINT` 的执行。这是为什么呢？

## 分析

通过分析 `RequestCheckpoint()` 函数，可以看到它实际上是向 checkpointer 进程发送了 SIGINT 信号，如下所示。

```c
void
RequestCheckpoint(int flags)
{
    [...]

    for (ntries = 0;; ntries++)
    {
        if (CheckpointerShmem->checkpointer_pid == 0)
        {
            if (ntries >= MAX_SIGNAL_TRIES || !(flags & CHECKPOINT_WAIT))
            {
                elog((flags & CHECKPOINT_WAIT) ? ERROR : LOG,
                     "could not signal for checkpoint: checkpointer is not running");
                break;
            }
        }
        else if (kill(CheckpointerShmem->checkpointer_pid, SIGINT) != 0)
        {
            if (ntries >= MAX_SIGNAL_TRIES || !(flags & CHECKPOINT_WAIT))
            {
                elog((flags & CHECKPOINT_WAIT) ? ERROR : LOG,
                     "could not signal for checkpoint: %m");
                break;
            }
        }
        else
            break;              /* signal sent successfully */

        CHECK_FOR_INTERRUPTS();
        pg_usleep(100000L);     /* wait 0.1 sec, then retry */
    }

    [...]
}
```

但是，当我们在通过 GDB 附加进程之后，SIGINT 信号被 GDB 拦截了并且不会向程序发送 SIGINT 信息，因此导致 checkpointer 进程始终接收不到 SIGINT 信号。我们可以通过 GDB 的 `info signals` 命令看到 GDB 拦截的信号。

```bash
(gdb) info signals
Signal        Stop      Print   Pass to program Description

SIGHUP        Yes       Yes     Yes             Hangup
SIGINT        Yes       Yes     No              Interrupt
SIGQUIT       Yes       Yes     Yes             Quit
SIGILL        Yes       Yes     Yes             Illegal instruction
SIGTRAP       Yes       Yes     No              Trace/breakpoint trap
SIGABRT       Yes       Yes     Yes             Aborted
SIGEMT        Yes       Yes     Yes             Emulation trap
SIGFPE        Yes       Yes     Yes             Arithmetic exception
SIGKILL       Yes       Yes     Yes             Killed
SIGBUS        Yes       Yes     Yes             Bus error
SIGSEGV       Yes       Yes     Yes             Segmentation fault
SIGSYS        Yes       Yes     Yes             Bad system call
[...]
```

因此，我们可以在 GDB 的命令行中手动的向 checkpointer 进程发送 SIGINT 信号来触发后续的 checkpoint 代码流程。

```bash
(gdb) c
Continuing.

Program received signal SIGINT, Interrupt.
0x00007f83751d342a in epoll_wait (epfd=8, events=0x55afd620a668, maxevents=1, timeout=169802) at ../sysdeps/unix/sysv/linux/epoll_wait.c:30
30      in ../sysdeps/unix/sysv/linux/epoll_wait.c
(gdb) signal SIGINT
Continuing with signal SIGINT.

Breakpoint 1, HandleCheckpointerInterrupts ()
    at /home/japin/Codes/postgresql/Debug/../src/backend/postmaster/checkpointer.c:545
(gdb)
```

接着，我们便可以跟踪后续的 checkpoint 执行流程，例如：

```bash
(gdb) b CreateCheckPoint
Breakpoint 2 at 0x55afd4492083: file /home/japin/Codes/postgresql/Debug/../src/backend/access/transam/xlog.c, line 6441.
(gdb) c
Continuing.

Breakpoint 2, CreateCheckPoint (flags=32766)
    at /home/japin/Codes/postgresql/Debug/../src/backend/access/transam/xlog.c:6441
```

## 参考

[1] [Debugging a program that uses SIGINT with gdb](https://stackoverflow.com/questions/36993909/debugging-a-program-that-uses-sigint-with-gdb)

<div class="just-for-fun">
笑林广记 - 过桥嚏

一乡人自城中归，谓其妻曰：“我在城里打了无数喷嚏。”
妻曰：“皆我在家想你之故。”
他日挑粪过危桥，复连打数嚏几乎失足，乃骂曰：“骚花娘，就是思量我，也须看什么所在！”
</div>
