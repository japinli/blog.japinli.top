---
title: "C 语言词法元素"
date: 2019-06-01 22:31:18 +0800
category: Programming
tags: C
---

本文主要介绍 C 语言的词法元素，包括标识符、关键字、常量、操作符以及分隔符。其中关于操作符的一些更为详细的信息将在后续进行介绍。

{% asset_img C_lexical_elements.png %}

<!-- more -->

## 标识符

标识符在 C 语言中由于命令变量、函数、新的数据类型以及预处理的字符序列（例如，宏定义）。它可以包含字符、数字以及下划线（`_`)，标识符是区分大小写的，并且不能以数字开始。需要注意的是，GNU 扩展可以在标识符中使用美元符号（`$`）。

例如，下面的标识符是正确的：

```
bool ok;
int my_id;
char *_name;
```

而下面的标识符则错误的：

```
int 2id;
char *#a;
```

## 关键字

关键字是 C 语言保留的特殊标识符，这些标识符有特定的用处，因此不能用于其它用途。不同的标准下，C 语言支持的关键字有所不同。下表给出了不同标准下的关键字。

| 标准     | 关键字 |
|----------|--------|
| ANSI C89 | auto, break, case, char, const, continue, default, do, double, else, enum, extern, float, for, goto, if, int, long, register, return, short, signed, sizeof, static, struct, switch, typedef, union, unsigned, void, volatile, while |
| ISO C99  | inline, \_Bool, \_Complex, \_Imaginary, restrict |
| GUN 扩展 | \_\_FUNCTION\_\_, \_\_PRETTY\_FUNCTION\_\_, \_\_alignof, \_\_alignof\_\_, \_\_asm, \_\_asm\_\_, \_\_attribute, \_\_attribute\_\_, \_\_builtin\_offsetof, \_\_builtin\_va\_arg, \_\_complex, \_\_complex\_\_, \_\_const, \_\_extension\_\_, \_\_func\_\_, \_\_imag, \_\_imag\_\_, \_\_inline, \_\_inline\_\_, \_\_label\_\_, \_\_null, \_\_real, \_\_real\_\_, \_\_restrict, \_\_restrict\_\_, \_\_signed, \_\_signed\_\_, \_\_thread, \_\_typeof, \_\_volatile, \_\_volatile\_\_, restrict|

## 常量

常量是一个数值或者字符值，例如，`5` 或者 `'m'`。所有的常量都有一个特定的数据类型，你可以显示地将其强制转换为某个特定类型或者你也可以让编译器选择默认的数据类型。C 语言包含四类常量：a. 整型常量；b. 字符常量；c. 浮点数常量；d. 字符串常量。

### 整型常量

整型常量是一个数字组成的序列，它可以伴随一个前缀用于表示常量的基数，同时也可以带有一个后缀用以表示数据类型。C 语言提供了三种基数的表示方式：

| 基数     | 前缀         | 示例                     |
|----------|--------------|--------------------------|
| 十六进制 | `0x` 或 `0X` | `0x2f`, `0x88`, `0XAB43` |
| 十进制   | 无           | `459`, `12`, `1293`      |
| 八进制   | `0`          | `057`, `03`, `012`       |

数据类型则可以通过字符 `u` 和 `l` 来表示：

| 数据类型                     | 后缀          | 示例     |
|------------------------------|---------------|----------|
| 无符号整型 （`unsigned`）    | `u` 或 `U`    | `45U`    |
| 长整型（`long int`）         | `l` 或 `L`    | `45L`    |
| 长长整型 （`long long int`） | `ll` 或 `LL`  | `45LL`   |

长长整型（`long long int`）是在 ISO 99 和 GNU C 扩展中新加的数据类型。此外，我们可以通过将 `u` 和 `l` 组合起来形成无符号长整型数据类型。例如 `45ULL`。

__备注：__ `u` 和 `l` 的顺序没有多大关系。

### 字符常量

字符常量通常是有单引号包含起来的单个字符，例如，`A`。字符常量的默认数据类型为整型（`int` 类型）。一些字符无法用单个字符表示，因此需要进行转义。常见的转义字符如下所示：

| 转义字符                   | 说明                   |
|----------------------------|------------------------|
| `\\`                       | 反斜杆字符             |
| `\?`                       | 问号字符               |
| `\'`                       | 单引号                 |
| `\"`                       | 双引号                 |
| `\a`                       | 警报                   |
| `\b`                       | 退格字符               |
| `\e`                       | <ESC> 字符（GNU 扩展） |
| `\f`                       | 表格填充               |
| `\n`                       | 换行符                 |
| `\r`                       | 回车符                 |
| `\t`                       | 水平制表符             |
| `\v`                       | 垂直制表符号           |
| `\o`,`\oo`,`\ooo`          | 八进制数               |
| `xh`,`\xhh`,`\xhhh`, `...` | 十六进制数             |

虽然十六进制的表示方式后面可以跟任意多个数字，但是给定的字符集的字符数量是有限的。例如，常用扩展的 ASCII 字符集只有 256 个字符。如果你尝试给出一个超出字符集范围的十六进制字符表示，那么编译时将出错。（我测试过后发现其实有一个警告。）

### 浮点数常量

浮点数常量（实数常量）由整数部分，小数点和小数部分组成，同样它可以有一个可选的数据类型后缀。在表示浮点数常量时，我们可以省略整数部分或小数部分，但不能同时省略。例如：

``` C
double a, b, c, d, e, f;

a = 4.7;
b = 4.;
c = 4;
d = .7;
e = 0.7;
```

需要注意的是在 `c = 4;` 的赋值语句中，整型常量 `4` 将自动的由整型转换为浮点型（`double` 类型）。此外，我们还可以用科学计数的方式来表示浮点数，如下所示：

``` C
double x, y;

x = 5e2;    /* x 为 5 * 100，即 500.0 */
y = 5e-2;   /* y 为 5 * (1/100), 即 0.05 */
```

你可以在浮点数后面添加 `F` 或 `f` 来表示单精度浮点数（`float` 类型），如果在浮点数后面添加 `L` 或 `l` 则表示该常量的数据类型为 `long double`。默认情况下，浮点数的类型为 `double`。

### 字符串常量

字符串常量是由双引号包裹的零个或多个字符、数字以及转义字符序列。字符串常量的数据类型为字符数组。所有的字符串都包含一个空字符（`\0`）用来表示字符串结尾。字符串以字符数组的方式存储，它没有字符串长度的属性。字符串以末尾的空字符作为结束标志。两个相邻的字符串常量将会被连接为一个字符串常量，并且只保留最后一个字符串的空字符。

由于字符串由双引号作为标示，因此我们在字符串中使用双引号时需要对其进行转义。例如：

```
"\"Hello, world!\""
```

如果一个字符串太长以致于不能放在一行中，我们可以使用反斜杠 `\` 来将其拆分为单独的行。例如：

```
"This is a long long long long long long long long long \
long long long string."
```

__注意：__ 在反斜杠后面不能有任何字符，尤其要注意空白字符，如空格、制表符等。

## 操作符

操作符（运算符）是一个特殊标记，它对一个，两个或三个操作数执行操作，例如加法或减法。后续将给出更为详细的介绍。

## 分隔符

分隔符用于分割标记（`tokens`）。分隔符本身也是一种标记。它们由单个字符组成并代表其自身，C 语言中的分隔符标记包括 `(`, `)`, `[`, `]`, `{`, `}`, `;`, `,`, `.`, `:`。空白也是一种分隔符，但它不属于标记。

## 参考

[1] https://www.gnu.org/software/gnu-c-manual/gnu-c-manual.html#Lexical-Elements