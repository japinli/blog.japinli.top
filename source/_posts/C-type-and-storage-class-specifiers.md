---
title: "C 语言类型及存储类限定符"
date: 2019-06-26 21:22:04 +0800
category: Programming
tags: C
---

本文主要介绍 C 语言中的类型及存储类限定符，C 语言中提高了两个类型限定符：`const` 和 `volatile`；类型限定符指明了变量的访问方式。存储类限定符则指定了变量在内存中的存储方式，C 语言提供了四种存储类限定符：`auto`，`register`，`extern` 和 `static`。

<!-- more -->

## 类型限定符

类型限定符允许您指定变量的访问方式，C 语言提供了两个类型限定符：(a) `const` 指明变量是只读的，一旦初始化，它的值将不能被改变；(b) `volatile` 表明变量是显式可变的，并且看似无用的变量访问（例如，通过指针）不应该被优化掉。例如：

``` C
const float pi = 3.14159f;
volatile float currentTemperature = 40.0;
```

`const` 限定符除了能防止变量被意外改变之外，它还能辅助编译器进行优化。针对有回调函数或者信号处理函数更新的变量，我们可以将其定义为 `volatile` 从而避免编译器过度优化导致数据不一致。

## 存储类限定符

存储类限定允许您定义变量在内存中的存储方式。`auto` 关键字用于定义函数内部的局部变量，当函数返回时，这是局部变量（自动变量）将自动被清理掉，这是函数内部的变量默认行为。

``` C
void
foo(int value)
{
    auto int x = value;
    ...
    return;
}
```

`register` 关键字定义的变量被称为寄存器变量，它的行为与 `auto` 定义的变量几乎类似，稍有不同的是，该关键字表明该变量的使用频率极高，如果可能尽量将其放在寄存器中。如果变量被声明为 `register` 类型，__那么将不能对其进行取地址运算 (`&`)__。这意味着您不能引用使用存储类寄存器声明的数组的元素。GCC 编译器在优化时可以很好的选择哪些变量使用被保存在寄存器中，因此寄存器变量很少使用。

`static` 限定符与 `auto` 的作用正好相反：当将 `static` 应用于函数内部或块内的变量时，即使函数完成或块结束之后，这些变量都将保存其值。这就是所谓的__静态存储持续期 (Static Storage Duration)__。

``` C
int
sum (int x)
{
    static int sumSoFar = 0;
    sumSoFar = sumSoFar + x;
    return sumSoFar;
}
```

此外，您还可以在顶层（即不在函数内）将变量（或函数）声明为 `static`。这些变量（全局变量）仅在当前源文件可见，其它源文件则不可见。这就给 `static` 带来了双重含义；第二种意义则是__静态链接 (Static Linkage)__。在单独的文件中具有静态链接的两个函数或变量是完全独立的；在声明它的文件之外都不可见。

声明为 `extern` 的未初始化变量的默认值为 `0`，`0.0` 或 `NULL`，具体值则取决于其类型。声明为 `auto` 和 `register` 的未初始化变量保留为初始化状态，因此不应假设这些变量保存特定的值。

`extern` 对于声明要链接到项目的所有源文件可见的变量很有用。变量声明时并不会为其分配存储空间，所以你无法在 `extern` 声明语句中进行初始化操作。您必须同时进行 `extern` 声明和非 `extern` 声明，实际上后者是变量的定义，它将为期分配存储空间。`extern` 声明语句可以重复多次。

``` C
extern int numberOfClients;
...
int numberOfClients = 4;
```

## 参考

[1] https://www.gnu.org/software/gnu-c-manual/gnu-c-manual.html#Type-Qualifiers
