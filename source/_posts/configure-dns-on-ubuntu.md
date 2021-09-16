---
title: Ubuntu 系统 DNS 服务器配置
date: 2018-09-13 21:49:08
category: 杂项
tags:
  - DNS
---

域名系统 (Domain Name System, DNS) 是为连接到互联网或专用网络的计算机、服务或其他资源提供的一个分散且分级的命名系统。他可以理解为域名和 IP 地址相互映射的一个分布式数据库，通过域名系统，用户可以使用相对容易记忆的域名来访问互联网，而不用去记忆难以理解的 IP 字符串，由域名到 IP 地址转换的过程则被叫做域名解析。下图给出了一个典型的域名分级系统 (图片来源于维基百科)。

{% asset_img Domain_name_space.png Domain name space %}

<!-- more -->

在 Ubuntu 平台，我目前所了解到的 DNS 的配置主要有两种方式 (配置文件修改)：网络配置文件 interfaces 和域名解析配置文件 resolvconf。

### 网络配置文件

若是通过网络配置文件修改 DNS，那么我们只需要在 /etc/network/interfaces 文件中加入 nameserver 即可，如下所示：

``` text
dns-nameserver 114.114.114.114
dns-nameservers 8.8.8.8 8.8.4.4
```

dns-nameserver: 用于添加一个域名服务器，如果需要指定多个域名服务器则需要使用添加多行。
dns-nameservers: 用于同时指定多个域名服务器地址，用空格隔开。

通过这种方式修改 DNS 后需要重启电脑方可生效。

### 域名解析配置文件

Ubuntu 系统提供了 resolvconf 工具来管理其域名信息，其配置文件为在 /etc/resolvconf/resolv.conf.d/ 目录下，通过修改该目录下的 head 文件，我们可以添加特定的域名服务器。例如：

``` text
nameserver 114.114.114.114
nameserver 8.8.8.8
nameserver 8.8.4.4
```

在该文件中，每个域名服务器的地址单独一行，不能同时在一行上指定多个域名服务器。修改成功后，我们只需要运行 `sudo resolvconf -u` 更新 /etc/resolv.conf 文件即可。这种方式不需要重启电脑。此外，我们也可以直接在 /etc/resolv.conf 文件中添加域名服务器，但是这种方式添加的域名服务器在系统重启之后将失效，这是因为 /etc/resolv.conf 文件是由 resolvconf 命令生成的，重启后该文件将被重写。
