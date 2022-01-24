---
title: "OpenSSH 私钥转 RSA 私钥"
date: 2022-01-24 12:11:58 +0800
categories: 杂项
tags:
  - OpenSSH
  - RSA
---

今天遇到关于私钥格式的问题，需要通过远程连接访问远端的服务器，该服务器是客户给的，然后通过 ssh 的方式访问，然而客户给的私钥是如下形式的：

```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAA...
-----END OPENSSH PRIVATE KEY-----
```

通过 ssh 连接时报无效的格式，`Load key "~/.ssh/openssh_id_rsa": invalid format`。本文简要记录一下解决方法。

<!--more-->

## 解决

我们可以通过工具将其转换为 `RSA` 格式的私钥，需要使用到 putty 工具。

```shell
$ sudo apt-get install putty
```

首先，我们通过 puttygen 将 OpenSSH 的私钥转换为 SSHv2 的中间格式。

```shell
$ puttygen ~/.ssh/openssh_id_rsa -O private-sshcom -o ~/.ssh/sshv2_id_rsa
```

其中 `~/.ssh/openssh_id_rsa` 是原始的 OpenSSH 私钥文件，`~/.ssh/sshv2_id_rsa` 是生成的中间文件（SSHv2 格式），其格式如下所示：

```
---- BEGIN SSH2 ENCRYPTED PRIVATE KEY ----
P2/56wAABa4AAAA3aWYtbW9kbntzaWdue3JzYS1wa2NzMS1za...
---- END SSH2 ENCRYPTED PRIVATE KEY ----
```

接着，我们使用 ssh-keygen 将 SSHv2 格式的文件转换为 RSA 格式的文件。

```shell
$ ssh-keygen -i -f ~/.ssh/sshv2_id_rsa > ~/.ssh/converted_id_rsa
```

最后，转换后的 RSA 私钥格式如下所示：

```
-----BEGIN RSA PRIVATE KEY-----
MIIG5AIBAAKCAYEArwZXd5mI3XeOynhMIFWbRX1HoDWvXXO0C...
-----END RSA PRIVATE KEY-----
```

## 参考

[1] https://federicofr.wordpress.com/2019/01/02/how-to-convert-openssh-private-keys-to-rsa-pem/

<div class="just-for-fun">
笑林广记 -
</div>
