---
title: "Emacs ERC SASL 配置"
date: 2022-09-16 20:23:45 +0800
categories: 杂项
tags:
  - Emacs
---

最近在使用 IRC 的时候发现 Emacs 的 ERC 不能登录 IRC 了，提示如下错误信息：

```
Opening connection..                                                    [13:47]
-zinc.libera.chat- *** Checking Ident
-zinc.libera.chat- *** Looking up your hostname...
-zinc.libera.chat- *** No Ident response
-zinc.libera.chat- *** Couldn't look up your hostname
-zinc.libera.chat- *** Notice -- SASL authentication to a NickServ account
                 with a verified email address is required to connect from
                 your current network. Please see
                 https://libera.chat/guides/sasl for configuration assistance.
==> ERROR from irc.libera.chat: Closing Link: 117.139.163.129 (SASL
    authentication to a NickServ account with a verified email address is
    required to connect from your current network. Please see
    https://libera.chat/guides/sasl for configuration assistance.)


Connection failed!  Not re-establishing connection.


*** ERC terminated: connection broken by remote peer
```

<!--more-->

## 解决方案

这是由于 [Libera.Chat][] 要求对某些 IP 范围使用 SASL。在采用了官网给出的[解决方案](https://libera.chat/guides/emacs-erc)之后，发现还是不行，启动 Emacs 的时候将遇到如下错误：

```
Warning (initialization): An error occurred while loading ‘/Users/japin/.emacs.d/init.el’:

Symbol's function definition is void: define-erc-response-handler

To ensure normal operation, you should investigate and remove the
cause of the error in your initialization file.  Start Emacs with
the ‘--debug-init’ option to view a complete error backtrace. Disable showing Disable logging
```

我尝试在 [Github 上搜索 `erc-sasl`](https://github.com/search?q=erc-sasl&ref=opensearch)，找到两个与之相关的项目，我选择了 [kimjetwav][] 的实现（仅仅是因为它在最近更新过），经过测试发现可以正常使用。

通过查看其源码，我发现 kimjetwav 的实现中导入了 `erc`，搜索一番之后，[才知道 `define-erc-response-handler` 是在 `erc-backend.el` 中定义的][define-erc-response-handler]。而官网给的 `erc-sasl` 中并没有导入，于是我们尝试在官网的 `erc-sasl` 中加入 `erc`，其也可以正常工作。

## 参考

[1] https://libera.chat/guides/emacs-erc
[2] https://libera.chat/guides/sasl
[3] https://github.com/kimjetwav/erc-sasl/blob/master/erc-sasl.el
[4] https://github.com/syl20bnr/spacemacs/blob/master/layers/%2Bchat/erc/local/erc-sasl/erc-sasl.el
[5] https://doc.endlessparentheses.com/Fun/define-erc-response-handler.html

[define-erc-response-handler]: https://doc.endlessparentheses.com/Fun/define-erc-response-handler.html
[kimjetwav]: https://github.com/kimjetwav/erc-sasl
[Libera.Chat]: https://libera.chat/

<div class="just-for-fun">
笑林广记 - 医银入肚

一富翁含银于口，误吞入，肚甚痛，延医治之。
医曰：“不难，先买纸牌一副，烧灰咽之，再用艾丸炙脐，其银自出。”
翁询其故，医曰：“外面用火烧，里面有强盗打劫，哪怕你的银子不出来。”
</div>
