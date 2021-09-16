---
title: "LaTeX 自定义封面"
date: 2019-04-13 21:04:34 +0800
category: 排版
tags:
  - LaTeX
---

本文主要记录在使用 LaTeX 进行封面自定义的相关实现，如下图 1 所示。

{% asset_img customize-title-page.png LaTeX Title Page %}
<p style="text-align:center">图 1 LaTeX 自定义封面</p>

<!-- more -->

## 实现

图 1 的封面通过 LaTeX 实现起来非常简单，我们只需要会使用几个基本的命令就足够了。从图中我们可以将封面分为六个部分，它们分别是最上面的横线、居中的标题、标题下的横线、作者信息、日期以及封面底部的横线。如下所示：

``` tex
\documentclass{book}

\begin{document}

  \begin{titlepage}
    \centering

    %------------------------------------------------------------
    %    Top rules
    %------------------------------------------------------------

    \rule{\textwidth}{1pt}   % The top horizontal rule
    \vspace{0.2\textheight}  % Whitespace between top horizontal rule and title

    %------------------------------------------------------------
    %    Title
    %------------------------------------------------------------

    {\Huge Customize \LaTeX{} Title Page}

    \vspace{0.025\textheight}   % Whitespace between the title and short horizontal rule

    \rule{0.83\textwidth}{0.4pt}  % The short horizontal rule under title

    \vspace{0.1\textheight}  % Whitespace between the short horizontal rule and author

    %------------------------------------------------------------
    %    Author
    %------------------------------------------------------------

    {\Large Author: \textsc{Japin Li}}

    \vfill  % Whitespace between author and date

    {\large \today}
    \vspace{0.1\textheight}  % Whitespace between date and bottom horizontal rule

    %------------------------------------------------------------
    %    Bottom rules
    %------------------------------------------------------------

    \rule{\textwidth}{1pt}  % The bottom horizontal rule

  \end{titlepage}
\end{document}
```

在上面的示例中我只是将 `titlepage` 直接在文档中给出，其实我们还可以通过重定义 `\maketitle` 命令来实现自定义封面，这时我们还需要传入一些特定的参数，详细实现可以参考我实现的 [ferret](https://github.com/japinli/ferret)。您也可以在封面中使用 `\includegraphics` 命令来导入图片。

## 参考

[1] https://en.wikibooks.org/wiki/LaTeX/Title_Creation
