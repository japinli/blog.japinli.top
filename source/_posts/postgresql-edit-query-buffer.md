---
title: "PostgreSQL 编辑查询缓冲区"
date: 2020-05-19 22:28:59 +0800
category: 数据库
tags:
  - PostgreSQL
---

我们经常需要在 psql 中修改查询语句，例如，我们编辑了几行查询语句，然后需要修改之前的内容，我之前额做法就是 Ctrl-C 然后在重新输入。其实，我们可以不必这么复杂。我们可以使用 `\e` 命令来编辑查询缓冲区。如下所示：

```
postgres=# SELECT * FROM
postgres-# pg_calss
postgres-# WHERE relname = 'pg_class'
postgres-#
```

此时，我们发现 `pg_calss` 拼写错了，那么我们可以通过 `\e` 对其进行修改。如下所示：

```
postgres-# WHERE relname = 'pg_class'
postgres-# \e
  1 SELECT * FROM
  2 pg_class
  3 WHERE relname = 'pg_class'
```

`\e` 命令将会创建一个临时文件，然后我们便可以通过编辑文件的方式对其进行修改了，当保存之后，psql 将会把文件内容存放到查询缓冲区中。

`\e [ filename ] [ line_number ]` 命令还可以接文件和行号，文件指定了我们想要编辑的文件，行号则表明文件打开时光标所处的位置。注意，如果仅跟一个数字，该命令将其视为行号，例如 `\e 3` 表示编辑查询缓冲区，并将光标移动到第三行。
