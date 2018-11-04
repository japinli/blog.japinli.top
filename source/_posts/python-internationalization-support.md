---
title: "Python 多语言国际化支持"
date: 2018-11-04 09:13:35 +0800
category: Programming
tags: Python
---

<!--
GNU gettext 是国际化 (i18n) 开发古老而成熟的解决方案。它可以用于本地化任何类型的应用程序，并且在支持不同区域设置和规则方面十分灵活。在本文中，我们将介绍如何使用 Python 标准库中自带的 gettext 模块来实现程序的多语言支持。
-->


Python 的 gettext 模块为应用程序提供了国际化 (Internationalization, I18N) 和本地化 (Localization, L10N) 的服务。该模块提供了两类 APIs：(a) 支持 GNU gettext 的基本 API；(b) 适合 Python 的并且基于类的 API。本文主要针对第二类 API 进行介绍。

为了向 Python 程序提供多语言消息，我们需要按以下步骤进行：

1. 使用包装函数对程序中所有可以翻译的字符串进行标记；
2. 使用 xgettext 在标记的文件上生成原始消息目录或 POT 文件；
3. 将 POT 文件复制到特定的区域设置目录并进行翻译（需要使用专用的编辑器）；
4. 导入并使用 gettext 模块，以便正确转换消息字符串。

<!-- more -->

## 示例

为了更好的理解整个过程，我们需要一个想要本地化的示例程序。我们的示例程序目录结构如下所示：

```
i18n/
+-- locales
|   +-- en_US
|   |   +-- LC_MESSAGES
|   +-- zh_CN
|       +-- LC_MESSAGES
+-- src
    +-- main.py
```

目录 `locales` 用于存放多国语言之间的翻译文件，`src` 则用于存放源码文件。正如上文所述，我们需要标记程序中待翻译的字符串，为了实现这一点，我们将需要翻译的字符串放在 `_()` 中。文件 main.py 的内容如下所示：

``` python
#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Internationalization test.

import gettext
_ = gettext.gettext

def printSomeMessages():
    print(_("Hello world!"))
    print(_("This is a translate message."))

if __name__ == '__main__':
    printSomeMessages()
```

注意，我们引入了 gettext 模块并将 `_` 赋值为 `gettext.gettext`。这样可以保证我们的程序可以正常运行。

## 生成原始翻译消息

为了自动化在整个应用程序中从包装字符串生成原始可翻译消息的过程，gettext 库的作者提供了一组工具用于解析源文件并提取需要翻译的消息。最初，GNU gettext 仅支持 C/C++ 源码，但是它的扩展程序 xgettext 支持多种语言的源码，包括 Python，Lisp，Java 等。

``` shell
$ cd i18n
$ xgettext -o locales/en_US/LC_MESSAGES/base.po_en src/*.py
$ xgettext -o locales/zh_CN/LC_MESSAGES/base.po_zh src/*.py
```

原始信息 (两个文件内容一致) 如下所示：

```
# SOME DESCRIPTIVE TITLE.
# Copyright (C) YEAR THE PACKAGE'S COPYRIGHT HOLDER
# This file is distributed under the same license as the PACKAGE package.
# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.
#
#, fuzzy
msgid ""
msgstr ""
"Project-Id-Version: PACKAGE VERSION\n"
"Report-Msgid-Bugs-To: \n"
"POT-Creation-Date: 2018-11-04 10:24+0800\n"
"PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\n"
"Last-Translator: FULL NAME <EMAIL@ADDRESS>\n"
"Language-Team: LANGUAGE <LL@li.org>\n"
"Language: \n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=CHARSET\n"
"Content-Transfer-Encoding: 8bit\n"

#: src/main.py:11
msgid "Hello world!"
msgstr ""

#: src/main.py:12
msgid "This is a translate message."
msgstr ""
```

## 翻译

在得到原始翻译消息之后，我们就可以通过编辑生成的 `*.po` 文件进行翻译工作了。这里需要注意的是 PO 文件具有自己的格式，因此尽量使用专用的 PO 文件编辑器进行修改。我个人使用的 Emacs + po-mode 进行编辑。

翻译 locales/en_US/LC_MESSAGES/base.po_en 为：

```
# I18N.
# Copyright (C) 2018 Japin Li
# This file is distributed under the same license as the I18N package.
# Japin Li <japinli@hotmail.com>, 2018.
#
#, fuzzy
msgid ""
msgstr ""
"Project-Id-Version: 0.0.1\n"
"Report-Msgid-Bugs-To: \n"
"POT-Creation-Date: 2018-11-04 10:24+0800\n"
"PO-Revision-Date: 2018-11-04 10:26+0800\n"
"Last-Translator: Japin Li <japinli@hotmail.com>\n"
"Language-Team: English <LL@li.org>\n"
"Language: \n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=ASCII\n"
"Content-Transfer-Encoding: 8bit\n"

#: src/main.py:11
msgid "Hello world!"
msgstr "Hello world!"

#: src/main.py:12
msgid "This is a translate message."
msgstr "This is a translate message."
```

翻译 locales/zh_CN/LC_MESSAGES/base.po_zh 为：

```
# I18N.
# Copyright (C) 2018 Japin Li
# This file is distributed under the same license as the I18N package.
# Japin Li <japinli@hotmail.com>, 2018.
#
#, fuzzy
msgid ""
msgstr ""
"Project-Id-Version: 0.0.1\n"
"Report-Msgid-Bugs-To: \n"
"POT-Creation-Date: 2018-11-04 10:24+0800\n"
"PO-Revision-Date: 2018-11-04 10:37+0800\n"
"Last-Translator: Japin Li <japinli@hotmail.com>\n"
"Language-Team: Chinese <LL@li.org>\n"
"Language: \n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"

#: src/main.py:11
msgid "Hello world!"
msgstr "你好世界！"

#: src/main.py:12
msgid "This is a translate message."
msgstr "这是一个翻译消息。"
```

上述翻译需要注意中文的编码要选择 `UTF-8`，至于其他的诸如 PACKAGE VERSION，COPYRIGHT 等可以根据自己需要进行填写。当翻译完成之后，我们需要将 `*.po` 文件通过 msgfmt 最终转换为 `*.mo` 文件。

``` shell
$ cd i18n
$ msgfmt -o locales/en_US/LC_MESSAGES/base.mo locales/en_US/LC_MESSAGES/base.po_en
$ msgfmt -o locales/zh_CN/LC_MESSAGES/base.mo locales/zh_CN/LC_MESSAGES/base.po_zh
```

## 执行

我们修改 src/main.py 文件为：

``` python
#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Internationalization test.

import gettext
_ = gettext.gettext

def printSomeMessages():
    print(_("Hello world!"))
    print(_("This is a translate message."))

import os
import sys
localedir=os.path.dirname(os.path.abspath(sys.argv[0])) + '/../locales'
zh_CN = gettext.translation('base', localedir, languages=['zh_CN']);
zh_CN.install()
_ = zh_CN.gettext

if __name__ == '__main__':
    printSomeMessages()
```

其中 `getext.translation` 函数有三个较为重要的参数。

* domain - 该参数的名字需要与生成的 `*.mo` 的文件名匹配。
* localedir - 创建的 locales 目录的路径
* languages - 需要载入的语言代码

最终文件目录结构如下所示：

```
i18n/
+-- locales
|   +-- en_US
|   |   +-- LC_MESSAGES
|   |       +-- base.mo
|   |       +-- base.po_en
|   +-- zh_CN
|       +-- LC_MESSAGES
|           +-- base.mo
|           +-- base.po_zh
+-- src
    +-- main.py
```

你可以在 [github][] 上下载整个工程文件。

## 参考

[1] https://phraseapp.com/blog/posts/translate-python-gnu-gettext/
[2] https://docs.python.org/2/library/gettext.html#class-based-api

<hr>

__P.S.__ Internationalization 简写为 I18N 是因为在单词第一个字母 I 和最后一个字母 N 之间有 18 个字符。Localization 亦是如此。

[github]: https://github.com/japinli/i18n
