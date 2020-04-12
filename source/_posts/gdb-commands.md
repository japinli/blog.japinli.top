---
title: "GDB 命令"
date: 2020-04-07 22:09:34 +0800
category: Misc
tags: GDB
---

在{% post_link getting-in-and-out-of-gdb 上一篇 %}文章中，我们介绍了如何进入和退出 GDB，以及一些基本的配置，本文主要介绍 GDB 的命令语法、与命令相关的配置，如何对命令进行补全、有关命令的选项以及如何获取命令的帮助信息。

<!-- more -->

## 命令语法

GDB 命令是一个单行的输入，这一行是没有限制的。GDB 命令的语法是命令名后跟参数。例如，命令 `step` 可以跟一个参数代表步进的次数，如 `step 5`。我们也可以使用不带参数的 `step` 命令，某些命令不允许带参数。

如果 GDB 命令的名称缩写没有歧义的话，我们可以简写命令名称。在某些情况下，我们甚至可以不明确的缩写。例如，即使有其他命令以 `s` 开头，GDB 也将 `s` 定义为 `step`。我们可以通过将缩写用作 `help` 命令的参数来测试缩写。

如果输入空行（即输入 `RET` 回车键）的话则表示重复之前的命令。某些命令（例如，`run` 命令）不会以这种方式重复，这些命令通常我们也不需要它重复执行。用户定义的命令可以禁用这个功能。

当我们使用 `RET` 来重复 `list` 和 `x` 命令时，它们会构造新的参数而不是使用之前输入的参数。这样可以很容易的查看源码和内存。

GDB 还可以通过另一种方式使用 `RET`：以类似于通用实用程序的方式对冗长的输出进行分区。

任何位于 `#` 字符之后的文本都是注释的内容，这通常在命令文件中非常有用。

## 命令配置

许多命令都可以由命令特定的变量或者配置来更改其行为。我们可以使用 `set` 子命令来修改配置。例如，`print` 命令（查看数据）打印数组的内容取决于 `set print elements NUMBER-OF-ELEMENTS` 和 `set print array-indexes` 以及其他配置。

我们可以在 GDB 启动时加载的 gdbinit 文件中更改这些设置。这些配置也可以在 gdb 回话中临时修改。例如，要更改要打印的数组元素的限制，可以执行以下操作：

``` gdb
(GDB) set print elements 10
(GDB) print some_array
$1 = {0, 10, 20, 30, 40, 50, 60, 70, 80, 90...}
```

上面的命令 `set print elements 10` 将默认打印的数组大小由 200 修改为 10。如果仅打算将此限制 10 用于打印 some_array，则我们需要将其设置回默认值 200 。

某些命令允许使用命令选项来覆盖设置。例如，`print` 命令支持一系列选项来覆盖相关的全局设置。上面的命令我们可以使用下面的命令来实现：

``` gdb
(GDB) print -elements 10 -- some_array
$1 = {0, 10, 20, 30, 40, 50, 60, 70, 80, 90...}
```

或者，我们可以在命令调用期间使用 `with` 命令来临时更改设置，即 `with setting [value] [-- command]` 或者 `w setting [value] [-- command]`，在命令执行期间临时将 `setting` 设置为 `value`。其中 `setting` 是任何可以使用 `set` 命令修改的配置。如果没有提供 `command`，那么将会重复执行上一条命令。如果指定了 `command`，那么必须使用 `--` 来分割设置和命令。

``` gdb
(GDB) with print array on -- print some_array
```

等同于

``` gdb
(GDB) set print array on
(GDB) print some_array
(GDB) set print array off
```
当我们覆盖自定义命令或者使用 Python 和 Guile 时非常有用。
如果我们需要为一个命令临时修改多个设置，我们可以使用嵌套的 `with` 命令，例如：

``` gdb
with language ada -- with print elements 10
```

上面的命令临时地将语言设置为 `ada` 并且设置数组和字符串的输出限制为 10。

## 命令补全

当只有一个候选的命令时，GDB 可以补全用户输入的命令，任何时候，GDB 都可以查看用户可能输入的命令。这对于 GDB 的命令、子命令、命令选项以及程序的符号名都是有效的。

当我们需要补全命令时，我们可以直接输入 `TAB`。如果只有一种可能性，则 GDB 会填入单词，并等待我们完成命令（或按 `RET` 键输入）。例如，如果我们输入：

``` gdb
(gdb) info bre TAB
```

GDB 将会补全 `bre` 为 `breakpoints`，因为对于 `info` 的子命令并且以 `bre` 开头的只有 `breakpoints` 一个候选项：

``` gdb
(gdb) info breakpoints
```

此时，我们可以输入 `RET` 来执行 `info breakpoints` 命令，或者如果 `breakpoints` 不是我们期望的命令，我们可以使用退格键删除补全的内容，并输入我们想要的命令。（如果我们确定想要执行的命令就是 `info breakpoints`，我们可以在输入 `info bre` 之后立即输入 `RET` 来执行这条命令，这就是利用了 GDB 命令缩写的功能。）

如果我们在输入 `TAB` 进行补全时，候选项不止一个，那么 GDB 会发出铃声，我们可以尝试输入更多的字符来补全信息，或者再次输入 `TAB` 来查看可能的候选项。如下所示：

``` gdb
(gdb) b make_ TAB

GDB sounds bell; press TAB again, to see:

make_a_section_from_file     make_environ
make_abs_section             make_function_type
make_blockvector             make_pointer_type
make_cleanup                 make_reference_type
make_command                 make_symbol_completion_list
(gdb) b make_
```

当我么输入 `make_` 并按 `TAB` 键时，由于存在多个候选项，因此 GDB 将会发出铃声，当我么再次输入 `TAB` 时，GDB 会显示可能的候选项。随后，GDB 会赋值用户的输入并继续等待用户输入。

如果我们只是想要第一时间看到可能的候选项，我们可以直接输入 `M-?` 而不是连续输入两次 `TAB`。`M-?` 是 `META ?` 的简写。我们可以通过按 `ESC+?` 来达到相同的目的。

如果候选项非常大，GDB 将尽可能多的输出候选项。

``` gdb
(gdb) b mTABTAB
main
<... the rest of the possible completions ...>
*** List may be truncated, max-completions reached. ***
(gdb) b m
```

我们可以通过下面的命令来控制候选项的数量：

```
set max-completions limit
set max-completions unlimited
```

上面的命令用于设置显示的最大的候选项数量。当达到最大的限制时，GDB 将不会在显示其他可能的候选项。

```
show max-completions
```

显示候选项限制。

有时我们输入的内容逻辑上属于一个完整的内容，但是它包含了特殊字符，例如括号等。为了让补全在这种情况下也可以正常工作，我们需要使用单引号将其包裹起来。例如在补全 C++ 中模版名时经常会遇到这种情况，在正常情况下，GDB 会将 `<` 视为一个分隔符，并假定它是小于符号。

如下所示，当我们需要使用 `print` 或者 `call` 命令调用 C++ 模版函数时，我们需要区分使用那个版本，如 `name<int>()` 或 `name<float>()`。为了在这种情况下使用补全共鞥，我们需要在函数名称之前键入 `'` ，随后在使用补全的快捷键：

``` gdb
(gdb) p 'func< M-?
func<int>()    func<float>()
(gdb) p 'func<
```

但是在设置断点时，我们并不需要这样做，这是因为 GDB 知道我们需要在函数上设置断点：

``` gdb
(gdb) b func< M-?
func<int>()    func<float>()
(gdb) b func<
```

这对于 C++ 中的重载函数也是一样的。

``` gdb
(gdb) b bubble( M-?
bubble(int)    bubble(double)
(gdb) b bubble(dou M-?
bubble(double)
```

GDB 提供了 `set overload-resolution off` 来禁止重载函数的解析。


当 GDB 在补全结构体的成员时，他将尝试补全除了左侧之外可用的字段名称，例如：

``` gdb
(gdb) p gdb_stdout.M-?
magic                to_fputs             to_rewind
to_data              to_isatty            to_write
to_delete            to_put               to_write_async_safe
to_flush             to_read
```

上面的 `gdb_stdout` 变量在 GDB 源码中的定义如下所示：

``` c
struct ui_file
{
   int *magic;
   ui_file_flush_ftype *to_flush;
   ui_file_write_ftype *to_write;
   ui_file_write_async_safe_ftype *to_write_async_safe;
   ui_file_fputs_ftype *to_fputs;
   ui_file_read_ftype *to_read;
   ui_file_delete_ftype *to_delete;
   ui_file_isatty_ftype *to_isatty;
   ui_file_rewind_ftype *to_rewind;
   ui_file_put_ftype *to_put;
   void *to_data;
}
```

## 命令选项

GDB 的某些命令支持一个 `-` 给出命令选项，例如，`print -pretty`。与命令名称一样，命令选项也可以采用缩写的形式，前提是这个缩写不会导致歧义，同时，我梦也可以用 `TAB` 来补全命令选项（或者是查看可能的命令选项）。

GDB 某些命令将原始输入作为参数。例如，`print` 命令可以处理 GDB 支持的任何语言的表达式。在这些命令中，原始输入可能以 `-` 开始，因此这可能会与命令选项产生混淆，例如， `print -p` （它可以是 `print -pretty` 的缩写或者取变量 `p` 的相反数），因此如果我们的命令中包含选项，我们需要使用 `--` 来分割命令选项和参数。

例如：

``` gdb
(gdb) print -object on -pretty off -element unlimited -- *myptr
(gdb) p -o -p 0 -e u -- *myptr
```

上面两条命令是等价的。

我们可以使用补全功能来查看命令可用的选项，如下所示：

``` gdb
(gdb) print -TABTAB
-address         -max-depth       -raw-values      -union
-array           -null-stop       -repeats         -vtbl
-array-indexes   -object          -static-members
-elements        -pretty          -symbol
```

补全功能同样也能给出命令选项的参数，如下所示：

``` gdb
(gdb) print -elements TABTAB
NUMBER     unlimited
```

在上面的示例中，选项期望输入一个整数（如，100），而不是文本 `NUMBER`。

## 帮助

在 GDB 中，我们可以使用 `help` 命令来获取帮助信息。我们可以使用不带参数的 `help`（缩写为 `h`）来显示命令分类类的简短列表。

``` gdb
(gdb) help
List of classes of commands:

aliases -- Aliases of other commands
breakpoints -- Making program stop at certain points
data -- Examining data
files -- Specifying and examining files
internals -- Maintenance commands
obscure -- Obscure features
running -- Running the program
stack -- Examining the stack
status -- Status inquiries
support -- Support facilities
tracepoints -- Tracing of program execution without
               stopping the program
user-defined -- User-defined commands

Type "help" followed by a class name for a list of
commands in that class.
Type "help" followed by command name for full
documentation.
Command name abbreviations are allowed if unambiguous.
(gdb)
```

我们使用 `help class` 可以获取命令分类下的命令信息。例如，我们可以查看 `status` 分类。

``` gdb
(gdb) help status
Status inquiries.

List of commands:

info -- Generic command for showing things
        about the program being debugged
show -- Generic command for showing things
        about the debugger

Type "help" followed by command name for full
documentation.
Command name abbreviations are allowed if unambiguous.
(gdb)
```

`help command` 则可以查看具体命令的使用。

`apropos [-v] regexp` 命令可以在所有 GDB 命令中搜索与正则表达式匹配的命令。`-v` 是详细的意思。

``` gdb
apropos alias
alias -- Define a new command that is an alias of an existing command
aliases -- Aliases of other commands
d -- Delete some breakpoints or auto-display expressions
del -- Delete some breakpoints or auto-display expressions
delete -- Delete some breakpoints or auto-display expressions
```

`complete args` 命令用于获取所有以 `args` 开始的命令。例如：

``` gdb
(gdb) complete i
if
ignore
inferior
info
init-if-undefined
interpreter-exec
interrupt
(gdb)
```

除了 `help` 命令之外，我们还可以使用 `info` 和 `show` 命令来获取程序或 GDB 的状态。

* `info` - 该命令可以缩写为 `i`，它用于获取当前程序的状态。例如，我们可以使用它来函数的参数 `info args`，查看当前使用的寄存器 `info registers`，或者是查看当前设置的断点信息 `info breakpoints`。我们可以使用 `help info` 来查看所有 `info` 的子命令。
* `set` - 我们可以使用 `set` 命令给环境变量赋值。例如，我们可以使用 `set prompt $` 将 GDB 命令提示符号修改为 `$` 符。
* `show` - 与 `info` 命令不通，`show` 用来查看 GDB 自身的状态。我们可以改变大多数我们可以使用 `show` 命令查看的内容。例如，我们可以使用 `set radix` 命令设置系统编号，并使用 `show radix` 来查询当前值。

为了获取所有可以设置的参数，我们可以使用没有参数的 `show` 命令，或者 `info set` 命令，它们是等效的。

有几个 `show` 的子命令是无法使用 `set` 命令进行修改的。

* `show version` - 查看当前 GDB 的版本信息。
* `show copying` & `info copying` - 显示有关复制 GDB 的权限的信息。
* `show warranty` & `info warranty` - 显示 GNU "NO WARRANTY" 声明。
* `show configuration` - 显示编译 GDB 时的详细配置信息。

## 参考

[1] https://sourceware.org/gdb/current/onlinedocs/gdb/Commands.html#Commands
