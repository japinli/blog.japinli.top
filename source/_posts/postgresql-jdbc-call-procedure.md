---
title: "PostgreSQL 使用 JDBC 调用存储过程错误"
date: 2021-11-25 22:41:44 +0800
categories: 编程
tags:
  - PostgreSQL
  - Java
  - JDBC
---

最近在迁移 Oracle 数据库到 PostgreSQL 时遇到了 PostgreSQL 中调用存储过程异常的情况。本文简要记录以下定位及其修复过程。

<!--more-->

## 问题

在将 Oracle 中的存储过程迁移到 PostgreSQL 中，我们遇到了一个如下的存储过程（经过了简化）：

```sql
CREATE OR REPLACE PROCEDURE proc(a INOUT bigint)
AS $$
BEGIN
    INSERT INTO tbl VALUES(a);
    COMMIT;
END;
$$ LANGUAGE plpgsql;
```

随后在 Java 程序中使用 JDBC 去调用这个存储过程，调用代码如下所示：

```Java
    CallableStatement proc = conn.prepareCall("{call proc( ? )}");
```

运行时程序报如下错误：

```
org.postgresql.util.PSQLException: ERROR: proc(integer) is a procedure
  Hint: To call a procedure, use CALL.
  Position: 15
        at org.postgresql.core.v3.QueryExecutorImpl.receiveErrorResponse(QueryExecutorImpl.java:2674)
        at org.postgresql.core.v3.QueryExecutorImpl.processResults(QueryExecutorImpl.java:2364)
        at org.postgresql.core.v3.QueryExecutorImpl.execute(QueryExecutorImpl.java:354)
        at org.postgresql.jdbc.PgStatement.executeInternal(PgStatement.java:484)
        at org.postgresql.jdbc.PgStatement.execute(PgStatement.java:404)
        at org.postgresql.jdbc.PgPreparedStatement.executeWithFlags(PgPreparedStatement.java:162)
        at org.postgresql.jdbc.PgCallableStatement.executeWithFlags(PgCallableStatement.java:83)
        at org.postgresql.jdbc.PgPreparedStatement.execute(PgPreparedStatement.java:151)
        at PGTest.main(PGTest.java:52)
org.postgresql.util.PSQLException: ERROR: proc(integer) is a procedure
  Hint: To call a procedure, use CALL.
  Position: 15
```

错误提示我们调用的是一个存储过程，应该使用 `CALL` 来调用存储过程？WTF? 难道我在程序里使用的不是 `CALL` 么？真的是老眼昏花了吗？

经过一番尝试之后发现还是不能解决这个问题，当时由于敢进度，就选择了曲线救国的思路，将存储过程改为函数，折腾了一番之后总算是可以用了。

## 分析

晚上回来继续研究，这次选择了查看[官方文档](https://jdbc.postgresql.org/documentation/head/callproc.html)，浏览了一下发现 PostgreSQL 的 JDBC 在处理存储过程没有返回值的时候需要设置 `escapeSyntaxCallMode` 参数。如下所示：

```Java
    // Ensure EscapeSyntaxCallmode property set to support procedures if no return value
    props.setProperty("escapeSyntaxCallMode", "callIfNoReturn");
```

根据注释来看，设置 `escapeSyntaxCallMode` 为 `callIfNoReturn` 可以确保存储过程在没有返回值的时候依然正常工作，经验证，通过这个设置，存储过程便能正确执行了。

这个问题虽然不大，但是对于不懂 Java 的我来说定位还是比较费事的，不过还好 PostgreSQL 的 jdbc 文档比较完善，虽然走了一些弯路，从这个也能看出，官方文档才是第一手资料，其他的都是浮云啊。

此外，[这里](https://jdbc.postgresql.org/documentation/head/connect.html) 包含了 PostgreSQL 数据库 jdbc 连接的所有参数信息。拿上面的 `escapeSyntaxCallMode` 来说，您可以看到如下内容：

> * escapeSyntaxCallMode = String
>
>   Specifies how the driver transforms JDBC escape call syntax into underlying SQL, for invoking procedures or functions. In escapeSyntaxCallMode=select mode (the default), the driver always uses a SELECT statement (allowing function invocation only). In escapeSyntaxCallMode=callIfNoReturn mode, the driver uses a CALL statement (allowing procedure invocation) if there is no return parameter specified, otherwise the driver uses a SELECT statement. In escapeSyntaxCallMode=call mode, the driver always uses a CALL statement (allowing procedure invocation only).
>
>   The default is select

从上面的说明可以看到，`escapeSyntaxCallMode` 参数制定了如何调用底层的函数和存储过程，它有三种模式：

* **select** - 默认值，jdbc 驱动使用 `SELECT` 来调用函数和存储过程。
* **callIfNoReturn** - 当存储过程没有返回值时使用 `CALL` 来调用，其他情况则使用 `SELECT` 来调用。
* **call** - 所有的函数和存储过程都使用 `CALL` 来调用。

## 参考

[1] https://jdbc.postgresql.org/documentation/head/callproc.html
[2] https://jdbc.postgresql.org/documentation/head/connect.html


<div class="just-for-fun">
笑林广记 - 进士第

一介弟横行于乡，怨家骂曰：“兄登黄甲，与汝何干，而豪横若此？”
答曰：“尔不见匾额上面写着‘进士第（弟）’么？”
</div>
