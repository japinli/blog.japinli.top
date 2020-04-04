---
title: "C 语言语句"
date: 2019-10-13 07:39:30 +0800
category: Programming
tags: C
---

C 语言提供了语句用以控制程序的执行流程。您可以编写不执行任何操作的语句，当然也可以编写执行毫不相关的语句（没有任何意义）。本文主要介绍 C 语言所提供的一些语句类型，它们分别是：

0. 空语句 - 即形如 `;` 这样的语句；
1. 块语句 - 用括号括起来的一组零个或多个语句；
2. 条件语句 - __if__；
3. 返回语句 - __return__；
4. 循环语句 - __do__、__while__、__for__；
5. 开关语句 - __switch__，与 __case__ 结合使用；
6. 标签语句 - __labels:__，通常与 __goto__ 结合使用；
7. 跳转语句 - __goto__、__break__、__continue__，后两者用于循环语句中；
8. 表达式语句 - 例如 `a += 10`；
9. 类型定义语句 - __typedef__；

<!-- more -->

## 标签语句 （Labels）

我们可以使用标签来标示一部分源代码，以便后续通过 __goto__ 语句来使用。标签由标识符以及紧随其后的冒号组成。例如：

``` C
treet:
```

标签名不会影响其它标识符名称，例如，我们可以按如下定义：

``` C
int treet = 5;    /* 名为 treet 的变量 */
treet:            /* 名为 treet 的标签 */
```

在 ISO C 的标准中，标签后面必须跟至少一个语句，可以是空语句。GCC 则支持标签后不带任何语句。在编写可移植性的代码时需要注意这一点。

## 表达式语句（Expression Statements）

表达式语句通过在表达式末尾附加一个分号构成。例如：

``` C
5;
2 + 2;
10 >= 9;
```

在上面的例子中，所有的表达式在执行时都将被求值，但是这些求值结果由于没有保存，因此会被丢弃。编译器可能会忽略这些语句。

仅当表达式语句具有某种副作用（例如存储值，调用函数）或导致程序错误时，它才有用。例如：

``` C
x++;
y = x + 25;
puts("Hello, user!");
*cucumber;
```

如果 `cucumber` 即不是有效的指针并且被声明为 `volatile`，那么最后一个语句 `*cucumber*` 可能会导致潜在的程序错误。

## 条件语句（if）

我们可以使用条件语句来根据表达式的真假情况有选择的执行程序的一部分。其一般形式如下：

``` C
if (test)
    then-statement
else
    else-statement
```

若 `test` 求值结果为 `true`，那么程序将执行 `then-statment` 语句；反之，程序将执行 `else-statement` 语句。`else` 部分是可选的。例如：

``` C
if (x == 10)
    puts("x is 10");
```

如果表达式 `x == 10` 为 `true`，那么将执行 `puts("x is 10");` 语句。如果表达式 `x == 10` 为 `false`，那么 `puts("x is 10");` 将不会被执行。

下面的例子展示了 `else` 字句的使用：

``` C
if (x == 10)
    puts("x is 10");
else
    puts("x is not 10");
```

我们还可以使用一系列 `if` 语句来测试多个条件：

``` C
if (x == 1)
    puts ("x is 1");
else if (x == 2)
    puts ("x is 2");
else if (x == 3)
    puts ("x is 3");
else
    puts ("x is something else");
```

下面的函数用于计算给你年份 `y` 的复活节日期：

``` C
void
easterDate (int y)
{
    int n = 0;
    int g = (y % 19) + 1;
    int c = (y / 100) + 1;
    int x = ((3 * c) / 4) - 12;
    int z = (((8 * c) + 5) / 25) - 5;
    int d = ((5 * y) / 4) - x - 10;
    int e = ((11 * g) + 20 + z - x) % 30;

    if (((e == 25) && (g > 11)) || (e == 24))
        e++;

    n = 44 - e;

    if (n < 21)
        n += 30;

    n = n + 7 - ((d + n) % 7);

    if (n > 31)
        printf ("Easter: %d April %d", n - 31, y);
    else
        printf ("Easter: %d March %d", n, y);
}
```

## 开关语句（switch）

我们可以使用 `switch` 语句将一个表达式与其他表达式进行比较，然后根据比较结果执行一系列子语句。其一般形式如下：

``` C
switch (test)
{
    case compare-1:
        if-equal-statement-1
    case compare-2:
        if-equal-statement-2
        ...
    default:
        default-statement
}
```

`switch` 语句将 `test` 表达式的结果与每一个 `compare` 表达式进行比较，直到它找到与 `test` 表达式结果相等的 `compare`。接着，程序将执行这个 `compare` 表达式之后的语句。所有的 `compare` 表达式都必须是整型并且为常量整型（即，文字整数或由文字整数构建的表达式）。

我们可以在 `switch` 语句中给出一个可选的 `default` 字句。如果 `test` 表达式与 `default` 前的 `compare` 表达式均不匹配时，`default` 字句后的语句将被执行。通常，`default` 放在 `switch` 语句的末尾，但这不是必须的。

``` C
switch (x)
{
    case 0:
        puts("x is 0");
        break;
    case 1:
        puts("x is 1");
        break;
    default:
        puts("x is something else");
        break;
}
```

注意每个 `case` 语句后的 `break` 语句，这是因为，一旦找到匹配的 `case` 语句，不仅会执行其后语句，还会执行该 `case`语句后其它 `case` 语句下的所有语句。例如：

``` C
int x = 0;
switch (x)
{
    case 0:
        puts("x is 0");
    case 1:
        puts("x is 1");
    default:
        puts("x is something else");
}
```

上面的示例代码将输出下面的结果：

``` C
x is 0
x is 1
x is something else
```

这通常不是我们所期望的。在每个 `case` 语句的末尾包含一个 `break` 语句可以将程序流重定向到 `switch` 语句之后。

GNU C 支持在单个的 `case` 语句中指定一个连续的整数范围，例如：

``` C
case low ... high:
```

这与包含相同个数的 `case` 语句具有相同的含义。即：

``` C
case low:
case low + 1:
case ...:
case high - 1:
case high:
```

这个特性同样可以应用于 ASCII 字符集：

``` C
case 'A' ... 'Z':
```

请注意在 `...` 周围包含空格，否则可能在与整数一起使用时会出现解析错误。即，我们需要写成`case 1 ... 5:` 而不是 `case 1...5:`。

通常我们使用 `switch` 语句来处理 `errno` 的各种可能值。

## 循环语句

循环语句可以用于重复的执行某段代码，C 语句提供了三种基本的循环语句，`while`、`do` 和 `for`。接下来我们将分别介绍这三种循环语句。

### while 语句

`while` 循环语句在循环开始时进行退出测试，其一般形式如下：

``` C
while (test)
    statement
```

`while` 语句首先对 `test` 表达式求值。若结果为 `true`，那么将执行 `statement` 语句，随后再一次对 `test` 表达式求值；只要 `test` 表达式为 `true`，那么将一直执行 `statement` 语句。例如：

``` C
int counter = 0;
while (counter < 10)
    printf ("%d ", counter++);
```

此外，`break` 语句也可以用于退出当前循环。

### do 语句

`do` 循环语句是在循环末尾进行退出测试，其一般形式如下：

``` C
do
    statement
while (test)
```

`do` 语句首先执行 `statement` 语句，随后对 `test` 表达式求值。若结果为 `true`，那么继续执行 `statement` 语句。`statement` 仅在 `test` 表达式结果为 `false` 的时候退出。例如：

``` C
int x = 0;
do
    printf ("%d ", x++);
while (x < 10);
```

同样地，我们可以使用 `break` 语句来提前终止循环。

### for 语句

`for` 循环语句其结构允许简单的变量初始化，表达式测试和变量修改，它可以很方便地进行计数器的循环控制，其一般形式如下：

``` C
for (initialize; test; step)
    statement
```

`for` 语句首先执行 `initialize` 表达式，接着执行 `test` 表达式，如 `test` 表达式结果为 `false`，那么程序将退出 `for` 循环。否则，如果 `test` 表达式结果为 `true`，则执行 `statement` 语句。最后对 `step` 进行求值，循环的下一个迭代再次从 `test` 表达式开始。

大多数情况下，`initialize` 将对一个或多个变量赋值，它们通常用作计数器，`test` 表达式将这些变量与一个预定义的表达式进行比较，而 `step` 则负责更新这些变量的值。例如：

``` C
int x;
for (x = 0; x < 10; x++)
    printf("%d ", x);
```

首先，它执行 `initialize` 表达式，将变量 `x` 初始化为 `0`，接着，只要 `x` 的值小于 `10`，`x` 的值将在循环体中输出，再接着，`x` 的值在 `step` 表达式中自增，并重新计算 `test` 表达式。

`for` 循环语句中的三个表达式都是可选的，并且它们的任意组合都是有效的。由于第一个 `initialize` 表达式仅执行一次，因此它是最常被省略的表达式。例如，我们可以将上面的 `for` 循环改写为如下形式：

``` C
int x = 0;
for (; x < 10; x++)
    printf("%d ", x);
```

如果我们省略 `test` 表达式，那么这将是一个无限循环，即死循环（没有在循环体使用 `break` 或 `goto` 语句）。这与将 `test` 设置为 `1` 或 `true` 具有相同的效果，它们从不会变成 `false`。

下面的示例中，`for` 从 `1` 开始输出数字随后自增，并且一直进行。

``` C
for (x = 1; ; x++)
    printf("%d ", x);
```

如果省略 `step` 表达式，那么将没有更新计算的方法（循环体内没有更新）- 这通常不是我们所期望的。例如，下面的示例将一直输出数字 `1`。

``` C
for (x = 1; x <= 10;)
    printf("%d ", x);
```

需要注意的时，我们不能在 `test` 表达式中使用逗号运算符来同时检查多个变量，因为逗号运算符通常会将做操作数的结果给丢弃，例如：

``` C
int x, y;
for (x = 1, y = 10; x <= 10, y >= 1; x+=2, y--)
    printf("%d %d\n", x, y);
```

其输出结果为：

``` C
1 10
3 9
5 8
7 7
9 6
11 5
13 4
15 3
17 2
19 1
```

我们可以通过 `&&` 运算符来测试多个变量。

``` C
int x, y;
for (x = 1, y = 10; x <= 10 and y >= 1; x+=2, y--)
    printf("%d %d\n", x, y);
```

同样，我们也可以使用 `break` 语句来终止 `for` 循环。

这是用于计算平方和的函数：

``` C
int
sum_of_squares(int start, int end)
{
    int i, sum = 0;
    for (i = start; i <= end; i++)
        sum += i * i;
    return sum;
}
```

## 块语句（Blocks）

块语句是用括号括起来的一组零个或多个语句。块语句又被称为__复合语句__。通常，块语句用于 `if` 语句或循环语句的主体，以将语句进行分组。例如：

``` C
for (x = 1; x <= 10; x++)
{
    printf("x is %d\n", x);

    if ((x % 2) == 0)
        printf("%d is even\n", x);
    else
        printf("%d is odd\n", x);
}
```

我们也可以在块语句中嵌套块语句，例如：

``` C
for (x = 1; x <= 10; x++)
{
    if ((x % 2) == 0)
    {
        printf("x is %d\n", x);
        printf("%d is even\n", x);
    }
    else
    {
        printf("x is %d\n", x);
        printf("%d is odd\n", x);
    }
}
```

您可以在块语句内声明变量；这样的变量是该块语句的局部变量。在 C89 中，声明必须出现在其他语句之前，因此有时为此目的引入一个块语句十分有用。

``` C
{
    int x = 5;
    printf("%d\n", x);
}
printf("%d\n", x);   /* 编译错误！变量 x 仅存在于前一个块语句中 */
```

## 空语句（Null Statement）

空语句仅包含一个分号（`;`）。空语句不会执行任何操作、它也不会在任何地方存储值，同时它也不会在程序执行时产生额外的开销。

通常，空语句用作循环语句的主体，或用作 `for` 语句中的一个或多个表达式。例如下面的示例使用空语句作为循环的主体（并且它还计算了 `n` 的整数平方根，仅是示例而已，没多大作用）：

``` C
for (i = 1; i * i < n; i++)
    ;
```

下面的例子同样使用空语句作为循环的主体，但同时输出了变量 `x` 的值。

``` C
for (x = 1; x <= 5; printf("x is now %d\n", x), x++)
    ;
```

有时，我们需要在标签（该标签之后没有任何其它语句）之后加上一个空语句，从而解决移植性问题。

## 跳转语句

C 语言提供了三种跳转方式，它们分别是 `goto`、`break` 和 `continue`。接下来我们将分别介绍这三种跳转语句。

### goto 语句

我们可以使用 `goto` 语句来实现无条件的跳转到程序的某个地方，其一般形式如下：

``` C
goto label;
```

我们需要指定一个跳转的标签；当执行 `goto` 语句时，程序流将跳转到标签所在位置。例如：

``` C
goto end_of_program;
...
end_of_program:
```

标签可以是位于 `goto` 语句所在函数的任意位置，`goto` 语句不支持跨函数跳转，因此，我们不能使用 `goto` 语句来跳转到另一函数的标签位置。

我们也可以使用 `goto` 语句来模拟循环，但是通常不建议那样做，原因有两点：

1. 这使得代码难以阅读；
2. 可能导致编译器无法进行优化（GCC 是无法对其进行优化的）。

如果可能，我们应尽量使用 `for`，`while` 和 `do` 语句而不是 `goto` 语句。

GCC 支持 `goto` 语句跳转到一个由 `void *` 变量指定的地址处。要想使得其工作，我们需要使用 `&&` 而不是 `&` 来获取标签的地址，例如：

``` C
enum Play { ROCK=0, PAPER=1, SCISSORS=2 };
enum Result { WIN, LOSE, DRAW };

static enum Result turn(void)
{
    const void * const jumptable[] = {&&rock, &&paper, &&scissors};
    enum Play opp;                /* opponent’s play */
    goto *jumptable[select_option (&opp)];
rock:
    return opp == ROCK ? DRAW : (opp == PAPER ? LOSE : WIN);
paper:
    return opp == ROCK ? WIN  : (opp == PAPER ? DRAW : LOSE);
scissors:
    return opp == ROCK ? LOSE : (opp == PAPER ? WIN  : DRAW);
}
```

### break 语句

我们可以使用 `break` 语句来终止 `while`、`do`、`for` 或者 `switch` 语句。例如：

``` C
int x;
for (x = 1; x <= 10; x++)
{
    if (x == 8)
        break;
    else
        printf("%d ", x);
}
```

上面的程序将输出 `1` 到 `7` 的数字，当 `x` 自增到 `8` 时，表达式 `x == 8` 为 `true`，那么将执行 `break` 语句，从而跳转到 `for` 语句之后。

如果我们将 `break` 语句放在本身位于循环或 `switch` 语句内的循环或 `switch` 语句内时，`break` 仅终止最里面的循环或 `switch` 语句。

### continue 语句

我们可以在循环中使用 `continue` 语句来终止循环的当前迭代并开始下一次迭代，例如：

``` C
for (x = 0; x < 100; x++)
{
    if (x % 2 == 0)
        continue;
    else
        sum_of_odd_numbers += x;
}
```

同样地，如果我们将 `continue` 放在循环内的循环中，`continue` 只会影响最里层的循环。

## 返回语句（return）

我们可以使用 `return` 语句来结束函数的执行，并将程序控制权返回给调用它的函数，其一般形式如下：

``` C
return return-value;
```

`return-value` 是一个可选的返回表达式。如果函数的返回类型为 `void`，那么返回一个表达式是无效的，然而，我们可以使用 `return` 语句不返回任何值。

如果函数的返回类型与返回值不匹配，并且不能执行自动转换，那么返回的返回值同样是无效的。

如果函数的返回类型不为 `void` 并且没有指定返回值，那么这个返回语句是有效的，除非调用该函数的上下文环境需要一个返回值，例如：

``` C
x = cosine(y);
```

在这种情况下，函数 `cosine` 是在需要返回值的上下文中调用的，因此可以将该返回值分配给 `x`。

即使在不需要返回值的情况下，忽略非 `void` 返回类型函数的返回值并不是一个好主意。当使用 GCC 时，我们可以使用命令行参数 `-Wreturn-type` 来警告此类忽略了返回值的函数。

以下是具有 `void` 和非 `void` 返回类型函数中使用 `return` 语句的一些示例：

``` C
void
print_plus_five(int x)
{
    printf ("%d ", x + 5);
    return;
}

int
square_value(int x)
{
    return x * x;
}
```

## 类型定义语句 (typedef)

我们可以使用 `typedef` 语句为数据类型创建新的名称，其一般形式如下：

``` C
typedef old-type-name new-type-name
```

`old-type-name` 是以及存在的类型名，它可能包含多个 `token` （如，`unsigned long int`）；`new-type-name` 则是新定义的类型的名称，它必须是单个的标识符。为类型创建此新名称不会导致旧名称不再存在。例如：

``` C
typedef unsigned char byte_type;
typedef double real_number_type;
```

对于自定义数据类型，可以在定义类型时使用 `typedef` 为该类型创建新名称。

``` C
typedef struct fish
{
    float weight;
    float length;
    float probability_of_being_caught;
} fish_type;
```

我们也可以对数组进行类型定义，首先要提供元素的类型，然后在类型定义的末尾确定元素数量：

``` C
typedef char array_of_bytes[5];
array_of_bytes five_bytes = {0, 1, 2, 3, 4};
```

为类型选择名称时，应避免以 `_t` 后缀结束类型名称。编译器允许我们这样做，但是 POSIX 标准保留对标准库类型名称使用 `_t` 后缀。

## 参考

[1] https://www.gnu.org/software/gnu-c-manual/gnu-c-manual.html#Statements
