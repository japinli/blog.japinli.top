---
title: "Golang cron v3 定时任务"
date: 2021-08-06 23:17:59 +0800
category: 编程
tags:
  - Go
---

最近由于工作原因，需要在 Golang 中创建一个定时任务来执行一些工作。在 Linux 中，我们可以通过 crontab 来实现这个功能；在 Golang 中也有一个名为 [cron][] 的包，通过它我们可以很方便地在 Golang 中实现定时任务，本文简要记录了 [cron][] 的使用方法。

{% asset_img crontab-guru.jpg %}

<!-- more -->

## 最小示例

首先我们创建一个最小示例来看看 `cron` 是如何工作的，如下所示。

```shell
$ mkdir crontest
$ cd crontest && go mod init crontest
$ touch main.go
```

文件 `main.go` 中的内容如下所示：

```go
package main

import (
    "fmt"
    "time"

    "github.com/robfig/cron/v3"
)

func main() {
    c := cron.New()

    c.AddFunc("*/1 * * * *", func() {
        fmt.Println("Execute cron task at %s\n", time.Now().String())
    })

    c.Start()
	defer c.Stop()

    select {}
}
```

接着，我们使用 `go build` 来编译，并运行该程序，可以得到如下输出。

```shell
$ ./crontest
Execute cron task at 2021-08-06 20:29:00.000304257 +0800 CST m=+12.310669667
Execute cron task at 2021-08-06 20:30:00.00037062 +0800 CST m=+72.310736162
Execute cron task at 2021-08-06 20:31:00.000493635 +0800 CST m=+132.310859212
Execute cron task at 2021-08-06 20:32:00.000351753 +0800 CST m=+192.310717288
Execute cron task at 2021-08-06 20:33:00.000309421 +0800 CST m=+252.310674994
Execute cron task at 2021-08-06 20:34:00.000350467 +0800 CST m=+312.310716002
Execute cron task at 2021-08-06 20:35:00.000311664 +0800 CST m=+372.310677063
Execute cron task at 2021-08-06 20:36:00.000345813 +0800 CST m=+432.310711346
Execute cron task at 2021-08-06 20:37:00.000545952 +0800 CST m=+492.310911501
```

我们通过 `cron.New()` 来创建一个 cron 作业运行器，接着，通过 `c.AddFunc()` 函数向 cron 作业运行器中添加一个按指定时间运行的任务，该函数的第一个参数指定了定时表达式，第二个参数则是由匿名函数提供的具体需要完成的任务，在这里我们仅仅是输出一条日志。最后，调用 `c.Start()` 函数启动 cron 调度程序。

默认情况下，所有解释和调度都在机器的本地时区 (time.Local) 中完成。我们也可以在构建时指定不同的时区：

```go
cron.New(cron.WithLocation(time.UTC))
```

### 定时表达式

定时表达式从左到由分别是 `Minutes`，`Hours`，`Day of month`，`Month` 和 `Day of week`。

| 域名         | 必须 | 允许的值        | 允许的特殊字符 |
|--------------|------|-----------------|----------------|
| Minutes      | Yes  | 0-59            | * / , -        |
| Hours        | Yes  | 0-23            | * / , -        |
| Day of month | Yes  | 1-31            | * / , - ?      |
| Month        | Yes  | 1-12 or JAN-DEC | * / , -        |
| Day of week  | Yes  | 0-6 or SUN-SAT  | * / , - ?      |

`Month` 和 `Day of Week` 的值不区分大小写，例如 `SUN`，`Sun` 和 `sun` 是一样的。

- `*` - 表示 cron 表达式将匹配字段的所有值；例如，在第 5 个字段（月）中使用星号表示每个月。
- `/` - 表示描述范围的增量。例如，第 1 个字段（分钟）中的 `3-59/15` 将表示一小时的第 3 分钟，此后每 15 分钟一次。
- `,` - 用于分隔列表中的项目。例如，在第 5 个字段（星期几）中使用 `MON`，`WED`，`FRI` 表示星期一、星期三和星期五。
- `-` - 用于定义范围。例如，`9-17` 表示上午 9 点到下午 5 点之间的每小时。
- `?` - 可以使用问号代替 `*` 以将月中的某天或一周中的某天留空。

### 预定义时间表

[cron][] 提供了多个预定义计划之一来代替 cron 表达式。

| 预定义值               | 描述                            | 等同于    |
|------------------------|---------------------------------|-----------|
| @yearly (or @annually) | 每年的 1 月 1 日午夜运行一次    | 0 0 1 1 * |
| @monthly               | 每月的第一天午夜运行一次        | 0 0 1 * * |
| @weekly                | 每周周六/周日之间的午夜运行一次 | 0 0 * * 0 |
| @daily (or @midnight)  | 每天午夜运行一次                | 0 0 * * * |
| @hourly                | 每小时开始时运行一次            | 0 * * * * |

由于添加 Seconds 是对标准 cron 规范最常见的修改，因此 cron 提供了一个内置函数来执行此操作。

```go
cron.New(cron.WithSeconds())
```

例如，我们将上述代码进行修改，使其支持秒级别的定时任务，代码如下所示：

```go
func main() {
    c := cron.New(cron.WithSeconds())

    c.AddFunc("*/5 * * * * *", func() {
        fmt.Println("Execute cron task at %s\n", time.Now().String())
    })

    c.Start()
	defer c.Stop()

    select {}
}
```

下面是执行结果。

```
$ ./crontest
Execute cron task at 2021-08-06 21:29:10.000409533 +0800 CST m=+1.862999190
Execute cron task at 2021-08-06 21:29:15.000346401 +0800 CST m=+6.862936200
Execute cron task at 2021-08-06 21:29:20.000336872 +0800 CST m=+11.862926638
Execute cron task at 2021-08-06 21:29:25.00041627 +0800 CST m=+16.863006019
Execute cron task at 2021-08-06 21:29:30.000354942 +0800 CST m=+21.862944684
Execute cron task at 2021-08-06 21:29:35.000375026 +0800 CST m=+26.862964792
```

## 使用 Job 来创建定时任务

上面我们通过 `AddFunc()` 函数来创建了一个定时任务，实际上通过查看 [cron][] 的源码，我们可以发现其本质也是封装成一个 Job 来调用，如下所示：

```go
// FuncJob is a wrapper that turns a func() into a cron.Job
type FuncJob func()

func (f FuncJob) Run() { f() }

// AddFunc adds a func to the Cron to be run on the given schedule.
// The spec is parsed using the time zone of this Cron instance as the default.
// An opaque ID is returned that can be used to later remove it.
func (c *Cron) AddFunc(spec string, cmd func()) (EntryID, error) {
    return c.AddJob(spec, FuncJob(cmd))
}
```

下面我们尝试通过 `AddJob()` 的方式来创建定时任务。

```go
package main

import (
    "fmt"
    "time"

    "github.com/robfig/cron/v3"
)

type Job1 struct {}
type Job2 struct {}

func (this Job1) Run() {
    fmt.Printf("Run job1 at %s\n", time.Now().String())
}

func (this Job2) Run() {
    fmt.Printf("Run job2 at %s\n", time.Now().String())
}

func main() {
    c := cron.New(cron.WithSeconds())

    c.AddFunc("*/5 * * * * *", func() {
        fmt.Printf("Execute cron task at %s\n", time.Now().String())
    })

    c.AddJob("*/10 * * * * *", Job1{})
    c.AddJob("*/30 * * * * *", Job2{})

    c.Start()
    defer c.Stop()

    select {}
}
```

上面的代码中，我们定义了两个结构体 `Job1` 和 `Job2`，为了满足 cron 的需要，它们必须实现 `Run()` 这个接口。在 `Run()` 接口中我们输出两个日志信息，这个就是我们定时任务所做的全部工作，然后通过 `c.AddJob()` 添加 Job 即可。程序执行过程如下所示。

```shell
$ ./crontest
Execute cron task at 2021-08-06 22:08:15.000392468 +0800 CST m=+2.864996300
Run job1 at 2021-08-06 22:08:20.000339425 +0800 CST m=+7.864943177
Execute cron task at 2021-08-06 22:08:20.000494832 +0800 CST m=+7.865098624
Execute cron task at 2021-08-06 22:08:25.000372842 +0800 CST m=+12.864976583
Execute cron task at 2021-08-06 22:08:30.000453832 +0800 CST m=+17.865057603
Run job2 at 2021-08-06 22:08:30.000418619 +0800 CST m=+17.865022319
Run job1 at 2021-08-06 22:08:30.000472417 +0800 CST m=+17.865076204
Execute cron task at 2021-08-06 22:08:35.000387698 +0800 CST m=+22.864991512
Run job1 at 2021-08-06 22:08:40.000350366 +0800 CST m=+27.864954043
Execute cron task at 2021-08-06 22:08:40.000375622 +0800 CST m=+27.864979303
Execute cron task at 2021-08-06 22:08:45.000366659 +0800 CST m=+32.864970478
Run job1 at 2021-08-06 22:08:50.000284729 +0800 CST m=+37.864888549
Execute cron task at 2021-08-06 22:08:50.000341062 +0800 CST m=+37.864944800
```

最后，在推荐一个简单快捷的 crontab 编辑工具 [crontab guru][https://crontab.guru/]。

## 参考

[1] https://pkg.go.dev/github.com/robfig/cron/v3


<div class="just-for-fun">
笑林广记 - 取金

一官出朱票，取赤金二锭，铺户送讫，当堂领价。
官问：“价值几何？”
铺家曰：“平价该若干，今系老爷取用，只领半价可也。”
官顾左右曰：“这等，发一锭还他。”
发金后，铺户仍候领价。
官曰：“价已发过了。”
铺家曰：“并未曾发。”
官怒曰：“刁奴才，你说只领半价，故发一锭还你，抵了一半价钱，本县不曾亏你，如何胡缠？快撵出去！”
</div>

[cron]: https://github.com/robfig/cron
