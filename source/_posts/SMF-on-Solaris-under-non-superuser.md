---
title: "非超级用户下运行 Solaris SMF 服务"
date: 2019-10-22 22:24:04 +0800
category: Misc
tags:
    - Solaris
---

今天在 Solaris 上遇到一个问题，我需要在非超级用户下运行某个服务。默认情况下，通过 SMF 管理的都是在 root 用户下运行的，但是我们可以通过修改配置文件来使其运行到特定用户下。

<!-- more -->

例如，我们有如下一个配置文件（部分）：

``` xml
<exec_method type="method" name="start" exec="/path/to/exec_binary &amp;">
    <method_context working_directory="/path/to/work">
        <method_environment>
            <envar name="HOME" value="/home/path" />
        </method_environment>
    </method_context>
</exec_method>
```

现在，我们想要 `exec_binary` 在 `tom` 用户下运行，那么我们需要加入 `method_credential` 元素，如下所示：

``` xml
<exec_method type="method" name="start" exec="/path/to/exec_binary &amp;">
    <method_context working_directory="/path/to/work">
        <method_credential user="tom" />
        <method_environment>
            <envar name="HOME" value="/home/path" />
        </method_environment>
    </method_context>
</exec_method>
```

这样，我们便可以在 `tom` 用户下运行 `exec_binary` 的服务了，这里需要注意 `method_credential` 的位置，它需要位于 `method_environment` 之前，否则将出现如下问题。

```
element method_context: validity error : Element method_context content does not follow the DTD, expecting ((method_profile | method_credential)? , method_environment?), got (method_environment method_credential )
svccfg: Document is not valid.
```

我们可通过查看 `/usr/share/lib/xml/dtd/service_bundle.dtd.1` 文件来了解更多的 SMF 配置信息。

## 参考

[1] https://www.linuxquestions.org/questions/solaris-opensolaris-20/problem-by-validate-a-manefest-file-4175468958/
[2] https://www.master-tutorial.design/2010/06/credentials-and-projects-for-solaris-10.html
