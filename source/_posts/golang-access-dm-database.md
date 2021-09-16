---
title: "Go 访问达梦数据库"
date: 2021-07-28 14:07:44
category: 编程
tags:
  - Go
  - 达梦
---

本文简要记录一下如何使用 Go 语言来访问达梦数据库。达梦数据库随安装包提供了 Go 语言的 driver，目前该 driver 仅支持 Windows 和 Linux 操作系统，不支持 MacOS 系统。

<!-- more -->

## 环境

本次的测试环境如下所示：

| 名称       | 版本     |
|------------|----------|
| Ubuntu     | 18.04    |
| Go         | go1.14.3 |
| 达梦数据库 | DM-V8    |

## 配置达梦数据库驱动

在安装完了达梦数据库之后，我们需要将安装目录下的 `drivers/go/dm-go-driver.zip` 文件解压到 `$GOROOT/src` 目录下。其官方文档说的是解压到 `$GOPATH/src` 路径下，经过测试不能正常工作，可能是由于 Go 语言版本导致的（包管理的方式发生了变化，本文采用 `GO111MODULE=on` 的方式进行包管理），官方采用的 `go1.13`，我在这里并没有进行详细的测试，毕竟我也仅仅是一名 Go 小白而已。

## 访问达梦数据库

首先，我们使用下面的命令初始化项目。

```shell
$ cd $GOPATH/src
$ mkdir dmtest && cd dmtest
$ go mod init dmtest
$ touch main.go
```

文件 `main.go` 的内容如下所示：

```go
package main

import (
    "database/sql"
    "fmt"
    _ "dm"
)

var (
    db  *sql.DB
    err error
)

func main() {
    driverName := "dm"
    dataSourceName := "dm://SYSDBA:123456789@10.9.10.184:5236"
    if db, err = connect(driverName, dataSourceName); err != nil {
        fmt.Println(err)
        return
    }

    if err = insertTable(); err != nil {
        fmt.Println(err)
        return
    }

    if err = selectTable(); err != nil {
        fmt.Println(err)
        return
    }

    fmt.Println("ok")
}

func connect(driverName string, dataSourceName string) (*sql.DB, error) {
    var db *sql.DB
    var err error
    if db, err = sql.Open(driverName, dataSourceName); err != nil {
        return nil, err
    }

    if err = db.Ping(); err != nil {
        return nil, err
    }
    fmt.Printf("connect to \"%s\" succeed.\n", dataSourceName)
    return db, nil
}

func insertTable() error {
    sql := "INSERT INTO tbl VALUES (1, 'world');"

    data, err := db.Exec(sql)
    if err != nil {
        return err
    }

    fmt.Printf("Insert data succeed: %v\n", data)
    return nil
}

func selectTable() error {
    sql := "SELECT * FROM tbl;"

    rows, err := db.Query(sql)
    if err != nil {
        return err
    }
    defer rows.Close()

    for rows.Next() {
        var id int
        var name string
        if err = rows.Scan(&id, &name); err != nil {
            return err
        }
        fmt.Printf("%v\t%v\n", id, name)
    }
    return nil
}
```

上面的代码创建一个连接，并向表中插入一条记录，随后再读取该记录。在这之前，我们需要先在达梦数据库中创建一个名为 `tbl` 的表，如下所示：

```sql
CREATE TABLE tbl (id int, name varchar(20));
```

编译上面的代码：

```shell
$ go build
go: finding module for package golang.org/x/text/encoding/ianaindex
go: finding module for package golang.org/x/text/message
go: finding module for package golang.org/x/text/encoding
go: finding module for package golang.org/x/text/language
go: finding module for package github.com/golang/snappy
go: found github.com/golang/snappy in github.com/golang/snappy v0.0.4
go: found golang.org/x/text/encoding in golang.org/x/text v0.3.6
```

运行时报段错误，如下所示：

```shell
$ ./dmtest
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x93e04e]

goroutine 1 [running]:
dm.(*Properties).GetTrimString(0x0, 0xa490a3, 0xc, 0x0, 0x0, 0x0, 0x0)
        /opt/go1.14.3/src/dm/zv.go:80 +0x3e
dm.(*DmConnector).mergeConfigs(0xc000014600, 0xa56519, 0x26, 0x108a8b0, 0x0)
        /opt/go1.14.3/src/dm/n.go:766 +0x855
dm.(*DmDriver).openConnector(0xc00005ae80, 0xa56519, 0x26, 0xa08c60, 0xc000106101, 0x7fca885b6038)
        /opt/go1.14.3/src/dm/p.go:78 +0xaf
dm.(*DmDriver).OpenConnector(0xc00005ae80, 0xa56519, 0x26, 0x7fca885b6038, 0xc00005ae80, 0x1, 0xc000045e88)
        /opt/go1.14.3/src/dm/p.go:62 +0x3f
database/sql.Open(0xa43c5f, 0x2, 0xa56519, 0x26, 0xc000070150, 0xa43c5f, 0x2)
        /opt/go1.14.3/src/database/sql/sql.go:754 +0x114
main.connect(0xa43c5f, 0x2, 0xa56519, 0x26, 0xc000045f48, 0x5cb1ba, 0xfaf920)
        /home/japin/Codes/gocode/src/dmtest/main.go:40 +0x56
main.main()
        /home/japin/Codes/gocode/src/dmtest/main.go:19 +0x5d
```

## 错误分析

从上面的错误代码可以猜测多半是由于 `dm/zv.go` 中的空指针导致的段错误。我们通过 gdb 来进行分析，重新编译程序。

```shell
$ go build -gcflags=all="-N -l"
```

接着使用 gdb 调试发现如下错误：

```shell
$ gdb ./dmtest
0x0000000000ace1ae in dm.(*Properties).GetTrimString (g=0x0, key=..., def=..., ~r2=...) at /opt/go1.14.3/src/dm/zv.go:80
80              value, ok := g.innerProps[strings.ToLower(key)]
(gdb) p g
$2 = (dm.Properties *) 0x0
(gdb) bt
#0  0x0000000000ace1ae in dm.(*Properties).GetTrimString (g=0x0, key=..., def=..., ~r2=...) at /opt/go1.14.3/src/dm/zv.go:80
#1  0x0000000000a4f76f in dm.(*DmConnector).mergeConfigs (c=0xc00007a000, dsn=..., ~r1=...) at /opt/go1.14.3/src/dm/n.go:766
#2  0x0000000000a54f00 in dm.(*DmDriver).openConnector (d=0xc000110e80, dsn=..., ~r1=0x0, ~r2=...) at /opt/go1.14.3/src/dm/p.go:78
#3  0x0000000000a54b8d in dm.(*DmDriver).OpenConnector (d=0xc000110e80, dsn=..., ~r1=..., ~r2=...) at /opt/go1.14.3/src/dm/p.go:62
#4  0x00000000006c4b8b in database/sql.Open (driverName=..., dataSourceName=..., ~r2=0x0, ~r3=...) at /opt/go1.14.3/src/database/sql/sql.go:754
#5  0x0000000000b03183 in main.connect (driverName=..., dataSourceName=..., ~r2=0x0, ~r3=...) at /home/japin/Codes/gocode/src/dmtest/main.go:40
#6  0x0000000000b02cde in main.main () at /home/japin/Codes/gocode/src/dmtest/main.go:19
```

可以看到这是由于 `GetTrimString()` 函数中调用 `g.innerProps[strings.ToLower(key)]` 导致的，因为变量 `g` 为空。那么 `g` 是什么呢？通过查看上层调用栈 `#1`，可以得到这里的 `g` 其实就是 `GlobalProperties`。

```
(gdb) up
#1  0x0000000000a4f76f in dm.(*DmConnector).mergeConfigs (c=0xc00007a000, dsn=..., ~r1=...) at /opt/go1.14.3/src/dm/n.go:766
766                     addressRemapStr = GlobalProperties.GetTrimString(AddressRemapKey, "")
(gdb)
```

通过查找 `GlobalProperties`，我们发现它是在 `zzm.go` 的 `load()` 函数中初始化的，代码如下所示：



```go
// filePath: dm_svc.conf 文件路径
func load(filePath string) {
        if filePath == "" {
                switch runtime.GOOS {
                case "windows":
                        filePath = os.Getenv("SystemRoot") + "\\system32\\dm_svc.conf"
                case "linux":
                        filePath = "/etc/dm_svc.conf"
                default:
                        return
                }
        }
        file, err := os.Open(filePath)
        defer file.Close()
        if err != nil {
                return
        }
        fileReader := bufio.NewReader(file)

        GlobalProperties = NewProperties()
        var groupProps *Properties
        var line string //dm_svc.conf读取到的一行

        ... ...
}
```

从这里可以看到达梦的 driver 程序会查找 `dm_svc.conf` 配置文件，仅当配置文件存在时才会初始化 `GlobalProperties` 变量。该文件在 Linux 配置默认在 `/etc/dm_svc.conf`，然而我并没有这个文件，所以导致 `GlobalProperties` 为空，从而出现段错误。

在安装完达梦数据库之后，它默认会在 `/etc` 目录下创建 `dm_svc.conf` 文件，由于数据库服务器和开发环境不是同一环境，因此开发环境默认没有 `/etc/dm_svc.conf` 文件，解决办法就是创建一个 `/etc/dm_svc.conf` 文件。重新运行程序，一切正常。

```
$ ./dmtest
connect to "dm://SYSDBA:123456789@10.9.10.184:5236" succeed.
Insert data succeed: {0xc000688080 0xc00009e000}
1       world
ok
```

## 总结

在查看达梦数据库提供的 driver 时，我发现达梦一个很有意思的地方，看下图：

{% asset_img dm_driver_directory.png %}

你是想做混淆吗？但是代码又放在那儿的。如果不是做混淆，那么还是建议取个有意义的文件名，毕竟是要自己维护的。

上述问题可能并不是特别难定位，但是从中还是可以看出一些问题。
1. 国产软件在健壮性方面还是有待加强。
2. 文档不够清晰。
3. 代码规范有待提高（当然这可能就是人家的特色）。

## 参考

[1] https://eco.dameng.com/docs/zh-cn/app-dev/go-go.html
[2] https://golang.org/doc/gdb


<div class="just-for-fun">
笑林广记 - 有理

一官最贪，一日拘两造对鞫，原告馈以五十金，被告闻知，加倍贿托。
及审时，不问情由，抽签竟打原告。
原告将手作五数势曰：“小的是有理的。”
官亦以手覆曰：“奴才，你虽有理。”
又以一手仰曰：“他比你更有理哩！”
</div>
