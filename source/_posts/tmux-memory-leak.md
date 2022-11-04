---
title: "Tmux 内存泄露"
date: 2022-10-31 22:55:53 +0800
categories: 杂项
tags:
  - tmux
---

内存泄露又来啦！这次的主角是 tmux。我在升级 tmux 到 3.4 之后，并在 tmux 绘画中使用 fzf 时，出现了如下内存泄露。

```
=================================================================
==367944==ERROR: LeakSanitizer: detected memory leaks

Direct leak of 2 byte(s) in 1 object(s) allocated from:
    #0 0x4855e4 in strdup (/usr/local/bin/tmux+0x4855e4)
    #1 0x84d104 in xstrdup /home/japin/Codes/tmux/xmalloc.c:93:12
    #2 0x5170d8 in cmd_parse_from_arguments /home/japin/Codes/tmux/cmd-parse.y:1075:11
    #3 0x4e10df in client_main /home/japin/Codes/tmux/client.c:267:8
    #4 0x768190 in main /home/japin/Codes/tmux/tmux.c:519:7
    #5 0x7fe9db1fe082 in __libc_start_main /build/glibc-SzIz7B/glibc-2.31/csu/../csu/libc-start.c:308:16

SUMMARY: AddressSanitizer: 2 byte(s) leaked in 1 allocation(s).
```

<!--more-->

## 重现

我使用的是提交号为 [5ce34add][] 的 Tmux 编译安装。下面基本环境信息。

```bash
$ uname -sp && tmux -V && echo $TERM
Linux x86_64
tmux next-3.4
xterm-256color

$ fzf --version
0.34.0 (04d0b02)

$ tmux -Ltest -f/dev/null new
```

接着，我们在 tmux 会话中执行 `fzf-tmux` 就出现了本文一开始的内存泄露问题。从错误日志可以看到问题出在 tmux 的 `cmd_parse_from_arguments()` 函数中。

```c
struct cmd_parse_result *
cmd_parse_from_arguments(struct args_value *values, u_int count,
    struct cmd_parse_input *pi)
{
    [...]

    for (i = 0; i < count; i++) {
        end = 0;
        if (values[i].type == ARGS_STRING) {
            copy = xstrdup(values[i].string);
            size = strlen(copy);
            if (size != 0 && copy[size - 1] == ';') {
                copy[--size] = '\0';
                if (size > 0 && copy[size - 1] == '\\')
                    copy[size - 1] = ';';
                else
                    end = 1;
            }
            if (!end || size != 0) {
                arg = xcalloc(1, sizeof *arg);
                arg->type = CMD_PARSE_STRING;
                arg->string = copy;
                TAILQ_INSERT_TAIL(&cmd->arguments, arg, entry); /* 添加到 cmd->arguments 中 */
            }
            /*
             * 如果进入到这里，那么 copy 的内存就泄露了，而当我执行 fzf-tmux 时，
             * 正好进入到这里，从而导致内存泄露。
             */
        }

        [...]
    }

    cmd_parse_free_commands(cmds); /* 此处释放内存 */
    [...]
}
```

## 修复

通过上面的分析，我们可以在条件 `!end || size != 0` 之后加上一个分支用于释放 `copy` 的内存，如下所示：

```diff
diff --git a/cmd-parse.y b/cmd-parse.y
index 1d69277083..cdf026f3de 100644
--- a/cmd-parse.y
+++ b/cmd-parse.y
@@ -1086,7 +1086,8 @@ cmd_parse_from_arguments(struct args_value *values, u_int count,
 				arg->type = CMD_PARSE_STRING;
 				arg->string = copy;
 				TAILQ_INSERT_TAIL(&cmd->arguments, arg, entry);
-			}
+			} else
+				free(copy);
 		} else if (values[i].type == ARGS_COMMANDS) {
 			arg = xcalloc(1, sizeof *arg);
 			arg->type = CMD_PARSE_PARSED_COMMANDS;
```

## 链接

[1] https://github.com/tmux/tmux/pull/3358
[2] https://github.com/tmux/tmux/commit/2111142cf1715eeac174cd5c71ed90f00595b17e

<div class="just-for-fun">
笑林广记 - 抛锚

道士、和尚、胡子三人过江。忽遇狂风大作，舟将颠覆，僧道慌甚，急把经卷投入江中，求神救护。
而胡子无可掷得，惟将胡须逐根拔下，投于江内。
僧道问曰：“你拔胡须何用？”
其人曰：“我在此抛毛（锚）。”
</div>


[5ce34add]: https://github.com/tmux/tmux/commit/5ce34add77fa3517a01e63b915c5f4e3241af470
