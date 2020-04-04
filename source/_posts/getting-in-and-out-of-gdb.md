---
title: "GDB 基本使用"
date: 2020-01-13 22:42:31 +0800
category: Misc
tags: GDB
---

在工作中经常使用 GDB 来调试程序，但是一直都没有系统的进行学习过，为此，我打算对其进行一个系统的学习，学习的主要材料来自 GNU GDB 文档 [Debugging with GDB](https://sourceware.org/gdb/current/onlinedocs/gdb/)。

本文主要包括如何运行以及退出 GDB，通常，我们使用 `gdb` 即可进入 GDB，而 `quit` 命令或者 `Ctrl-d` 快捷键便可以退出 GDB。

<!-- more -->

## 运行 GDB

通过在命令行中输入 `gdb` 就可以进入到 GDB，此时，GDB 将读取用户输入的命令并执行，这其实就是一个交互式的界面，读取用户命令，执行用户命令，再读取用户命令，直到用户输入退出指令执行退出操作。

我们还可以在 `gdb` 运行时指定一系列参数和选项，从而指定更多关于我们调试环境的一些设置。

``` shell
$ gdb program
```

上面是最常用的 GDB 使用方式，它指定我们将要调试的可执行程序。此外，我们还可以指定调试的程序以及一个 core 文件：

``` shell
$ gdb program core
```

如果我们要调试正在运行的程序，我们还可以使用进程 ID 或者 `-p` 选项作为第二个参数：

``` shell
$ gdb program 1234
$ gdb -p 1234
```

上面的命令将使用 GDB 附加到进程 ID 为 `1234` 的进程上，如果使用 `-p` 选项，我们可以省略 `program` 程序名。

我们可以选择使用 `--args` 来向调试的程序传递参数，该选项将终止可选参数的处理。例如：

``` shell
$ gdb --args gcc -O2 -c foo.c
```

上面的命令将使用 GDB 调试 gcc 程序，并将 `-O2 -c foo.c` 作为 `gcc` 的命令行参数。

GDB 运行时会输出类似下面的信息：

```
$ gdb
GNU gdb (GDB) 8.3
Copyright (C) 2019 Free Software Foundation, Inc.
License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
Type "show copying" and "show warranty" for details.
This GDB was configured as "x86_64-apple-darwin18.5.0".
Type "show configuration" for configuration details.
For bug reporting instructions, please see:
<http://www.gnu.org/software/gdb/bugs/>.
Find the GDB manual and other documentation resources online at:
    <http://www.gnu.org/software/gdb/documentation/>.

For help, type "help".
Type "apropos word" to search for commands related to "word".
```

我们可以使用 `--slient` 或者 `-q/--quite` 选项来抑制这些信息的输出。还有很多关于 GDB 的命令行选项，我们可以通过 `gdb -help` 来获取其使用方法。

### 文件选择

当 GDB 运行时，它将读取选项以外的所有参数以指定可执行文件和 core 文件（或者进程 ID）中读取其它参数。这与分别由 `-se` 和 `-c` （或者 `-p`）指定参数相同。（GDB 将第一个没有选项关联的参数视为与 `-se` 后跟参数等效；将第二个没有选项关联的参数视为与 `-c` 或者 `-p` 后跟参数等效。）如果第二个参数以数字开始，GDB 首先尝试将其附加为一个进程，如果失败了，GDB 则试图将其作为一个 core 文件来打开。如果我们有一个以数字开始的 core 文件，那么我们可以为期添加前缀（如 `./`）来避免 GDB 将其视为一个进程 ID。

如果 GDB 不支持配置 core 文件，例如对于大多是嵌入式目标，那么 GDB 将输出日志并忽略第二个参数。

大多数 GDB 选项都有长，短选项两种形式；如果我们截断了长格式，只要足够 GDB 区分歧义，那么它也是能识别的。

<style>
table th:nth-of-type(1) {
    width: 35%;
}
table th:nth-of-type(2) {
    width: 65%;
}
</style>

| 选项                                              | 说明                       |
|---------------------------------------------------|----------------------------|
| `-symbols file`, <br/>`-s file`                   | 从文件 `file` 中读取符号表 |
| `-exec file`, <br/>`-e file`                      | 使用文件 `file` 作为可执行文件在适当时执行，并与核心转储一起检查纯数据 |
| `-se file`                                        | 从文件 `file` 中读取符号表，并将其用作可执行文件 |
| `-core file`, <br/>`-c file`                      | 使用文件 `file` 作为 coredump 文件进行检查 |
| `-pid number`, <br/>`-p number`                   | 与 `attach` 命令一样，附加到进程 ID 为 `number` 的进程 |
| `-command file`, <br/>`-x file`                   | 执行 `file` 文件中的命令，该文件的内容与 `source` 命令的内容相同 |
| `-eval-command command`, <br/>`-ex command`       | 执行单个的 GDB 命令，可多次使用，也可以与 `-x` 交叉使用 |
| `-init-command file`, <br/>`-ix file`             | 在加载 `inferior` 之前（在加载 `gdbinit` 文件之后）执行 `file` 文件内的 GDB 命令 |
| `-init-eval-command command`,<br/> `-iex command` | 在加载 `inferior` 之前（在加载 `gdbinit` 文件之后）执行单个 GDB 命令 |
| `-directory directory`, <br/>`-d directory`       | 将目录 `directory` 作为源码或脚本的搜索路径 |
| `-r`, <br/>`-readnow`                             | 立即读取每个符号文件的整个符号表，而不是默认值，默认值是根据需要逐步读取它。这会使启动速度变慢，但会使以后的操作变快 |
| `--readnever`                                     | 不要读取每个符号文件的符号调试信息。这使启动速度更快，但以无法执行符号调试为代价。DWARF展开信息也不会被读取，这意味着 backtrace 可能变得不完整或不准确。这种用法通常是用户只关心程序的执行顺序。 |

### 选择模式

我们可以在不同模式下运行 GBD，例如，批处理模式或者静默模式。

* `-nx, -n` 不要执行初始化文件中的命令。GDB 包含三个初始化文件，它们按照如下的顺序加载：
  * `system.gdbinit` - 系统级别的初始化文件，它由编译时选项 `--with-system-gdbinit` 指定的位置。GDB 会在命令行选项处理之前加载此文件。
  * `system.gdbinit.d` - 这是系统级别的初始化目录。它由编译时选项 `--with-system-gdbinit-dir` 指定。此处的文件将在 `system.gdbinit` 文件之后、命令行选项之前进行加载，该目录下可能存在多个文件，它们按字母顺序进行加载。文件需要具有公认的脚本语言扩展名（`.py/.scm`）或以 `.gdb` 扩展名（将其视为普通的 GDB 命令）命名。GDB 不会递归的加载该目录下的子目录。
  * `~/.gdbinit` - 用户家目录初始化文件，它在 `system.gdbinit` 之后，命令行选项处理之前加载。
  * `./.gdbinit` - 当前目录的初始化文件。它最后被加载，除了 `-x` 和 `-nx` 命令行选项之外。`-x` 和 `-ex` 是最后被处理的，在 `./.gdbinit` 之后加载。

* `-nh` 不要执行来自用户家目录下的初始化文件（即 `~/.gdbinit`）中的命令。

* `-quite, -silent, -q` 静默模式，不输出介绍信息和版权信息。在批处理模式下也不会输出这些信息。

* `-batch` 批处理模式。在处理完由 `-x` 指定的所有命令文件（如果没有使用 `-n` 选项，也将处理初始化文件中的命令）并退出，正常返回 0，非 0 表示出现错误。批处理模式将会禁止分页功能，即终端的宽度和高度没有限制，类似于 `set confirm off`。

* `-cd directory` 使用 `directory` 作为工作目录，而不是当前目录作为工作目录。

* `-data-directory directory, -D directory` 使用 `directory` 作为 GDB 运行时的数据目录，这个目录包含了 GDB 的辅助文件。

此处只列出了部分选项，更多选项[请看这里](https://sourceware.org/gdb/current/onlinedocs/gdb/Mode-Options.html#Mode-Options)。

### GDB 在启动时都做了什么

下面是有关 GDB 在会话启动过程中执行的操作的说明：

1. 设置命令行指定的命令解释器。
2. 读取系统级别的初始化文件以及系统级别的初始化目录，并执行这些文件中的命令。这些文件以 `.gdb` 结尾（包含 GDB 命令）或者 GDB 支持的脚本语言的后缀结尾。
3. 读取用户级别的初始化文件并执行其中的命令。
4. 执行由 `-iex` 或 `-ix` 选项指定的命令文件或命令，按照指定的顺序执行。
5. 处理命令行选项和操作数。
6. 读取并执行来自当前工作目录下的初始化文件（需要 `set auto-load local-gdbinit` 设置为 `on`）。仅在当前目录不是用户家目录时才会执行。因此，我们可以在调用 GDB 的目录中拥有多个初始化文件，一个初始化文件位于用户家目录中，而另一个文件特定于要调试的程序目录。
7. 如果命令行选项指定了待调试的程序，或者需要附加的进程，或者 core 文件，GDB 会加载为程序或其加载的共享库提供的有自动加载的脚本。
   如果我们想要禁用启动时自动加载脚本，可以按如下方式使用：
   
   ```
   $ gdb -iex "set auto-load python-scripts off" myprogname
   ```

   选项 `-ex` 不会有效，这是因为它加载的时间太晚了，以致于来不及关闭自动加载功能。
8. 按顺序执行来自 `-ex` 和 `-x` 选项指定的命令。
9. 读取历史文件中的历史文件。

初始化文件使用的语法与命令文件相同，并且 GDB 处理的方式也一样。用户家目录的初始化文件设置选项可以影响后续选项的处理。如果使用了 `-nx` 选项，那么将不会执行初始化文件中的命令。

通过 `gdb --help` 可以看到 GDB 启动时加载的初始化文件列表。

## 退出 GDB

我们可以使用 `quit [expression]` 或者 `q [expression]` 退出 GDB。如果没有指定 `expression` 表达式，GDB 将正常终止；否则他将使用表达式 `experssion` 的结果作为错误码。

中断（通常是 `Ctrl-c`）不会退出 GDB，而是终止正在运行的 GDB 命令，并返回到 GDB 的命令行。如果您一直在使用 GDB 来控制连接的进程或设备，则可以使用 `detach` 命令释放它。

## Shell 命令

如果我们想要在调试期间执行 shell 命令，我们没有必要离开或者挂起 GDB；我们可以直接使用 SHELL 命令。

我们可以使用 `shell command-string` 或者 `!command-string` 来执行标准的 shell 命令。需要注意的是在 `!` 和 `command-string` 之间没有空格。如果存在空格，那么将使用环境变量 `SHELL` 来运行 shell 命令。否则，GDB 将使用默认的 shell（Unix 系统为 /bin/sh，Windows 平台为 COMMAND.COM 等）。

编译工具 `make` 总是在开发环境中，因此，在 GDB 中我们不必为 `make` 使用 `shell` 命令。

* `make make-args` -  将以给定的参数执行 `make` 命令，这等同于 `shell make make-args`。
* `pipe [command] | shell_command` 和 `| [command] | shell_command` - 命令执行 `command` 命令并将结果重定向到 `shell_command` 中。
* `pipe -d delim command delim shell_command` 和`| -d delim command delim shell_command` - 与上面的命令相似，不同的是我们可以指定分割符 `delim`。例如：

  ```
  (gdb) p var
  $1 = {
    black = 144,
    red = 233,
    green = 377,
    blue = 610,
    white = 987
  }
  
  (gdb) pipe p var | wc
        7      19      80
  (gdb) | p var | wc -l
  7
  
  (gdb) p /x var
  $4 = {
    black = 0x90,
    red = 0xe9,
    green = 0x179,
    blue = 0x262,
    white = 0x3db
  }
  (gdb) || grep red
    red => 0xe9,
  
  (gdb) | -d ! echo this contains a | char\n ! sed -e 's/|/PIPE/'
  this contains a PIPE char
  (gdb) | -d xxx echo this contains a | char!\n xxx sed -e 's/|/PIPE/'
  this contains a PIPE char!
  (gdb)
  ```

变量 `$_shell_exitcode` 和 `$_shell_exitsignal` 可以方便的检查 `shell`, `make`, `pipe` 和 `|` 最后一个 shell 命令的退出状态。

## 日志输出

我们可能想要将 GDB 的输出保存在文件中，GDB 提供多个命令来控制日志的输出。

* `set logging on` - 启用日志。
* `set logging off` - 禁用日志。
* `set logging file filename` - 改变当前日志文件名。默认为 gdb.txt。
* `set logging overwrite [on|off]` - 默认情况下，GDB 将采用追加的方法写日志文件。我们可以通过设置该参数来改变其行为。
* `set logging redirect [on|off]` - 默认情况下，GDB 会同时输出到终端和日志文件中，如果设置 `redirect`，那么只会输出到日志文件。如果是使用多个 TUI 模式，在 GDB 的命令窗口没有输出，也就无法输出到日志文件中。
* `set logging debugredirect [on|off]` - 默认情况下，GDB 的调试输出同时输出到终端和日志文件中，如果设置了 `debugredirect`，那么就只会输出到日志文件中。GDB 8.1 没有这个命令。
* `show logging` - 显示当前日志配置。

## 参考

[1] https://sourceware.org/gdb/current/onlinedocs/gdb