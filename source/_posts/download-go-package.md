---
title: "Go 语言软件包下载"
date: 2020-05-18 21:46:28 +0800
category: 编程
tags:
  - Go
---


作为一个刚入门的 Go 小白来说，下载第三方包就成为了第一道坎 :( 。本文简要介绍一下如何下载 Go 软件包，尤其是 Google 系列的包。

<!-- more -->

本文基于 Go 1.13.4 版本，例如，我们要下载 `golang.org/x/tools` 包，由于某些不可抗力的原因，我们会遇到下面的错误：

```shell
$ go get golang.org/x/tools
package golang.org/x/tools: unrecognized import path "golang.org/x/tools" (https fetch: Get https://golang.org/x/tools?go-get=1: dial tcp 216.239.37.1:443: i/o timeout)
```

出现了问题，自然就有解决办法，毕竟国内也还是要进行 Go 语言开发的，因此，关于 Go 语言包的代理就应运而生，[goproxy](https://goproxy.io/) 就是其中之一。

根据介绍，我们可以设置 Go 的环境变量，如下所示：

```shell
$ go env -w GO111MODULE=on
$ go env -w GOPROXY="https://goproxy.io,direct"
```

随后，我们便可以正常下载 Go 语言包了。

``` shell
$ go get golang.org/x/tools
go: finding golang.org/x/tools latest
go: downloading golang.org/x/tools v0.0.0-20200515220128-d3bf790afa53
go: extracting golang.org/x/tools v0.0.0-20200515220128-d3bf790afa53
```

这是在 Go 1.13 及其之后的版本有效，对于之前的版本，我们可以采用如下方式：

```
# Enable the go modules feature
export GO111MODULE="on"
# Set the GOPROXY environment variable
export GOPROXY="https://goproxy.io"
```
