---
title: "PostgreSQL 更新 configure 引入无关更改"
date: 2021-02-21 09:07:21 +0800
category: 数据库
tags:
  - PostgreSQL
---

PostgreSQL 使用 autoconf 工具来自动配置软件源代码包。我在修改了 configure.ac 文件之后执行 autoreconf 发现它将引入其他无关的更改，如下所示：

```diff
@@ -1187,6 +1189,15 @@ do
   | -silent | --silent | --silen | --sile | --sil)
     silent=yes ;;

+  -runstatedir | --runstatedir | --runstatedi | --runstated \
+  | --runstate | --runstat | --runsta | --runst | --runs \
+  | --run | --ru | --r)
+    ac_prev=runstatedir ;;
+  -runstatedir=* | --runstatedir=* | --runstatedi=* | --runstated=* \
+  | --runstate=* | --runstat=* | --runsta=* | --runst=* | --runs=* \
+  | --run=* | --ru=* | --r=*)
+    runstatedir=$ac_optarg ;;
+

...

@@ -14714,7 +14738,7 @@ else
     We can't simply define LARGE_OFF_T to be 9223372036854775807,
     since some C++ compilers masquerading as C compilers
     incorrectly reject 9223372036854775807.  */
-#define LARGE_OFF_T (((off_t) 1 << 62) - 1 + ((off_t) 1 << 62))
+#define LARGE_OFF_T ((((off_t) 1 << 31) << 31) - 1 + (((off_t) 1 << 31) << 31))
   int off_t_is_large[(LARGE_OFF_T % 2147483629 == 721
               && LARGE_OFF_T % 2147483647 == 1)
              ? 1 : -1];

...

```

这是由于供应商的软件包经常包含一些改进导致的，这就导致了我们生成的 configure 文件与其他提交者的有不同的结果。

<!-- more -->

## 解决方案

我们可以从 autoconf 的[官网下载](https://www.gnu.org/software/autoconf/#downloading)并重新安装。

``` shell
$ wget https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
$ tar xf autoconf-2.69.tar.gz
$ cd autoconf-2.69
$ ./configure --prefix=/usr/local/autoconf-2.69
$ make
$ sudo make install
```

最后将 `/usr/local/autoconf-2.69/bin` 加入到 `PATH` 环境变量的开始（确保我们安装的 autoconf 先于系统的即可）并重新载入环境变量。随后执行 `autoreconf` 命令更新 `configure` 文件，这时就不会引入其他无关的更改。

## 参考

[1] https://www.postgresql.org/message-id/flat/20181229140802.GE2972%40paquier.xyz
