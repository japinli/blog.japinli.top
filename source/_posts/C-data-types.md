---
title: "C 语言数据类型"
date: 2019-06-03 22:26:40 +0800
category: Programming
tags: C
---

C 语言的数据类型可以分为七种，它们分别是原始类型（内建类型）、枚举类型、联合类型、结构体、数组、指针以及不完全类型。此外，本文还介绍了类型限定符、存储类型说明符以及类型重命名。

<!-- more -->

## 原始数据类型

C 语言提供的原始数据类型可以分为三类：a. 整数类型；b. 实数类型；c. 复数类型。接下来的部分将详细介绍这三类数据类型。

### 整数类型

整数数据类型的大小范围从 8-bit 到 32-bit 之间。在 C99 标准中扩展到了 64-bit。我们应该使用整数数据类型来存储整数值，当然我们也可以用 `char` 类型来存储字符。下表给出了这些整数类型的最小范围，在不同的平台上这个范围可能还会更大。

| 数据类型               | 比特位 | 最小值                     | 最大值                     |
|------------------------|--------|----------------------------|----------------------------|
| signed char            | 8      | -128                       | 127                        |
| unsigned char          | 8      | 0                          | 255                        |
| char                   | 8      | -128/0                     | 127/255                    |
| short int              | 16     | -32,768                    | 32,767                     |
| unsigned short int     | 16     | 0                          | 65,535                     |
| int                    | 32     | -2,147,483,648             | 2,147,483,647              |
| unsigned int           | 32     | 0                          | 4,294,967,295              |
| long int               | 32/64  |                            |                            |
| unsigned long int      | 32/64  |                            |                            |
| long long int          | 64     | -9,223,372,036,854,775,808 | 9,223,372,036,854,775,807  |
| unsigned long long int | 64     | 0                          | 18,446,744,073,709,551,615 |

* __char__ - 该数据类型被定义为 `signed char` 或者 `unsigned char` 类型，这取决于不同的系统平台。
* __short int__ - 该数据类型可以写为 `short`、`signed short int` 或 `signed short`。
* __unsigned short int__ - 该数据类型可以简写为 `unsigned short`。
* __int__ - 该数据类型可以写为 `signed int` 或 `signed`。
* __unsigned int__ - 该数据类型可以简写为 `unsigned`。
* __long int__ - 该数据类型的长度取决于您的系统，他可以是 32-bit 或 64-bit。它可以写为 `signed long int`、`signed long` 或 `long`。
* __unsigned long int__ - 该数据类型与 `long int` 数据类型相似。它可以简写为 `unsigned long`。
* __long long int__ - 该数据类型并非 C89 标准所定义，它是 C99 或 GNU C 标准中的一部分。它可以被写为 `signed long long int`、`signed long long` 或 `long long`。
* __unsigned long long int__ - 该数据类型与 `long long int` 数据类型相似。它可以简写为 `unsigned long long`。

### 实数类型

C 语言提供了三种类型用于表示小数（浮点数）。尽管目前来树这些类型的大小和范围在大多数计算机上都是一致的，但是历史上它们还是因为系统类型不一而存在差异。这些类型的最大值和最小值在 `float.h` 文件中通过宏的方式定义。

* `float` - 三种浮点数类型中取值范围最小的类型（如果它们的大小不一致的情况）。其最小值由 `FLT_MIN` 给出，并且最小值不能大于 1e-37；最大值则由 `FLT_MAX` 给出，并且不能小于 1e37。
* `double` - 该数据类型至少应与 `float` 类型一样大，甚至可能超过 `float` 类型。其最小值和最大值分别由 `DBL_MIN` 和 `DBL_MAX` 给出。
* `long double` - 该数据类型至少应与 `float` 类型一样大，甚至可能超过 `float` 类型。其最小值和最大值分别由 `LDBL_MIN` 和 `LDBL_MAX` 给出。

所有的浮点类型均为有符号，如果尝试使用无符号浮点类型，如 `unsigned float` 则会导致编译时错误。例如：

```
$ cat test.c
#include <stdio.h>

int
main(int argc, char **argv)
{
  unsigned float a = 0.0;
  return 0;
}
$ gcc test.c
test.c:6:3: error: 'float' cannot be signed or unsigned
  unsigned float a = 0.0;
  ^
1 error generated.
```

C 语言提供的实数是具有有限精度，因此，它并不能精确的表示所有实数。大多数采用 GCC 编译的计算机系统都采用二进制来表示实数，这就以为着它不能精确的表示某些数，例如 4.2。为此，在对浮点数进行比较时尽量不要使用 `==` 操作符，而是检测该数是否在可以容忍的误差范围内。

### 复数类型

GCC 在 C89 的基础上引入了复数类型，同样的，C99 中也增加了复数类型，但是它们之间由许多不同之处。接下来我们将先介绍标准库中的复数类型，随后再介绍 GNU 扩展中的复数类型。

#### 标准复数类型

复数类型在 C99 标准中引入，它有以下三种类型：

* `float _Complex`
* `double _Complex`
* `long double _Complex`

该类型以下划线和大写字母开头主要是为了避免与现有程序冲突。在 C99 标准库的 `<complex.h>` 头文件中定义了一系列宏使得复数的使用更为方便。例如，`complex` 将被扩展为 `_Complex`，这使得形如 `double complex` 的变量声明看起来更自然一些; `I` 为 `const float _Complex` 类型的常量，用以表示复数的虚数部分的单位，也可以写作 `i`。

`<complex.h>` 头文件还包含了许多用于复数计算的函数，如 `creal` 和 `cimag` 分别用于获取复数的实数部分和虚数部分。

#### GNU 扩展的复数类型

GCC 也为 C89 标准引入了复数类型。它与标准的复数类型拼写不太一样。其形式如下所示：

* `__complex__ float`
* `__complex__ double`
* `__complex__ long double`

GCC 复数类型的扩展不仅限于复数类型，因此你可以定义复数字符类型和复数整型类型；实际上 `__complex__` 可以应用于任何原始类型之上。例如：

* `__complex__ float` - 该数据类型包含两个部分，实数部分和虚数部分；实数部分和虚数部分均为 `float` 数据类型。
* `__complex__ int` - 该数据类型同样包含两个部分，实数部分和虚数部分；实数部分和虚数部分均为 `int` 数据类型。

在 GCC 扩展中，我们可以使用 `__real__` 和 `__imag__` 来获取复数的实数部分和虚数部分。例如：

``` C
__complex__ float a = 4 + 3i;

float b = __real__ a;        /* b 现在为 4 */
float c = __imag__ a;        /* c 现在为 3 */
```

## 枚举类型

枚举类型是一种自定义类型，它用于存储整型常量值并通过名称来引用。默认情况下，枚举类型值的数据类型为 `signed int`；你可以使用 GCC 编译器的 `-fshort-enums` 选项来使用尽可能小的整型类型。这两种行为都符合 C89 标准，但是在同一个程序中混合使用这些选项可能导致不兼容。

### 定义枚举类型

枚举类型通过关键字 `enum` 进行定义，后面紧跟枚举类型的名称（可以省略，此时为匿名的枚举类型），然后是由逗号分割开的枚举值（枚举值放在括号内），最后是代表结束的分号。如下所示：

``` C
enum friut { grape, cherry, lemon, kiwi };
```

上述示例定义了 `friut` 的枚举类型，它包含 `grape`，`cherry`，`lemon` 和`kiwi` 四个整型，它们的值分别为 `0`，`1`，`2`，和 `3`。当然，你也可以指定一个或多个枚举类型的值，例如：

``` C
enum more_friut { banana = -17, apple, blueberry, mango };
```

上述示例中定义的 `banana` 的值为 `17`，其它值依次加 `1`：即 `apple = -16`，`blueberry = -15`，`mango = -14`。除非特别说明，枚举类型的值为前一个值加 `1`（第一个值默认为 `0`）。此外，你还可以引用在该枚举中已经定义了的值，例如：

``` C
enum yet_more_fruit { kumquat, raspberry, peach, plum = peach + 2 };
```

上述示例中 `kumquat = 0`，`raspberry = 1`，`peach = 2`，`plum = 4`。

### 声明枚举类型

你可以在定义枚举类型的同时声明枚举类型变量，如下所示：

``` C
enum fruit { banana, apple, blueberry, mango } my_fruit;
```

当然，你也可以将定义和变量声明分离开，如下所示：

``` C
enum fruit { banana, apple, blueberry, mango };
enum fruit my_fruit;
```

需要注意的是你不能声明匿名的枚举类型。

虽然它们被视为枚举类型的变量，但是你仍然可以为它们赋值任何整型值包括来自其它枚举类型的值。但是当枚举类型的值确定之后，你就不能再更改它，它们将被视为常量。

``` C
enum fruit { banana, apple, blueberry, mango };
banana = 15;  /* 你无法为 banana 赋值新值 */
```

枚举类型与 `switch` 语句结合起来相当有用，这是因为当在 `switch` 中只处理了部分枚举类型值时，编译器将会给出警告。

## 联合类型

联合类型同样属于一种自定义类型，它用于在同一内存空间存储多个变量。你可以随时访问这些变量中的任何一个，其实每次我们应该只读取其中一个变量，由它的定义可以看出，当修改这些变量中的某一个时，其它变量也会发生变化。

### 定义联合类型

联合类型通过关键字 `union` 进行定义，后跟由打括号包围起来的联合类型成员，联合类型的成员定义则与普通变量的定义类似。在 `union` 和开始大括号之间可以指定联合的名称（可选，如果不指定后续则无法引用，除非使用 `typedef` 语法）。下面是一个简单的示例：

``` C
union numbers
{
    int i;
    float f;
};
```

### 声明联合类型

如果在定义联合类型时给出了名称，那么我们可以在定义的同时或者定义之后声明联合类型变量。

#### 定义时声明变量

例如，我们可以采用如下形式在定义联合类型的同时声明变量。

``` C
union numbers
{
    int i;
    float f;
} first_num, second_num;
```

上面的示例声明了两个 `union numbers` 类型的变量：`first_num` 和 `second_num`。

#### 定义后声明变量

当然，我们也可以将定义与变量声明分割开来。

``` C
union numbers
{
    int i;
    float f;
};
union numbers first_num, second_num;
```

上面的形式与定义时声明变量的效果一致。

#### 初始化联合类型成员

我们在声明变量的时候也可以对其进行初始化操作。例如：

``` C
union numbers
{
    int i;
    float f;
};
union numbers first_num = { 5 };
```

上面的示例将 `union numbers` 类型的 `first_num` 变量的第一个成员 `i` 初始化为 `5`。除此之外，我们还可以初始化指定的联合类型成员，有两种方式用于初始化联合类型成员。

* `member: value` - 成员名 + `:` 的形式，例如：`union numbers first_num = { f: 3.14 };`。
* `.member = value` - `.` + 成员名 + `=` 的形式，例如：`union numbers first_num = { .f = 3.14}`。

当然，我们也可以在定义的同时声明变量并进行初始化。例如：

``` C
union numbers
{
    int i;
    float f;
} first_num = { 5 };
```

### 访问联合类型

对联合类型的访问通过访问操作符来完成，即将联合类型的变量放在访问操作符的左边，联合类型的成员名放在访问操作符的右边。例如：

```
union numbers
{
    int i;
    float f;
};
union numbers first_num;
first_num.i = 3;
first_numb.f = 4.123;
```

需要注意的时，当需改联合类型的 `f` 成员时，成员 `i` 的值相应的也发生了改变。

### 联合类型大小

联合类型的大小取决于联合类型成员中占空间最大的成员。例如：

```
union numbers
{
    int i;
    float f;
};
```

该联合类型的大小为 `sizeof(float)` 的大小，因为 `float` 比 `int` 所占空间大。由于在联合中所有的数据成员共享同一地址空间，因此，只需要该空间能存储联合类型中占空间最大的成员即可。

## 结构体

结构体是由程序员定义数据类型，该数据类型由变量和其它数据类型（可能包含其它结构体）组成。

### 定义结构体

结构体的定义与联合类型相似，所不同的是结构体的定义使用 `struct` 关键字。例如：

``` C
struct point
{
    double x, y;
};
```

上面的定义中我们定义了一个 `struct point` 的新类型，该类型包含两个成员：`x` 和 `y`，它们均为 `double` 类型。结构体（或联合类型）都可以包含其它结构体或者联合类型，但是不能包含自身。但是，它们可以包含自身类型的指针（参见不完全类型）。

### 声明结构体变量

结构体变量的声明与联合类型一样，可以在定义时或定义之后声明。

#### 定义时声明变量

与联合类型类似，我们可以在定义结构体时声明变量。

``` C
struct point
{
    double x, y;
} first_point, second_point;
```

#### 定义后声明变量

当然，我们也可以将定义与变量声明分割开来。例如：

``` C
struct point
{
    double x, y;
};
struct point first_point, second_point;
```

#### 初始化结构体变量

当你在声明结构体变量时可以为结构体成员变量初始化特定的值。如果你没有为结构体提供初始化值，那么它的值取决于是否有静态存储（后续介绍）。如果有，那么整型被初始化为 `0`，指针类型初始化为 `NULL`;其它情况下成员变量的值是不确定的。初始化成员变量的一种方式是在大括号中按定义时的顺序给出成员的值。

``` C
struct point
{
    double x, y;
};
struct point first_point = { 5.0, 4.0 };
```

另一种初始化成员变量的方式是按成员变量名进行初始化。采用这种方式进行初始化可以按任意顺序进行初始化，并且可以保留部分成员不初始化。按成员变量名称初始化也有两种方式：

* `.member = value` - C99 标准以及 GCC 的 C89 扩展。例如：`struct point first_point = { .y = 10.0, .x = 5.0 };`。
* `member: value` - GNU C 扩展。例如：`struct point first_point = { y: 10.0, x: 5.0 };`。

同样地，我们可以在定义结构体时声明变量并进行初始化操作。

``` C
struct point
{
    double x, y;
} first_point = { 5.0, 4.0 };
```

当然，我们也可以只初始化部分成员变量。例如：

``` C
struct pointy
{
    int x, y;
    char *p;
};
struct pointy first_pointy = { 5 };
```

在上面的示例中，`x` 被初始化为 `5`，`y` 被初始化为 `0`，`p` 被初始化为 `NULL`。这里的规则就是 `y` 和 `p` 采用静态存储的初始化规则。

当结构体中包含结构体时，我们同样可以对其进行初始化。例如：

``` C
struct point
{
    double x, y;
};
struct rectangle
{
    struct point top_left, bottom_right;
};
struct rectangle my_rectangle = { {1.0, 10.0}, {5.0, 4.0} };
```

在上面的示例中，我们定义了一个 `struct rectangle` 结构体，它包含两个 `struct point` 类型的成员变量。在初始化的过程中我们使用大括号来区分不同的结构体成员，其实这个大括号是可以省略的（可读性不强）。

### 访问结构体成员

结构体成员的访问与联合类型相似。例如

``` C
struct point
{
    double x, y;
};

struct point first_point;

first_point.x = 0.0;
first_point.y = 5.0;
```

如果结构体中还包含结构体，我们同样可以使用这样方式进行访问。

``` C
struct rectangle
{
    struct point top_left, bottom_right;
};

struct rectangle my_rectangle;

my_rectangle.top_left.x = 0.0;
my_rectangle.top_left.y = 5.0;

my_rectangle.bottom_right.x = 10.0;
my_rectangle.bottom_right.y = 0.0;
```

### 位域

在结构体中，我们可以为整型添加一个整数值来告知其不实用标准的字节大小，这种方式被称为位域。例如：

``` C
struct card
{
    unsigned int suit : 2;
    unsigned int face_value : 4;
};
```

上面的示例中定义了两个位域字段：`suit` 和 `face_value`，它们的位长度分别为 `2-bit` 和 `4-bit`，它们的取值范围分别为 `0~3` 和 `0~15`（无符号数）。如果它们被定义为有符号数，则其取值范围分别为 `-2~1` 和 `-8~7`。

我们可以采用通项来进行表示，`N-bit` 的位域字段可以表示的范围为：

* 无符号数 - $[0, 2^N-1]$
* 有符号数 - $[-\frac{2^N}{2}, \frac{2^N}{2}-1]$

我们可以使用匿名的位域字段（即没有名称），这样做的目的主要是为了控制那些位可以使用，然而，这种方式可能移植性不是很好且很少使用。此外，我们还可以定义大小为 `0` 的位域字段，这表示后续的位域字段不与前面的位域字段使用同一个单元，这通常也是没有多大用处。

``` C
struct zero_bit_test
{
    int    bit1 : 2;
    int         : 0;
    int    bit2 : 4;
};
```

__注意：__

1. 上述示例的结构体大小为 8 字节。
2. 你不能对位域字段进行取地址运算 (`&` 操作符)。

### 结构体大小

结构体的大小等于结构体中所有成员的大小之和，除此之外，它还可能包含用于特定字节对齐的填充字节。根据不同的计算机类型，某些细节可能不同，但是 4 字节和 8 字节对齐是经常见到的。这样做的目的是为了加快结构体类型的存储访问。

作为 GNU 的扩展，GCC 允许没有成员的结构体，即其大小为 `0`。如果你想要显示的去掉结构体的填充字节（这可能会降低结构体内存的访问速度），GCC 提供了多种方式。最简单的方式就是通过使用 `-fpack-struct` 选项。关于更多的填充细节可以参考 GCC 的文档（见扩展阅读 [3]）。

## 数组

数组是一种允许在连续的内存空间中存储一个或多个元素。C 语言的数组以 0 作为开始索引。

### 声明数组

数组的声明由元素的数据类型，数组名以及元素个数组成。例如，`int my_array[10];`。标准的 C 代码中，数组的元素个数必须为正数。而在 GNU 扩展中，数组的元素个数最小可以为 0。长度为 0 的数组在结构体中作为最后一个成员对于定义变长对象非常有用。例如：

``` C
struct line
{
    int length;
    char contents[0];
};

{
    struct line *this_line = (struct line *)
        malloc(sizeof(struct line) + this_length);
    this_line->length = this_length;
}
```

另一个 GNU 扩展是支持使用变量定义数组长度，而在标准 C 中仅支持常量。例如：

``` C
int
my_function (int number)
{
    int my_array[number];
    ...;
}
```

### 初始化数组

你可以在声明数组变量的时候给它提供一组初始化值进行初始化。

``` C
int my_array[5] = { 0, 1, 2, 3, 4 };
```

当然，你也可以只初始化部分值。

``` C
int my_array[5] = { 0, 1, 2 }
```

上面的示例中 `my_array` 的前三个值分别初始化为 `1`，`2`，`3`，剩余的两个则被初始化为 `0`。

在 C99 标准或 C89 的 GNU 扩展中支持乱序初始化，即指定需要初始化的元素下标以及初始值。例如：

``` C
int my_array[5] = { [4] 1, [2] 2 };
int my_array[5] = { [4] = 1, [2] = 2 };
int my_array[5] = { 0, 0, 2, 0, 1 };
```

上述三种声明方式的效果是一样的。在 GNU 中，数组还支持范围的初始化，即将一个范围内的值初始化为同一个值。例如：

``` C
int my_array[100] = { [0 ... 9] = 1, [10 ... 98] = 2, 4 };
```

上述示例中将 `my_array` 的 `0` 到 `9` 的值初始化为 `1`；将下标 `10` 到 `98` 的值初始化为 `2`，同时将最后一个元素初始化为 `4`。这里需要注意的是在下标与 `...` 之间必须要有空格。

如果你在初始化是对所有元素都进行了初始化，那么你可以不需要指定数组的大小。

``` C
int my_array[] = { 0, 1, 2, 3, 4 };
```

上述示例中声明了一个长度为 `5` 的数组，其值被初始化为 `0`，`1`，`2`，`3`，`4`。此外，如果你通过元素下标的方式进行初始化，那么数组的长度将是最大的下标加 `1`。例如：

``` C
int my_array[] = { 0, 1, 2, [99] = 99 };
```

上述示例中声明了一个长度为 `100` 的数组，其前三个值为 `0`，`1`，`2`；最后一个值为 `99`；其余得知则被初始化为 `0`。

### 访问数组元素

数组元素的访问是通过数组变量名以及数组下标的方式进行访问的。这里再次强调数组下标由 `0` 开始。例如，对 `my_array` 数组的第一个值赋值，其形式如下：

``` C
my_array[0] = 5;
```

### 多维数组

C 语言中多维数组的声明是在数组的基础之上在加数组符号及其长度，即数组的数组。例如：

``` C
int two_dimensions[2][5] = { {1, 2, 3, 4, 5}, {6, 7, 8, 9, 10} };
```

上面的示例声明了一个二维数组。多维数组的元素访问与一维数组类型，`two_dimensions[0][1] = 4`。

需要注意的是在 C 语言中，多维数组是按行的方式进行存储的，即 `two_dimensions[0][2]` 之后紧跟的元素是 `two_dimensions[0][3]`，而不是 `two_dimensions[1][2]`。

### 字符串数组

你可以使用字符的数组来存储字符串，该数组可以由有符号字符和无符号字符组成。正如前面介绍，当你在声明数组时，你可以指定数组的大小，此时字符串的大小（包括用于表示结束的 `null` 字符）不能超过数组的大小，如果采用这样方式声明字符串数组，可以不必立即初始化；当然你也可以指定初始化值而不给出数组大小，此时系统将为你分配足够的空间用于存储数组元素。

字符串数组的初始化有两种方式：(a) 使用逗号分割的字符数组；(b) 使用字符串常量。例如：

``` C
char blue[26];
char yellow[26] = {'y', 'e', 'l', 'l', 'o', 'w', '\0'};
char orange[26] = "orange";
char gray[] = {'g', 'r', 'a', 'y', '\0'};
char salmon[] = "salmon";
```

无论是上述那种情况，即便是没有显示的给出结束符（`\0`），字符数组也将会在字符的结尾添加结束符。需要注意的时，如果采用单个字符数组的方式进行初始化字符串，则末尾的结束符号不一定会有，它可能存在，也可能不存在，因此最好不要依赖这个特性。例如：

``` C
char bad_str[4] = { 'a', 'b', 'c', 'd' };
```

当初始化完成之后，你不能通过赋值操作符为其赋予新的字符串，例如：

``` C
char lemon[26] = "custard";
lemon = "steak sauce";      /* 失败 */
```

在使用字符数组时可能存在你给定了数组的大小，但是使用了更大的字符串进行初始化；此时超出的部分并不会重写已经写入数组的内容，而你将在编译时得到警告。由于原始数组大小仍然存在，因此超出原始大小的字符串的任何部分都将写入未分配给它的内存位置。

### 联合类型数组

你可以像创建基本类型数组一样创建联合类型的数组。

``` C
union numbers
{
    int i;
    float f;
};
union numbers number_array[3];
```

其初始化的方式为 `union numbers number_array[3] = { {3}, {4}, {5} };`。其中数组内部的大括号是可以省略的，其访问形式同普通类型一样。

### 结构体数组

同样地，你也可以为结构体声明数组。

``` C
struct point
{
    int x, y;
};
struct point point_array[3];
```

上述示例中声明了一个结构体变量 `point_array`，该变量包含三个 `struct point` 元素。当然，我们也可以声明变量的时候同时初始化。

``` C
struct point point_array[3] = { {2, 3}, {4, 5}, {6, 7} };
```

其中，结构体元素的初始化可以省略其中的大括号，而结构体数组的元素访问同联合类型一样。

## 指针

指针保存了存储常量和变量的内存地址。对于任何数据类型，包括基本类型和自定义类型，您都可以创建一个指针来保存该类型实例的内存地址。

### 声明指针变量

指针的声明与其它变量声明类型包括数据类型和变量名，数据类型代表了指针所指向的内存空间存储的变量类型。指针的声明需要在数据类型和变量名称之间加上间接运算符，其一般形式如下：

``` C
data-type * name;
```

间接运算符之间的空白字符无关紧要。下面的形式与上面的效果是一样的。

``` C
data-type *name;
data-type* name;
```

需要注意的是，当在一个语句中声明多个指针变量时需要在每个变量名之前加上间接运算符。

``` C
int *foo, *bar;  /* 两个指针 */
int *baz, quux;   /* 一个指针以及一个整型变量 */
```

### 初始化指针变量

指针变量的初始化需要用到取地址运算符。我们可以在变量声明的时候对其进行初始化。

``` C
int i;
int *ip = &i;
```

存储在指针变量的内容是一个整型值，它表示计算机内存的地址。在声明变量之后如果需要对指针变量进行赋值，此时就不再需要间接运算符了。如果在后续过程中使用了间接运算符，那么改变的将是指针所指向的变量的值而不是指针变量本身。例如：

``` C
int i, j;
int *ip = &i;  /* 变量 ip 现在存储的是变量 i 的地址 */
ip = &j;       /* 变量 ip 现在存储的是变量 j 的地址 */
*ip = &i;      /* 变量 j 现在存储的是变量 i 的地址 */
```

最要的是如果你没有使用一个对象的地址对指针变量进行初始化，那么它所指向的地方是不确定的，这时使用该指针变量可能导致程序崩溃（通常来说，这种情况被称为__未定义行为 - undefined behavior__）。

### 联合类型指针

联合类型的指针变量同原始类型一样。

``` C
union numbers
{
    int i;
    float f;
};
union numbers foo = {4};
union numbers *number_ptr = &foo;
```

当然我们也可以通过指针变量实现对联合类型的成员访问，但是我们不能使用常规的成员访问符而需要使用间接成员访问符。例如：

``` C
number_ptr->i = 500;
```

### 结构体类型指针

结构体类型的指针变量与联合类型一样。

``` C
struct fish
{
    float length, weight;
};
struct fish salmon = {4.3, 5.8};
struct fish *fish_ptr = &salmon;

fish_ptr->length = 5.1;
fish_ptr->weight = 6.3;
```

## 不完全类型

当在定义结构体、联合类型以及枚举类型时不指定其成员（对于枚举类型来说即枚举值），这种类型被称为不完全类型 (incomplete type)。你不可以定义不完全类型的变量，但是可以定义不完全类型的指针。例如：

``` C
struct point;
```

上面定义了一个不完全类型，在给出该类型的完全定义之前，我们不能使用它定义变量，你需要在后续给出该类型的完整定义。

``` C
struct point
{
    double x, y;
};
```

这种不完全类型通常用于链表。

``` C
struct singly_linked_list
{
    struct singly_linked_list *next;
    int x;
    /* 其它元素 */
};
struct singly_linked_list *list_head;
```

## 扩展阅读

[1] What Every Computer Scientist Should Know About Floating-Point Arithmetic
[2] section 4.2.2 of Donald Knuth’s The Art of Computer Programming.
[3] https://gcc.gnu.org/onlinedocs/gcc-9.1.0/gcc/Code-Gen-Options.html#Code-Gen-Options

## 参考

[1] https://www.gnu.org/software/gnu-c-manual/gnu-c-manual.html#Data-Types
