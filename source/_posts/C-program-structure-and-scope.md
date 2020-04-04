---
title: "C 程序结构和范围"
date: 2020-01-09 22:51:27 +0800
category: Programming
tags: C
---

在之前的几篇关于 C 语言的文章中，我们以及掌握了 C 语言的基本要素，本文主要介绍 C 语言的程序结构和范围。

<!-- more -->

## 程序结构

我们可以将 C 程序写在一个源文件中，然而，更为常见的是将其按照功能模块将其划分到不同的源文件中。

通常，头文件（即以 `.h` 结尾的文件）包含函数和变量的声明；源文件（即以 `.c` 结尾的文件）包含相应的定义。如果我们不想某些声明被外部文件访问，那么也可以将声明放在源文件中。

例如，如果我们编写一个求平方根的函数，我们希望可以在定义该函数以外的文件访问，那么我们需要将函数的声明放在头文件中（即以 `.h` 结尾的文件）。

``` C
/* sqrt.h */

double
computeSqrt(double x);
```

该头文件可能包含其它我们需要使用的函数但其定义在不同的源文件中，我们可能不需要知道这些函数的实现。

This header file could be included by other source files which need to use your function, but do not need to know how it was implemented.

上述函数的定义应该在相应的源文件中出现（即以 `.c` 结尾的文件）。

``` C
/* sqrt.c */
#include "sqrt.h"

double
computeSqrt(double x)
{
    double result;
    ...
    return result;
}
```

## 范围

范围是指程序的哪些部分可以“看到”声明的对象。声明的对象可以只在特定的函数中可见、或者是特定的文件、亦或者是包含这个声明的头文件的一系列源文件中（需要使用 `extern` 声明）。

除非特定说明，在文件的顶层（即不在函数内）进行的声明对整个文件都是可见的，包括从函数内部，但在文件外部不可见；在函数内进行的声明仅在这些函数内可见；此外，声明对之前的声明不可见，例如：

``` C
int x = 10;
int y = x + 5;
```

这样是可以的，但是如下方式则是不行的。

``` C
int x = y + 5;
int y = 10;
```

## 参考

[1] https://www.gnu.org/software/gnu-c-manual/gnu-c-manual.html#Program-Structure-and-Scope