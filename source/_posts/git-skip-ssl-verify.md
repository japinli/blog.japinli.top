---
title: "Git 跳过 SSL 验证"
date: 2019-08-28 22:00:53 +0800
category: 杂项
tags:
  - git
---

有时，我们在克隆代码或者拉取代码时想要跳过 SSL 验证（至于为什么有这么奇葩的需求就不多说了，自行体会），git 提供了多种方式可供用户选择。

首先，我们看来看看克隆代码时如何跳过 SSL 验证。如下，我们可以使用 `GIT_NO_SSL_VERIFY` 环境变量来设置是否采用 SSL 验证。

``` shell
$ GIT_SSL_NO_VERIFY=true git clone https://github.com/xxx/xxx
```

如果是仓库已经采用 SSL 验证克隆下来，但是在随后的拉取过程中想要取消 SSL 验证，我们可以通过修改配置来完成，例如：

``` shell
$ git config http.sslVerify false
```

如果您想后续的仓库都跳过 SSL 验证，可以设置全局的 `http.sslVerify`，如下所示：

``` shell
$ git config --global http.sslVerify false
```
