---
title: "Seafile 与 OnlyOffice 在线预览 Office 文档"
date: 2020-05-16 10:42:38 +0800
category: 杂项
tags:
  - Seafile
---

最近，在公司采用 Seafile 搭建了一个文件服务器，并结合 OnlyOffice 实现在线预览功能。本文简要记录一下这个过程中所遇到的问题。

<!-- more -->

## 环境介绍

我使用了三台机器来构建整个系统，一台 nginx 服务器，用来作为前端代理；一台 Seafile 服务器用于存放文档；一台 OnlyOffice 服务器用来实现在线预览 Office 文档。

## 环境搭建

首先，我们按照 [Seafile 官方给出的部署方式][]安装 Seafile 服务器，然后采用 [Nginx 来代理 Seafile 的请求][]，最后使用 [OnlyOffice 实现在线预览][]。

__备注：__ OnlyOffice 在线预览需要开源版本 6.1.0+ 的 Seafile，本文采用的是 Seafile 7.0.5 版本。

## 遇到的问题

### 预览文件下载失败

在安装好之后，通过 Seafile 域名可以正常访问，并且访问 `http://example.seafile.com/onlyoffice/welcome` 可以得到 `Document Server is running` 结果，但是在打开 Word 文档预览时却提示下载失败。这是由于我使用域名来访问 Seafile，但是在 ccnet.conf 配置文件的 SERVICE_URL 配置却是 IP 地址格式导致的。我们可以在 Web 页面进行修改，也可以通过配置文件修改将其修改为域名形式即可，见参考文献 [2]。

### 预览文件暂时无法访问

随后，我又遇到文件暂时无法访问的问题，这同样是由于域名导致的，我采用 docker 的方式安装 OnlyOffice，通过查看日志（如下所示）发现它无法解析域名。

```
[2020-05-16T01:11:42.235] [ERROR] nodeJS - dnsLookup error: hostname = example.seafile.com
Error: getaddrinfo ENOTFOUND example.seafile.com
    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:56:26)
```

因此，我们需要在 docker 中添加正确的域名解析即可。

## 参考文献

[1] https://cloud.seafile.com/published/seafile-manual-cn/home.md
[2] https://bbs.seafile.com/t/topic/4528/2

[Seafile 官方给出的部署方式]: https://cloud.seafile.com/published/seafile-manual-cn/deploy/using_mysql.md
[Nginx 来代理 Seafile 的请求]: https://cloud.seafile.com/published/seafile-manual-cn/deploy/deploy_with_nginx.md
[OnlyOffice 实现在线预览]: https://cloud.seafile.com/published/seafile-manual-cn/deploy/only_office.md
