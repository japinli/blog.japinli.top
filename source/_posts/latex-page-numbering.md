---
title: "LaTeX 页码设置"
date: 2019-03-12 21:49:40 +0800
category: 排版
tags:
  - LaTeX
---

默认情况下，LaTeX 会在每个页面的底部生成一个页码编号，即使是标题页也是如此。通常情况下，我们不需要在标题页输出页码编号，而且目录页一般也会采用罗马数字的形式给出页码，而正文内容则以阿拉伯数字的形式给出页码编号。本文接下来介绍了 LaTeX 中基本的页码设置。

<!-- more -->

## 页码设置相关的命令

在 LaTex 中，与页码和页面设置相关的命令有 `\pagestyle{type}`，`\thispagestyle{type}`，`setcounter{page}{number}` 和 `\pagenumbering{style}`。

其中 `\pagestyle{type}` 和 `\thispagestyle{type}` 命令用于设置页面样式 (页眉和页脚)。`\pagestyle{type}` 和 `\thispagestyle{type}` 的主要区别在于 `\pagestyle{type}` 对后续所有页面都有效，而 `\thispagestyle{type}` 仅仅对当前页面有效。在 LaTeX 中，默认提供了以下五种页面样式：

* __empty__ - 没有页眉和页脚
* __plain__ - 没有页眉，页脚包含一个居中的页码
* __headings__ - 没有页脚，页眉包含章/节或者字节的名字和页码
* __myheadings__ - 没有页脚，页眉包含有页码

默认情况下，页码从第一页开始 (通常是包含标题页的) 并且以阿拉伯数字形式显示 (例如：1，2，3, ... )。页码的编号也可以通过 `\setcounter{page}{number}` 命令手动设置，需要注意的是，手动设置可能会导致重复的页码出现。

`\pagenumbering{style}` 命令则用于改变页码的显示风格。LaTeX 中页码风格包含以下五类：

* __arabic__ - 阿拉伯数字
* __roman__ - 小写的罗马数字
* __Roman__ - 大写的罗马数字
* __alph__ - 小写的字符形式
* __Alph__ - 大写的字符形式

## 示例代码

``` latex
\documentclass{article}

\usepackage{fontspec, xunicode, xlextra}
\usepackage{xeCJK}

\title{\LaTeX 页码设置}
\author{Japinli}

\begin{document}
\maketitle
\thispagestyle{empty} % 当前页不显示页码
\newpage

\pagestyle{headings}
\setcounter{page}{1}
\pagenumbering{Roman}

\section*{前言}
学习如何在\LaTeX 中设置页码。
\newpage

\tableofcontents
\newpage

\setcounter{page}{1}
\pagenumbering{arabic}

\section{页码风格}

\LaTeX 中包含五种页码风格，分别是\emph{arabic}，\emph{roman}，\emph{Roman}，
\emph{alph}和\emph{Alph}。

\section{页码风格说明}

\emph{arabic}代表阿拉伯数字类型。

\emph{roman}代表小写的罗马数字类型。

\emph{Roman}代表大写的罗马数字类型。

\emph{alph}代表小写的字符类型。

\emph{Alph}代表大写的字符类型。

\section{页码风格设置}

为了改变页码的风格，可以使用\emph{\textbackslash pagenumbering\{sytle\}}
命令设置。

\end{document}
```
