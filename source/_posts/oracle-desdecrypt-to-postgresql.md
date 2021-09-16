---
title: "Oracle 迁移 PostgreSQL - DESDecrypt 函数"
date: 2021-06-08 18:01:24 +0800
category: 数据库
tags:
  - Oracle
  - PostgreSQL
  - 迁移
---

最近在工作中遇到了 Oracle DES 加解密迁移到 PostgreSQL 中的问题，本文简要记录一下这个问题的解决过程。

<!-- more -->

## 问题

在客户环境中，被加密的内容来自于一个数据中心，而在迁移的数据库中有一个名为 `fn_decrypt_base64()` 的函数对其进行解密。函数定义如下：

```sql
CREATE OR REPLACE FUNCTION fn_decrypt_base64(input_str  IN VARCHAR2,
                                             encode_key IN VARCHAR2)
RETURN VARCHAR2
IS
  output_string    varchar2(4000);
  encrypted_string varchar2(256);
BEGIN

  SELECT utl_raw.cast_to_varchar2(utl_encode.base64_decode(utl_raw.cast_to_raw(input_str)))
    INTO encrypted_string
    FROM dual;

  -- dbms_output.put_line(utl_raw.cast_to_raw(encrypted_string));
  dbms_obfuscation_toolkit.DESDecrypt(input_string     => encrypted_string,
                                      key_string       => encode_key,
                                      decrypted_string => output_string);
  RETURN output_string;
END;
```

其执行结果如下所示：

```sql
$ SELECT fn_decrypt_base64('0MgFN1KCaNetLz2kCGfssLFrGCC2Hpaw', 'identitynumber_com.ffcs.mss@123') AS plaintext FROM dual;
     PLAINTEXT
--------------------
 340104198809053015
(1 row)
```

既然是加解密，那么迁移到 PostgreSQL 中来很自然的就想到了 [pgcrypto]() 扩展。然而并没有那么简单。

下面是我迁移到 PostgreSQL 中对 `fn_decrypt_base64()` 函数的实现。

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE OR REPLACE FUNCTION fn_decrypt_base64(input_str text,
                                             encode_key bytea)
RETURNS varchar
AS $body$
DECLARE
  output_string varchar(4000);

BEGIN
  SELECT decrypt(decode(input_str, 'base64'), encode_key, 'des')
  INTO output_string;

  RETURN output_string;
END;
$body$ LANGUAGE 'plpgsql' VOLATILE;
```

其执行结果如下所示：

```sql
$ SELECT fn_decrypt_base64('0MgFN1KCaNetLz2kCGfssLFrGCC2Hpaw', 'identitynumber_com.ffcs.mss@123') AS plaintext;
                     plaintext
----------------------------------------------------
 \x333430313034313938383039303533303135000000000000
(1 row)
```

这并不是我们想要的结果，但是已经非常接近了，可以看到其二进制格式实际上就是我们解密后的原文，但是后面附加了一些内容，当我们尝试将其转换为可读的字符串时，会遇到如下错误。

```sql
$ SELECT convert_from(fn_decrypt_base64('0MgFN1KCaNetLz2kCGfssLFrGCC2Hpaw', 'identitynumber_com.ffcs.mss@123')::bytea, 'SQL_ASCII') AS plaintext;
ERROR:  invalid byte sequence for encoding "SQL_ASCII": 0x00
```

在 Oracle 的 `fn_decrypt_base64` 中加入 `dbms_output.put_line(utl_raw.cast_to_raw(encrypted_string));` 语句，可以看到两个数据库中解密后的数据的区别，如下所示。

```
Oracle      D0C80537528268D7AD2F3DA40867ECB0B16B1820B61E96B0
plain text   3 4 0 1 0 4 1 9 8 8 0 9 0 5 3 0 1 5
PostgreSQL  333430313034313938383039303533303135000000000000
```

其长度都是一致的，但是在 Oracle 中，我看不出有什么规律，而在 PostgreSQL 中，可以发现非零部分就是我们解密后的明文的二进制形式。在 PostgreSQL 中，我们可以使用如下语句来达到与 Oracle 中类似的效果。

```sql
$ SELECT convert_from(trim(fn_decrypt_base64('0MgFN1KCaNetLz2kCGfssLFrGCC2Hpaw', 'identitynumber_com.ffcs.mss@123')::bytea, '\x00'), 'SQL_ASCII') AS plaintext;
     plaintext
--------------------
 340104198809053015
(1 row)
```

这只是 Oracle 中 `DESDecrypt` 迁移到 PostgreSQL 数据库中的一种临时解决方案，至于为什么 Oracle 和 PostgreSQL 中解密后的明文二进制表现不同，或许这个 Oracle 中 varchar2 类型的存储格式有关。

我们可以对 `fn_decrypt_base64` 函数进行封装，使其表现得更像 Oracle 一点。

```sql
CREATE OR REPLACE FUNCTION fn_decrypt_base64(input_str text,
                                             encode_key bytea)
RETURNS varchar
AS $body$
DECLARE
  output_string varchar(4000);

BEGIN
  SELECT convert_from(trim(decrypt(decode(input_str, 'base64'), encode_key, 'des'), '\x00'), 'SQL_ASCII')
  INTO output_string;

  RETURN output_string;
END;
$body$ LANGUAGE 'plpgsql' VOLATILE;
```

其结果如下所示：

```sql
$ SELECT fn_decrypt_base64('0MgFN1KCaNetLz2kCGfssLFrGCC2Hpaw', 'identitynumber_com.ffcs.mss@123') AS plaintext;
     plaintext
--------------------
 340104198809053015
(1 row)
```

## 参考

[1] https://www.postgresql.org/docs/12/pgcrypto.html
[2] https://asktom.oracle.com/pls/apex/f?p=100:11:0::::P11_QUESTION_ID:13889233036637

[pgcrypto]: https://www.postgresql.org/docs/12/pgcrypto.html

<div class="just-for-fun">
笑林广记 - 仙女凡身

董永行孝，上帝命一仙女嫁之。
众仙女送行，皆嘱咐曰：“去下方，若更有行孝者，千万寄个信来。”
</div>
