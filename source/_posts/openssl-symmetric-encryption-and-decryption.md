---
title: "Qt 与 sqlite 中 OpenSSL 对称加解密算法无法互相读取"
date: 2024-03-14 22:24:08 +0800
categories: 编程
tags:
  - OpenSSL
  - Qt
  - SQLite
---

最近，我在实现 SQLite 的透明加解密时遇到一个~~有意思~~ H2 的问题。当我使用 Qt 读写数据库文件时，可以正常操作，但是使用对应的 sqlite3 命令时则提示 `database disk image is malformed`；同样的，当我 sqlite3 命令创建数据库文件，并尝试在 Qt 中访问时，也无法正常读取。

<!--more-->
## 问题定位

由于这些数据以 4K 大小存储，为了找到问题出在哪儿，我尝试将加解密前后的数据 dump 出来进行对比，最后发现在 Qt 中加密后写入的数据和读取并解密是正确的；但是，如果使用 sqlite3 命令尝试读取 Qt 写入的数据库文件，那么读取的加密数据是对的，但是解密出来的数据不对。这说明问题出在加解密函数上，下面是我在 SQLite 中实现加解密的基本框架（以下代码进行了简化）。

```c
static char *passwd = "hello";

static void
default_encrypt(unsigned char *in, int inlen, unsigned char *out, int *outlen)
{
    EVP_CIPHER_CTX *ctx;
    int l1, l2;
    const EVP_CIPHER *cipher = EVP_aes_128_cbc();

    ctx = EVP_CIPHER_CTX_new();
    EVP_EncryptInit_ex(ctx, cipher, NULL, passwd, NULL);
    EVP_CIPHER_CTX_set_padding(ctx, 0);
    EVP_EncryptUpdate(ctx, out, &l1, in, inlen);
    EVP_EncryptFinal_ex(ctx, out + l1, &l2);
    EVP_CIPHER_CTX_free(ctx);

    if (outlen) *outlen = l1 + l2;
}

static void
default_decrypt(unsigned char *in, int inlen, unsigned char *out, int *outlen)
{
    int l1, l2;
    const EVP_CIPHER *cipher = EVP_aes_128_cbc();

    ctx = EVP_CIPHER_CTX_new();
    EVP_DecryptInit_ex(ctx, cipher, NULL, passwd, NULL);
    EVP_CIPHER_CTX_set_padding(ctx, 0);
    EVP_DecryptUpdate(ctx, out, &l1, in, inlen);
    EVP_DecryptFinal_ex(ctx, out + l1, &l2);
    EVP_CIPHER_CTX_free(ctx);

    if (outlen) *outlen = l1 + l2;
}
```

如果您熟悉 OpenSSL 的对称加解密，那么您可能一眼就看到了上面的问题所在。

由于在解密前输入的数据都是相同的，而解密出来的数据不同，那么问题肯定是密钥不同导致的解密数据不同。再次阅读 OpenSSL 官方文档中关于 [`EVP_EncryptInit_ex()`](https://www.openssl.org/docs/man3.0/man3/EVP_EncryptInit_ex.html) 函数的说明，我发现其有如下一段描述：

> key is the symmetric key to use and iv is the IV to use (if necessary), the actual number of bytes used for the key and IV depends on the cipher.

上面这段话的意思很明显了，参数 `key` 是对称加解密的密钥，但是这个密钥的长度取决于密码算法。上面的示例代码中我使用的是 `aes_128_cbc`，其密钥长度为 128-bit，即 16 字节。然而，我将用户密码与密钥混淆了，从而导致在 sqlite3 命令中可以正常读写，但是在 Qt 中无法正常读写的问题（密码 `hello` 仅 5 个字节，后续的 11 个字节在 sqlite3 命令和 Qt 中可能不一致，导致解密出来的结果不同）。

## 解决方法

经过上面的分析，我们知道了上述问题的本质，那么如何将用户密码转换为密钥呢？OpenSSL 提供了 [`EVP_BytesToKey()`](https://www.openssl.org/docs/man3.1/man3/EVP_BytesToKey.html) 函数来实现该功能。因此，我们需要将上述代码做如下修改：

```c
static char *passwd = "hello";

static void
default_encrypt(unsigned char *in, int inlen, unsigned char *out, int *outlen)
{
    EVP_CIPHER_CTX *ctx;
    int l1, l2;
    const EVP_CIPHER *cipher = EVP_aes_128_cbc();
    unsigned char iv[EVP_MAX_IV_LENGTH] = { 0 };
    unsigned char key[EVP_MAX_KEY_LENGTH] = { 0 };

    EVP_BytesToKey(cipher, EVP_sha1(), NULL, (const unsigned char *) passwd,
                   strlen(passwd), 1024, key, iv);

    ctx = EVP_CIPHER_CTX_new();
    EVP_EncryptInit_ex(ctx, cipher, NULL, key, iv);
    EVP_CIPHER_CTX_set_padding(ctx, 0);
    EVP_EncryptUpdate(ctx, out, &l1, in, inlen);
    EVP_EncryptFinal_ex(ctx, out + l1, &l2);
    EVP_CIPHER_CTX_free(ctx);

    if (outlen) *outlen = l1 + l2;
}

static void
default_decrypt(unsigned char *in, int inlen, unsigned char *out, int *outlen)
{
    int l1, l2;
    const EVP_CIPHER *cipher = EVP_aes_128_cbc();
    unsigned char iv[EVP_MAX_IV_LENGTH] = { 0 };
    unsigned char key[EVP_MAX_KEY_LENGTH] = { 0 };

    EVP_BytesToKey(cipher, EVP_sha1(), NULL, (const unsigned char *) passwd,
                   strlen(passwd), 1024, key, iv);

    ctx = EVP_CIPHER_CTX_new();
    EVP_DecryptInit_ex(ctx, cipher, NULL, key, iv);
    EVP_CIPHER_CTX_set_padding(ctx, 0);
    EVP_DecryptUpdate(ctx, out, &l1, in, inlen);
    EVP_DecryptFinal_ex(ctx, out + l1, &l2);
    EVP_CIPHER_CTX_free(ctx);

    if (outlen) *outlen = l1 + l2;
}
```

经过上述修改，sqlite3 命令创建的数据库文件可以正常的在 Qt 中读写；相反，在 Qt 中创建的数据库文件也可以在 sqlite3 命令中进行正常读写，两者不再冲突。

## 参考

[1] https://www.openssl.org/docs/man3.0/man3/EVP_EncryptInit_ex.html
[2] https://www.openssl.org/docs/man3.0/man3/EVP_BytesToKey.html


<div class="just-for-fun">
笑林广记 - 拾蚂蚁

近视眼行路，见蚂蚁摆阵，疏密成行，疑是一物。
因掬而取之，撮之不起，乃叹息曰：“可惜一条好线，毁烂得蹙蹙断了。”
</div>
