---
title: "PostgreSQL 安全性配置概要"
date: 2021-05-20 14:47:46 +0800
category: 数据库
tags:
  - PostgreSQL
---

本文从网络、数据库实例、数据库、schema 和表对象几个层面对 PostgreSQL 数据库的安全性配置进行了简要的回顾。

{% asset_img pg_security.png %}

<!-- more -->

## 网络安全性

### 监听地址

- unix socket
  通常 unix socket 方式要比 localhost 的性能要好。
- TCP/IP
  `listen_addresses`和 `port` 两个参数。
  `listen_addresses` 可以有多个 IP 地址，使用逗号分割。
	- localhost
	- ip address

### pg_hba

pg_hba 用于告知 PostgreSQL 如何认证用户的连接。格式如下：

```
local      DATABASE USER         METHOD [OPTIONS]
host       DATABASE USER ADDRESS METHOD [OPTIONS]
hostssl    DATABASE USER ADDRESS METHOD [OPTIONS]
hostnossl  DATABASE USER ADDRESS METHOD [OPTIONS]
```

第一条规则匹配后续，后续规则将不予判断。

- rules
  | 方法      | 说明                                                                                                             |
  |-----------|------------------------------------------------------------------------------------------------------------------|
  | local     | 用来配置本地 unix 套接字。                                                                                       |
  | host      | 用于配置 SSL 和非 SSL 连接。                                                                                     |
  | hostssl   | 仅用于配置 SSL 连接。必须编译有 SSL，并且 `ssl = on`，此外还需要配置以下参数 `ssl_cert_file` 和 `ssl_key_file`。 |
  | hostnossl | 配置非 SSL 连接。                                                                                                |

- methods
  | 方法         | 说明                                                                                                |
  |--------------|-----------------------------------------------------------------------------------------------------|
  | trust        | 允许不提供密码的认证，PostgreSQL 数据库中需要有对应的用户。                                         |
  | reject       | 拒绝连接。                                                                                          |
  | md5/password | 通过口令进行连接。md5 意味着口令在传输时被加密；password 以明文的形式发送（不建议这种方案）。       |
  | GSS/SSPI     | GSSAPI 或 SSPI 认证，针对 TCP/IP 连接。                                                             |
  | ident        | 通过联系客户端上的 Ident 服务器获得客户端的操作系统用户名，并且检查它是否匹配被请求的数据库用户名。 |
  | peer         | 只对本地连接有用。                                                                                  |
  | pam          | 使用可插拔认证模块（PAM），对于使用非 PostgreSQL 自带的认证方式非常有用。                           |
  | ldap         | 使用轻量级目录访问协议（LDAP）进行认证。                                                            |
  | radius       | 远程认证拨入用户服务（RADIUS）。                                                                    |
  | cert         | 使用 SSL 客户端证书来执行认证，只用使用 SSL 才能使用它。                                            |

  __备注：__
  1. SSPI (Security Support Provider Interface) 是微软 Windows 操作系统中用于执行各种安全相关操作（如身份认证）的一个 Win32 API。
  2. RADIUS 是一种用于在需要认证其链接的网络访问服务器（NAS）和共享认证服务器之间进行认证、授权和记帐信息的文档协议。RADIUS 服务器负责接收用户的连接请求、认证用户，然后返回客户机所有必要的配置信息以将服务发送到用户。

## 实例级安全

### CREATE USER/ROLE

`CREATE USER` 和 `CREATE ROLE` 的区别仅仅是 `CREATE USER` 默认具有 `LOGIN` 权限，而 `CREATE ROLE` 默认为 `NOLOGIN` 权限，即通过 `CREATE ROLE` 创建的用户如果没有指定 `LOGIN`，那么是无法用于登录数据库的。

| 选项                           | 说明                                                                                |
|--------------------------------|-------------------------------------------------------------------------------------|
| SUPERUSER/NOSUPERUSER          | 是否为超级用户。                                                                    |
| CREATEDB/NOCREATEDB            | 是否可以创建数据库。                                                                |
| CREATEROLE/NOCREATEROLE        | 是否可以创建角色/用户。                                                             |
| INHERIT/NOINHERIT              | 是否可以被继承。                                                                    |
| LOGIN/NOLOGIN                  | 是否可以登录数据库。                                                                |
| REPLICATION/NOREPLICATION      | 是否用于流复制。                                                                    |
| BYPASSRLS/NOBYPASSRLS          | 是否可以绕过行级安全策略。                                                          |
| CONNECTIOIN LIMIT              | 用户最大连接数量。在设置 CONNECTIONS LIMIT 时，可以指定其值大于 `max_connections`。 |
| ENCRYPTED/UNENCRYPTED PASSWORD | 是否加密密码。UNENCRYPTED PASSWORD 在测试的时候可能很有用。                         |
| VALID UNTIL                    | 设置用户有效期。                                                                    |

### ALTER USER/ROLE

- OPTIONS
  修改 `CREATE USER/ROLE` 时指定的选项。
- PARAMETERS
  设置参数。
  ```sql
  ALTE ROLE { role_specification | ALL }
    [ IN DATABASE database_name ]
    SET configuration_parameter { TO | = } { value | DEFAULT }

  ALTER ROLE { role_specification | ALL }
    [ IN DATABASE database_name ]
    SET configuration_parameter FROM CURRENT

  ALTER ROLE { role_specification | ALL }
    [ IN DATABASE database_name ]
    RESET configuration_parameter

  ALTER ROLE { role_specification | ALL }
    [ IN DATABASE database_name ] RESET ALL
  ```

## 数据库级安全

### CREATE

允许用户在数据库中创建 `schema`，注意，授权了数据库的 `CREATE `权限仅仅表示用户可以在数据库中创建 `schema`，而其他对象则不能创建，例如，表、视图、函数等。

### CONNECT

允许某个用户连接到数据库。

### 默认权限

如果没有指定，那么默认的权限来自 `public`。注意 `public` 不是一个角色。
通常建议在其他数据库创建之前就从 postgres 数据库中收回权限是。

```sql
REVOCK ALL ON DATABASE dbname FROM public;
```

## Schema 级安全

默认情况下，`public` 被允许使用 `public` 模式。

当我们在数据库上只有 `CONNECT` 权限时，我们可以在 `public` 模式下建表。

### 权限

| 权限   | 说明                                                         |
| ------ | ------------------------------------------------------------ |
| CREATE | 用户可以在该模式下创建对象，对对象进行修改。例如，ALTER TABLE。 |
| USAGE  | 用户可以进入该模式，但是能否使用该模式下的对象，还有下层的权限进行控制，例如对表的增、删、查、改等。 |

### 语法

```sql
GRANT { { SELECT | UPDATE } [, ...] | ALL [ PRIVILEGES ] }
    ON LARGE OBJECT loid [, ...]
    TO role_specification [, ...] [ WITH GRANT OPTION ]
    [ GRANTED BY role_specification ]
```

## 表级安全

### 表权限

| 权限       | 说明                                                                                                                  |
|------------|-----------------------------------------------------------------------------------------------------------------------|
| SELECT     | 允许用户读取表的内容。                                                                                                |
| INSERT     | 允许用户向表中插入数据，注意如果是带有 RETURNING 子句的还需要 SELECT 权限。                                           |
| UPDATE     | 允许用户对表进行更新。                                                                                                |
| DELETE     | 允许用户删除表中的行记录。                                                                                            |
| TRUNCATE   | 允许用户对表执行 TRUNCATE 命令。TRUNCATE 和 DELETE 是两种独立的权限，这是因为 TRUNCATE 会锁表，而 DELETE 语句则不会。 |
| REFERENCES | 允许用户创建外键，必须在引用和被引用列上都有这一特权，否则无法创建。                                                  |
| TRIGGER    | 允许用户在该表上创建触发器。                                                                                          |

### 列级安全

限制用户对不同列的访问。显示授权：

```sql
GRANT SELECT (id) ON t_useful TO paul;
```

## 行级安全策略

限制不同用户对不同数据行的查看权限。

### 启用/禁用

默认情况下，表的所有者不受行级安全策略的限制，我们可以通过 `FORCE ROW LEVEL SECURITY` 来明确表明所有者也需要验证行级安全策略。相关命令如下：

```sql
ALTER TABLE table_name ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_name DISABLE ROW LEVEL SECURITY;

ALTER TABLE table_name FORCE ROW LEVEL SECURITY;
ALTER TABLE table_name NO FORCE ROW LEVEL SECURITY;
```

__注意：__ 超级用户始终不受行级安全策略限制。

### 策略

多个策略之间使用 `OR` 进行连接。

- 创建
  ```sql
  CREATE POLICY name ON table_name
      [ AS { PERMISSIVE | RESTRICTIVE } ]
      [ FOR { ALL | SELECT | INSERT | UPDATE | DELETE } ]
      [ TO { role_name | PUBLIC | CURRENT_ROLE | CURRENT_USER | SESSION_USER } [, ...] ]
      [ USING ( using_expression ) ]
      [ WITH CHECK ( check_expression ) ]
  ```
  - USING
    过滤已经存在的行记录，与 `SELECT` 和 `UPDATE` 子句相关。
  - CHECK
    过滤将要被创建的新行，与 `INSERT` 和 `UPDATE` 子句相关。
- 删除
  ```sql
  DROP POLICY [ IF EXISTS ] name ON table_name [ CASCADE | RESTRICT ]
  ```
- 修改
  ```sql
  ALTER POLICY name ON table_name RENAME TO new_name

  ALTER POLICY name ON table_name
      [ TO { role_name | PUBLIC | CURRENT_ROLE | CURRENT_USER | SESSION_USER } [, ...] ]
      [ USING ( using_expression ) ]
      [ WITH CHECK ( check_expression ) ]
  ```

## 检查权限

主要是针对数据库对象。PostgreSQL 目前还没有提供很好的权限查询功能。

### psql

在 psql 中我们可以通过 `\z` 命令来查看表、视图和序列的权限，同 `\dp `命令。

### aclexplode

通过 aclexplode() 函数来查看，例如：

```sql
SELECT * FROM aclexplode('{joe=arwdDxt/postgres}');
```

| 标识 | 说明                     |
|------|--------------------------|
| a    | 追加，用于 INSERT 子句。 |
| r    | 读取，用于 SELECT 子句。 |
| w    | 写入，用于 UPDATE 子句。 |
| d    | 删除，用于 DELETE 子句。 |
| D    | 用于 TRUNCATE 子句。     |
| x    | 用于引用。               |
| t    | 用于触发器。             |

## 参考

[1] 《由浅入深PostgreSQL》
