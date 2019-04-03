---
title: "Eclipse 导入证书文件"
date: 2019-01-23 21:12:40 +0800
category: Programming
tags:
  - Eclipse
  - keystore
---

现在越来越多的网站采用 HTTPS 协议，今天就遇到一个关于 HTTPS 证书的问题，服务器端采用 HTTPS 加密传输，而证书是使用的自签名证书，因此客户端开发时需要将其导入到 Eclipse 中才能通过验证（客户端采用 Java 开发）。Eclipse 采用 keystore 来管理证书，可以利用工具 `keytool` 来管理证书文件，本文主要记录 Eclipse 证书管理的基本使用，以及使用自签名证书的格式问题。

<!-- more -->

### 导入 SSL 证书

我登陆到服务器取下了服务端使用的 SSL 证书（一个名为 ssl.pem 的文件），随后通过 `keytool` 将其导入到 Eclipse 中，命令如下：

```
$ keytool -import -alias <provide_an_alias> -file <certificate_file> -keysotre <your_path_to_jre>/lib/security/cacerts
```

__备注：__ `< >` 中的内容需要根据实际情况填写。

然而我执行时出现了如下错误：

```
keytool error: java.lang.Exception: Input not an X.509 certificate
java.lang.Exception: Input not an X.509 certificate
        at sun.security.tools.KeyTool.addTrustedCert(KeyTool.java:1913)
        at sun.security.tools.KeyTool.doCommands(KeyTool.java:818)
        at sun.security.tools.KeyTool.run(KeyTool.java:172)
        at sun.security.tools.KeyTool.main(KeyTool.java:166)
```

### 证书格式转换

从上面的错误结果可以看到证书格式不是标准的 X.509 格式，于是我查看了一下 ssl.pem 文件的内容，其格式如下:

```
-----BEGIN PRIVATE KEY-----
BASE64 ENCODING INFORMATION
-----END PRIVATE KEY-----
-----BEGIN CERTIFICATE-----
BASE64 ENCODING INFORMATION
-----END CERTIFICATE-----
```

这与 X.509 的证书格式不同，因此出现上述问题。X.509 证书的格式如下所示：

```
-----BEGIN CERTIFICATE-----
BASE64 ENCODING CERTIFICATE INFORMATION
-----END CERTIFICATE-----
```

因此，我们需要将 ssl.pem 格式的证书转换为 X.509 格式，我们利用 openssl 来实现，其命令如下：

```
$ openssl x509 -in ssl.pem -text
```

此外，我们可以直接将 ssl.pem 文件中的 `-----BEGIN CERTIFICATE-----` 到 `-----END CERTIFICATE-----` 之间的内容拷贝出来即可。

现在我们再次使用 `keytool -import` 命令导入证书即可。

__备注：__

1. 当 `keytool` 提示输入密码时，请输入：`changeit`。这应该是默认的。
2. 当 `keytool` 询问是否信任该证书时，请输入：`yes`。默认为 `on`。

### 删除证书

当我们不再需要这个自签名证书时，可以通过如下命令将其从 keystore 中删除。

```
$ keytool -delete -alias <cert_alias> -keystore <your_path_to_jre>/lib/security/cacerts
```

我们也可以使用下面的命令查看 keystore 中证书的详细信息。

```
$ keytool -list -v -keystore <your_path_to_jre>/lib/security/cacerts
```

### 参考

[1] [Importing SSL certificate into eclipse](https://stackoverflow.com/questions/684081/importing-ssl-certificate-into-eclipse)
[2] [Error importing SSL certificate not an X509 certificate](https://stackoverflow.com/questions/9889669/error-importing-ssl-certificate-not-an-x-509-certificate)
