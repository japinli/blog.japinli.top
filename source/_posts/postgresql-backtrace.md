---
title: "PostgreSQL 13 - backtrace 功能预览"
date: 2020-08-15 20:30:43 +0800
category: 数据库
tags:
  - PostgreSQL
---

目前在 Greenplum、MySQL 数据库中均支持 backtrace 功能，现在 PostgreSQL 13-devel 版本中也新增了这个功能，我们可以在服务器日志中记录堆栈信息。

{% asset_img backtrace.png Backtrace 提交记录 %}

本文将对该功能进行简要介绍。

<!-- more -->

## 简介

PostgreSQL 13 数据库提供了一个参数 `backtrace_functions` 来控制堆栈信息的生成，该参数是包含C函数名称的逗号分隔列表。如果出现错误，并且该错误是由 `backtrace_functions` 中的 C 函数引发的，那么将会把堆栈信息记录到服务器日志文件中。这个选项可以方便我们调试特定区域的源代码。

目前并非所有平台都支持 backtrace 功能，并且其堆栈信息的质量也取决于编译选项。

```
SET backtrace_functions TO 'ProcessUtility,ExecutorStart';
```

该参数仅超级用户可以设置，它可以在 postgresql.conf 中进行全局设置，也可以针对某个会话进行设置。

## 使用

在这里我们通过创建一个不存在的类型来演示如何使用 backtrace 功能。

```
postgres=# CREATE TABLE foo(id invalidtype);
ERROR:  type "invalidtype" does not exist
LINE 1: CREATE TABLE foo(id invalidtype);
                            ^
```

从上面可以看到，我们输入的数据类型不存在，下面是服务器端的日志信息。总的来说信息是很有限的，我们无法得知更多的细节。

```
2020-08-15 18:03:35.857 CST [1666] ERROR:  type "invalidtype" does not exist at character 21
2020-08-15 18:03:35.857 CST [1666] STATEMENT:  CREATE TABLE foo(id invalidtype);
```

现在我们来试试 backtrace 大法。首先我们可以通过搜索源码的方法确定当前错误是来自那个内部的 C 函数。这里我们确定它是由 `typenameType()` 函数抱出来的。那么我们可以按如下方式进行操作。

```
postgres=# SET backtrace_functions TO 'typenameType';
SET
postgres=# CREATE TABLE foo(id invalidtype);
ERROR:  type "invalidtype" does not exist
LINE 1: CREATE TABLE foo(id invalidtype);
                            ^
```

虽然在用户看来并没有什么区别，但是服务器日志里面多出了一下内容：

```
2020-08-15 18:09:25.079 CST [1666] ERROR:  type "invalidtype" does not exist at character 21
2020-08-15 18:09:25.079 CST [1666] BACKTRACE:
        postgres: japin postgres [local] CREATE TABLE(typenameType+0xb9) [0x563456c5f509]
        postgres: japin postgres [local] CREATE TABLE(+0x1dcbbc) [0x563456c60bbc]
        postgres: japin postgres [local] CREATE TABLE(transformCreateStmt+0x4da) [0x563456c6412a]
        postgres: japin postgres [local] CREATE TABLE(+0x3d88c8) [0x563456e5c8c8]
        postgres: japin postgres [local] CREATE TABLE(standard_ProcessUtility+0x230) [0x563456e5b7e0]
        postgres: japin postgres [local] CREATE TABLE(+0x3d5012) [0x563456e59012]
        postgres: japin postgres [local] CREATE TABLE(+0x3d5a93) [0x563456e59a93]
        postgres: japin postgres [local] CREATE TABLE(PortalRun+0x161) [0x563456e5a611]
        postgres: japin postgres [local] CREATE TABLE(+0x3d2017) [0x563456e56017]
        postgres: japin postgres [local] CREATE TABLE(PostgresMain+0x1ede) [0x563456e5842e]
        postgres: japin postgres [local] CREATE TABLE(+0x355cda) [0x563456dd9cda]
        postgres: japin postgres [local] CREATE TABLE(PostmasterMain+0xeff) [0x563456ddadef]
        postgres: japin postgres [local] CREATE TABLE(main+0x4a4) [0x563456b45e94]
        /lib/x86_64-linux-gnu/libc.so.6(__libc_start_main+0xe7) [0x7f5502994b97]
        postgres: japin postgres [local] CREATE TABLE(_start+0x2a) [0x563456b45f5a]
2020-08-15 18:09:25.079 CST [1666] STATEMENT:  CREATE TABLE foo(id invalidtype);
```

从上面的 backtrace 可以看到整个流程是如何一步一步走到 `typenameType()` 函数的。Backtrace 的每一行都包含函数的名称，函数内的偏移位置，以及栈帧的返回地址。在某些栈帧上，函数名称并没有出现，取而代之的是一个地址，这些函数是静态函数，它们的名字不会被导出，不过我们也可能通过它们的地址来获取其对应的函数名称。例如，`typenameType()` 函数的上层函数只是一个地址，我们并不知道其对应的函数是什么，这时我们可以使用下面的命令来进行转换：

``` shell
$ addr2line 0x1dcbbc -a -f -e `which postgres`
0x00000000001dcbbc
transformColumnDefinition
parse_utilcmd.c:?
```

可以看到 `0x1dcbbc` 这个地址对应的是 `transformColumnDefinition()` 函数，它位于 `parse_utilcmd.c` 文件中。由于这里是采用的 `-O2` 优化，没能查看到更多的信息，如果我们使用 `-O0`，那么其查询的信息将更为丰富，如下所示：

``` shell
$ addr2line +0x2525e6 -a -f -e `which postgres`
0x00000000002525e6
transformColumnDefinition
/home/japin/Codes/postgresql/Debug/../src/backend/parser/parse_utilcmd.c:568
```

上面两次查看的地址不一致是因为重新编译生成的文件不同导致的。

## 实现

现在我们对于 backtrace 的功能有了基本的了解，接下来我们来看看它是如何实现的。

该功能是通过 `backtrace()` 和 `backtrace_symbols()` 这两个简单的函数来生成堆栈信息，`backtrace()` 函数仅返回所有栈帧的返回地址，接着调用 `backtrace_symbols()` 函数来将这些地址转换为描述这个函数的字符串，PostgreSQL backtrace功能的其核心代码主要集中在 `set_backtrace()` 函数中，如下所示：

``` c
/*
 * Compute backtrace data and add it to the supplied ErrorData.  num_skip
 * specifies how many inner frames to skip.  Use this to avoid showing the
 * internal backtrace support functions in the backtrace.  This requires that
 * this and related functions are not inlined.
 */
static void
set_backtrace(ErrorData *edata, int num_skip)
{
	StringInfoData errtrace;

	initStringInfo(&errtrace);

#ifdef HAVE_BACKTRACE_SYMBOLS
	{
		void	   *buf[100];
		int			nframes;
		char	  **strfrms;

		nframes = backtrace(buf, lengthof(buf));
		strfrms = backtrace_symbols(buf, nframes);
		if (strfrms == NULL)
			return;

		for (int i = num_skip; i < nframes; i++)
			appendStringInfo(&errtrace, "\n%s", strfrms[i]);
		free(strfrms);
	}
#else
	appendStringInfoString(&errtrace,
						   "backtrace generation is not supported by this installation");
#endif

	edata->backtrace = errtrace.data;
}
```

`set_backtrace()` 函数通过 `backtrace()` 和 `backtrace_symbols()` 函数来获取堆栈信息，并将其添加到 `edata->backtrace` 字段中（方便后续处理），`num_skip` 参数指定了需要跳过的内部栈的数量，这是由于我们报错的地方实际上并不是 `set_backtrace()` 函数位置，而是在调用该函数的位置（可能是一层或多层），因此，我们需要定位到真实报错的地方，从这个地方开始输出堆栈信息。

## 参考

[1] https://amitdkhan-pg.blogspot.com/2020/07/backtraces-in-postgresql.html
[2] https://www.postgresql.org/docs/devel/runtime-config-developer.html
[3] https://github.com/postgres/postgres/commit/71a8a4f6e36547bb060dbcc961ea9b57420f7190
