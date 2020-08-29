---
title: "LaTeX 查看命令的定义"
date: 2019-04-18 22:25:24 +0800
category: 排版
tags:
  - LaTeX
---

最近在使用 LaTeX 撰写文档时需要重定义一个命令的，但是我想要知道该命令的原始定义时怎样的，经过查找发现 LaTeX 在这方面做得还是很不错的。目前，我知道有两种方式可以获取命令的定义：(a) 在文档中使用 `\show\command`；(b) 在命令行中使用 `texdef command`。

<!-- more -->

## `\show` 查看命令定义

下面是一个完整的文档示例，在该文档中，我们通过 `\show\section` 来查看 `\section` 的定义。

``` tex
\documentclass{article}
\begin{document}
\show\section
\end{document}
```

上述代码非常简单，当我们通过 `latex` 编译时可以得到以下内容：

```
$ latex test.tex
This is pdfTeX, Version 3.14159265-2.6-1.40.19 (TeX Live 2018) (preloaded format=latex)
 restricted \write18 enabled.
 entering extended mode
 (./test.tex
 LaTeX2e <2018-04-01> patch level 5
 (/usr/local/texlive/2018/texmf-dist/tex/latex/base/article.cls
 Document Class: article 2014/09/29 v1.4h Standard LaTeX document class
 (/usr/local/texlive/2018/texmf-dist/tex/latex/base/size10.clo)) (./test.aux)
 > \section=\long macro:
 ->\@startsection {section}{1}{\z@ }{-3.5ex \@plus -1ex \@minus -.2ex}{2.3ex \@p
 lus .2ex}{\normalfont \Large \bfseries }.
 l.3 \show\section

 ?
```

注意第 10 行的输出，`\section=\long macro:` 这里就是关于 `\section` 命令的定义。


## `texdef` 查看命令定义

`texdef` 时一个 shell 命令，我们可以直接在 shell 中执行，例如，我们想看 `\section` 命令的定义，可以在 shell 中输入 `texdef section`，其输出结果如下：

```
$ texdef section

\section:
undefined
```

为什么 `section` 命令没有定义？这里的例子其实与上面的稍微有点不一样，上面我们使用的是 `latex` 来编译的，而 `texdef` 查看的是原 `TeX` 命令的定义而非 `LaTeX` 命令的定义，因此我们需要将其换为 `latexdef`，其结果如下：

```
$ latexdef section

\section:
\long macro:->\@startsection {section}{1}{\z@ }{-3.5ex \@plus -1ex \@minus -.2ex}{2.3ex \@plus .2ex}{\normalfont \Large \bfseries }
```

`latexdef` 命令提供了很多选项给用户选择，关于如何使用 `latexdef` 请使用 `latexdef --help` 查看帮助手册。

## 参考

[1] https://tex.stackexchange.com/questions/36955/display-source-for-a-command
