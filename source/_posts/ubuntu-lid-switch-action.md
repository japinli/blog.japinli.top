---
title: "Ubuntu 笔记本盖住不挂机"
date: 2020-03-08 12:20:23 +0800
category: 杂项
tags:
  - Ubuntu
---

我有一台旧笔记本装有 Ubuntu 18.04 系统，希望把它当作一个服务器，这时我就需要在盖住笔记本时系统不休眠。

Ubuntu 系统中提供了 Login Manager 来管理这些行为，它的配置文件为 /etc/systemd/logind.conf。通过
`man logind.conf` 我们可以看到其详细说明。

其中有一项 `HandleLidSwitch`，它控制了笔记本盖住的行为，默认情况下是 `suspend`，我们可以将其修改为 `ignore` 即可以实现我们的目的。例如，我们修改 /etc/system/logind.conf 文件中的

```
#HandleLidSwitch=suspend
```

行修改为

```
HandleLidSwitch=ignore
```

然后重启 systemd-logind 服务即可。

``` shell
$ sudo service systemd-logind restart
```
