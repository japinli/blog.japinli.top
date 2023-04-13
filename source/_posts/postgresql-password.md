---
title: "聊聊 PostgreSQL 中的密码"
date: 2023-03-29 22:41:49 +0800
categories: 数据库
tags:
  - PostgreSQL
---

本文将简单的聊聊 PostgreSQL 的密码存储以及认证过程。在 PostgreSQL 10 之前，密码存储是采用明文和 MD5 进行存储的，在 10 版本之后则采用 MD5 和 SCRAM 进行存储，废弃了明文存储。

{% asset_img pg-password.png %}

<!--more-->

## 密码存储

下图是 PostgreSQL 10 之前的密码存储原理图。

{% asset_img pg-md5-password.png %}

我们可以通过下面的 SQL 语句来进行验证。

```sql
postgres=# CREATE USER japin WITH PASSWORD '123456';
CREATE USER
postgres=# SELECT rolname, rolpassword FROM pg_authid WHERE rolname = 'japin';
 rolname |             rolpassword
---------+-------------------------------------
 japin   | md5e01ae1cb17dfc0143ffb8dacc27d3c95
(1 row)

postgres=# SELECT 'japin' AS rolename, 'md5' || md5('123456'||'japin') AS rolpasswd;
 rolename |              rolpasswd
----------+-------------------------------------
 japin    | md5e01ae1cb17dfc0143ffb8dacc27d3c95
(1 row)
```

从上面可以看到 PostgreSQL 是使用的用户密码加上用户名信息计算 md5 值，然后存储在数据库中的。需要注意的时，PostgreSQL 也支持明文存储用户密码，如下所示。

```sql
postgres=# CREATE USER u01 WITH UNENCRYPTED PASSWORD '123456';
CREATE ROLE
postgres=# SELECT rolname, rolpassword FROM pg_authid WHERE rolname = 'u01';
 rolname | rolpassword
---------+-------------
 u01     | 123456
(1 row)
```

默认情况下都是加密存储的，这个是通过参数 [`password_encryption`](https://www.postgresql.org/docs/9.6/runtime-config-connection.html#GUC-PASSWORD-ENCRYPTION) 决定的。

下面的代码是关于 PostgreSQL 如何处理密码存储的（[源码在这里](https://github.com/postgres/postgres/blob/REL9_6_STABLE/src/backend/commands/user.c#L68)）。

```c
Oid
CreateRole(CreateRoleStmt *stmt)
{
	[...]

	bool		encrypt_password = Password_encryption; /* encrypt password? */
	char		encrypted_password[MD5_PASSWD_LEN + 1];

	[...]

	/* Extract options from the statement node tree */
	foreach(option, stmt->options)
	{
		DefElem    *defel = (DefElem *) lfirst(option);

		if (strcmp(defel->defname, "password") == 0 ||
			strcmp(defel->defname, "encryptedPassword") == 0 ||
			strcmp(defel->defname, "unencryptedPassword") == 0)
		{
			if (dpassword)
				ereport(ERROR,
						(errcode(ERRCODE_SYNTAX_ERROR),
						 errmsg("conflicting or redundant options")));
			dpassword = defel;
			if (strcmp(defel->defname, "encryptedPassword") == 0)
				encrypt_password = true;
			else if (strcmp(defel->defname, "unencryptedPassword") == 0)
				encrypt_password = false;
		}

		[...]
	}

	if (dpassword && dpassword->arg)
		password = strVal(dpassword->arg);

	[...]

	/*
	 * Call the password checking hook if there is one defined
	 */
	if (check_password_hook && password)
		(*check_password_hook) (stmt->role,
								password,
			   isMD5(password) ? PASSWORD_TYPE_MD5 : PASSWORD_TYPE_PLAINTEXT,
								validUntil_datum,
								validUntil_null);

	[...]

	if (password)
	{
		if (!encrypt_password || isMD5(password))
			new_record[Anum_pg_authid_rolpassword - 1] =
				CStringGetTextDatum(password);
		else
		{
			if (!pg_md5_encrypt(password, stmt->role, strlen(stmt->role),
								encrypted_password))
				elog(ERROR, "password encryption failed");
			new_record[Anum_pg_authid_rolpassword - 1] =
				CStringGetTextDatum(encrypted_password);
		}
	}
	else
		new_record_nulls[Anum_pg_authid_rolpassword - 1] = true;

	[...]
}
```

## 密码认证

下图 PostgreSQL 中基于 MD5 的密码认证流程。

{% asset_img pg-md5-auth.png %}

1. 客户端程序首先发送连接请求。
2. 服务在接收到客户端的连接请求之后将生成一个随机的 salt 值发送给客户端用于计算密码的 MD5 值。
3. 客户端根据用户密码和用户信息计算出 MD5 值，随后在利用来自服务器端的 salt 计算出 MD5 值用于服务器校验。
4. 服务器通过数据库中存储的用户密码 MD5 值以及其生成的 salt 再次计算 MD5 值并与来自客户端的 MD5 值进行比较，相同则说明用户密码正确，登陆成功。

服务器在接收到客户端的连接请求之后将创建一个进程来处理连接，并通过 [`ClientAuthentication()`](https://github.com/postgres/postgres/blob/REL9_6_STABLE/src/backend/libpq/auth.c#L314) 函数处理。

```c
void
ClientAuthentication(Port *port)
{

	int			status = STATUS_ERROR;
	char	   *logdetail = NULL;

	/*
	 * Get the authentication method to use for this frontend/database
	 * combination.  Note: we do not parse the file at this point; this has
	 * already been done elsewhere.  hba.c dropped an error message into the
	 * server logfile if parsing the hba config file failed.
	 */
	hba_getauthmethod(port);

	[...]

	/*
	 * Now proceed to do the actual authentication check
	 */
	switch (port->hba->auth_method)
	{
		[...]

		case uaMD5:
			if (Db_user_namespace)
				ereport(FATAL,
						(errcode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION),
						 errmsg("MD5 authentication is not supported when \"db_user_namespace\" is enabled")));
			sendAuthRequest(port, AUTH_REQ_MD5);
			status = recv_and_check_password_packet(port, &logdetail);
			break;

		[...]
	}

	if (ClientAuthentication_hook)
		(*ClientAuthentication_hook) (port, status);

	if (status == STATUS_OK)
		sendAuthRequest(port, AUTH_REQ_OK);
	else
		auth_failed(port, status, logdetail);
}
```

函数 `sendAuthRequest()` 则负责发送认证的方式，如下所示。

```c
/*
 * Send an authentication request packet to the frontend.
 */
static void
sendAuthRequest(Port *port, AuthRequest areq)
{
	StringInfoData buf;

	CHECK_FOR_INTERRUPTS();

	/* 消息头以及认证类型 */
	pq_beginmessage(&buf, 'R');
	pq_sendint(&buf, (int32) areq, sizeof(int32));

	/*
	 * 对于 MD5 认证，发送 salt，md5Salt 是在 ConnCreate() 函数中由 RandomSalt()
	 * 函数预先生成的。
	 */
	if (areq == AUTH_REQ_MD5)
		pq_sendbytes(&buf, port->md5Salt, 4);

#if defined(ENABLE_GSS) || defined(ENABLE_SSPI)

	/*
	 * Add the authentication data for the next step of the GSSAPI or SSPI
	 * negotiation.
	 */
	else if (areq == AUTH_REQ_GSS_CONT)
	{
		if (port->gss->outbuf.length > 0)
		{
			elog(DEBUG4, "sending GSS token of length %u",
				 (unsigned int) port->gss->outbuf.length);

			pq_sendbytes(&buf, port->gss->outbuf.value, port->gss->outbuf.length);
		}
	}
#endif

	pq_endmessage(&buf);

	/*
	 * Flush message so client will see it, except for AUTH_REQ_OK, which need
	 * not be sent until we are ready for queries.
	 */
	if (areq != AUTH_REQ_OK)
		pq_flush();

	CHECK_FOR_INTERRUPTS();
}
```

函数 [`pg_password_sendauth()`](https://github.com/postgres/postgres/blob/REL9_6_STABLE/src/interfaces/libpq/fe-auth.c#L501) 用于计算用户密码 MD5 值并发送到服务器发，如下所示。

```c
static int
pg_password_sendauth(PGconn *conn, const char *password, AuthRequest areq)
{
	int			ret;
	char	   *crypt_pwd = NULL;
	const char *pwd_to_send;

	/* Encrypt the password if needed. */

	switch (areq)
	{
		case AUTH_REQ_MD5:
			{
				char	   *crypt_pwd2;

				/* Allocate enough space for two MD5 hashes */
				crypt_pwd = malloc(2 * (MD5_PASSWD_LEN + 1));
				if (!crypt_pwd)
				{
					printfPQExpBuffer(&conn->errorMessage,
									  libpq_gettext("out of memory\n"));
					return STATUS_ERROR;
				}

				/* 先对密码和用户名计算 MD5 值 */
				crypt_pwd2 = crypt_pwd + MD5_PASSWD_LEN + 1;
				if (!pg_md5_encrypt(password, conn->pguser,
									strlen(conn->pguser), crypt_pwd2))
				{
					free(crypt_pwd);
					return STATUS_ERROR;
				}
				/* 随后里面服务器发送的 salt 在计算 MD5 值，注意去除了 md5 前缀 */
				if (!pg_md5_encrypt(crypt_pwd2 + strlen("md5"), conn->md5Salt,
									sizeof(conn->md5Salt), crypt_pwd))
				{
					free(crypt_pwd);
					return STATUS_ERROR;
				}

				pwd_to_send = crypt_pwd;
				break;
			}
		case AUTH_REQ_PASSWORD:
			pwd_to_send = password;
			break;
		default:
			return STATUS_ERROR;
	}
	/* Packet has a message type as of protocol 3.0 */
	/* 发送给服务器 */
	if (PG_PROTOCOL_MAJOR(conn->pversion) >= 3)
		ret = pqPacketSend(conn, 'p', pwd_to_send, strlen(pwd_to_send) + 1);
	else
		ret = pqPacketSend(conn, 0, pwd_to_send, strlen(pwd_to_send) + 1);
	if (crypt_pwd)
		free(crypt_pwd);
	return ret;
}
```

最后通过 [`recv_and_check_password_packet()`](https://github.com/postgres/postgres/blob/REL9_6_STABLE/src/backend/libpq/auth.c#L732) 来接收客户端的密码信息并验证密码的有效性。

```c
static int
recv_and_check_password_packet(Port *port, char **logdetail)
{
	char	   *passwd;
	int			result;

	/* 接收客户端密码信息 */
	passwd = recv_password_packet(port);

	if (passwd == NULL)
		return STATUS_EOF;		/* client wouldn't send password */

	/* 执行具体的密码验证工作 */
	result = md5_crypt_verify(port, port->user_name, passwd, logdetail);

	pfree(passwd);

	return result;
}
```

这里就不在展开 [`md5_crypt_verify()`](https://github.com/postgres/postgres/blob/REL9_6_STABLE/src/backend/libpq/crypt.c#L32) 函数了，感兴趣的朋友可以直接去阅读[源码](https://github.com/postgres/postgres/blob/REL9_6_STABLE/src/backend/libpq/crypt.c#L32)。

## scram-sha-256

MD5 是一种单向哈希方式，因此可以采用暴力破解和彩虹表字典攻击等方式进行破解，安全性相对较低。SCRAM 是 **S**alted **C**hallenge **R**esponse **A**uthentication **M**ethod 的缩写，使用的是挑战响应机制，每次认证过程都要生成一个服务器端随机数，并在密码哈希计算中加入盐值来防止撞库攻击，提高了安全性。SCRAM 在 [RFC5802](https://www.rfc-editor.org/rfc/rfc5802) 中给出了详细的说明，包括认证的步骤，发送的消息内容等。

我们已经知道 PostgreSQL 是如何使用 MD5 算法存储的密码了，由于给定的 MD5 哈希值构造字符串太容易了，因此 PostgreSQL 在 10 版本中引入了 scram-sha-256 加密算法。接下来我们就来看看它的原理已经实现（注意，PostgreSQL 10 版本同样移除了明文存储密码的功能）。

默认情况下，PostgreSQL 10 版本的 `password_encryption` 依然是 `md5`，在 PostgreSQL 14 中则切换为了 `scram-sha-256`。您可以使用下面的命令来修改密码策略。

```sql
postgres=# show password_encryption ;
 password_encryption
---------------------
 md5
(1 row)

postgres=# ALTER SYSTEM SET password_encryption TO 'scram-sha-256';
ALTER SYSTEM
postgres=# SELECT pg_reload_conf();
 pg_reload_conf
----------------
 t
(1 row)

postgres=# show password_encryption;
 password_encryption
---------------------
 scram-sha-256
(1 row)
```

接着我们同样创建一个用户来观察一下密码的存储结构。

```sql
postgres=# SELECT rolname, rolpassword FROM pg_authid WHERE rolname = 'japin';
 rolname |                                                              rolpassword
---------+---------------------------------------------------------------------------------------------------------------------------------------
 japin   | SCRAM-SHA-256$4096:cUy1lgsS7PnQv4k3p8fE4A==$LfgSXaK4NJBN4WHxBDlohQT/zrmMSsdgMrbWsgeodJY=:SRIYmyTyciPRuQJHJb+bAcXY0Kn6aOuZ9ztAS34GXDU=
(1 row)
```

从上面的结果可以看到，密码的存储更为复杂了，我们可以将其拆分为 5 个部分。

{% asset_img pg-scram-password.png %}

* DIGEST - 密码摘要算法，其中 `SCRAM` 是固定的，后面的则是具体的 HASH 摘要算法。
* ITERATIONS - 迭代次数。
* SALT - 由服务器生产的 salt，见 [`pg_backend_random()`](https://github.com/postgres/postgres/blob/REL_10_STABLE/src/backend/utils/misc/backend_random.c#L52) 函数（当使用 `\password` 修改密码是则由 [`pg_frontend_random()`](https://github.com/postgres/postgres/blob/REL_10_STABLE/src/interfaces/libpq/fe-auth-scram.c#L676) 函数生成）。
* STORED_KEY - 加密后的用户密码信息，用于验证用户。
* SERVER_KEY - 加密后的服务器信息，用于验证服务器。

PostgreSQL 使用函数 [`scram_build_verifier()`](https://github.com/postgres/postgres/blob/REL_10_STABLE/src/common/scram-common.c#L186) 来创建 SCRAM-SHA-256 密码，其流程如下图所示。

{% asset_img scram-build-verifier.png %}

与 SALT 的生成类似，scram-sha-256 的密码可能是 psql 通过 `\password` 命令使用函数 [`pg_fe_scram_build_verifier()`]() 生成。下面是 `scram_build_verifier()` 函数的源码。

```c
char *
scram_build_verifier(const char *salt, int saltlen, int iterations,
					 const char *password)
{
	uint8		salted_password[SCRAM_KEY_LEN];
	uint8		stored_key[SCRAM_KEY_LEN];
	uint8		server_key[SCRAM_KEY_LEN];
	char	   *result;
	char	   *p;
	int			maxlen;

	if (iterations <= 0)
		iterations = SCRAM_DEFAULT_ITERATIONS;

	/* Calculate StoredKey and ServerKey */
	scram_SaltedPassword(password, salt, saltlen, iterations,
						 salted_password);
	scram_ClientKey(salted_password, stored_key);
	scram_H(stored_key, SCRAM_KEY_LEN, stored_key);

	scram_ServerKey(salted_password, server_key);

	/*----------
	 * The format is:
	 * SCRAM-SHA-256$<iteration count>:<salt>$<StoredKey>:<ServerKey>
	 *----------
	 */
	maxlen = strlen("SCRAM-SHA-256") + 1
		+ 10 + 1				/* iteration count */
		+ pg_b64_enc_len(saltlen) + 1	/* Base64-encoded salt */
		+ pg_b64_enc_len(SCRAM_KEY_LEN) + 1 /* Base64-encoded StoredKey */
		+ pg_b64_enc_len(SCRAM_KEY_LEN) + 1;	/* Base64-encoded ServerKey */

#ifdef FRONTEND
	result = malloc(maxlen);
	if (!result)
		return NULL;
#else
	result = palloc(maxlen);
#endif

	p = result + sprintf(result, "SCRAM-SHA-256$%d:", iterations);

	p += pg_b64_encode(salt, saltlen, p);
	*(p++) = '$';
	p += pg_b64_encode((char *) stored_key, SCRAM_KEY_LEN, p);
	*(p++) = ':';
	p += pg_b64_encode((char *) server_key, SCRAM_KEY_LEN, p);
	*(p++) = '\0';

	Assert(p - result <= maxlen);

	return result;
}
```

在了解了 SCRAM 密码的存储之后，我们接着来看看 SCRAM 是如何进行认证的。下图是整个 SCRAM 的大致认证流程。

{% asset_img pg-scram-auth.png %}

1. 客户端请求连接到服务器。
2. 服务器接收到来自客户端的连接请求，确定当前的认证类型为 SCRAM，并将其返回给客户端。
3. 客户端进入 SCRAM 认证流程，生成 `client nonce` 发送给服务器。
4. 服务器接收到客户端的 `client nonce` 之后将生成 `server nonce`并附加到 `client nonce` 之后，与 `salt` 和 `iterations` 一同发送给客户端。
5. 客户端在接收到服务器的发送来的 `nonce` 之后进行验证，随后根据 `salt`，`iterations` 以及用户的明文密码计算 `client signature` 并发送给服务器进行验证。
6. 服务器验证通过之后将生成 `server signature` 并发送给客户端进行验证。

接下来我们详细看看客户端和服务器是如何验证用户信息的。我们知道服务存储了密码的加密算法、`iterations`、`salt`、`stored key` 和 `server key`，密码验证就是基于这些信息在加上用户明文密码完成的。

`client nonce` 和 `server nonce` 分别由 `pg_frontend_random()` 和 `pg_backend_random()` 生成，本质上就是两个随机字串。最为重要的还是 `client signature` 和 `server signature`。

### Client Signature

在 SCRAM 认证流程图中，我们可以看到 `client signature` 是由 [`build_client_final_message()`](https://github.com/postgres/postgres/blob/REL_10_STABLE/src/interfaces/libpq/fe-auth-scram.c#L353) 函数生成的。

```c
static char *
build_client_final_message(fe_scram_state *state, PQExpBuffer errormessage)
{
	PQExpBufferData buf;
	uint8		client_proof[SCRAM_KEY_LEN];
	char	   *result;

	initPQExpBuffer(&buf);

	/*
	 * Construct client-final-message-without-proof.  We need to remember it
	 * for verifying the server proof in the final step of authentication.
	 */
	appendPQExpBuffer(&buf, "c=biws,r=%s", state->nonce);
	if (PQExpBufferDataBroken(buf))
		goto oom_error;

	state->client_final_message_without_proof = strdup(buf.data);
	if (state->client_final_message_without_proof == NULL)
		goto oom_error;

	/* Append proof to it, to form client-final-message. */
	/* 生成 client signature */
	calculate_client_proof(state,
						   state->client_final_message_without_proof,
						   client_proof);

	appendPQExpBuffer(&buf, ",p=");
	if (!enlargePQExpBuffer(&buf, pg_b64_enc_len(SCRAM_KEY_LEN)))
		goto oom_error;
	buf.len += pg_b64_encode((char *) client_proof,
							 SCRAM_KEY_LEN,
							 buf.data + buf.len);
	buf.data[buf.len] = '\0';

	result = strdup(buf.data);
	if (result == NULL)
		goto oom_error;

	termPQExpBuffer(&buf);
	return result;

oom_error:
	termPQExpBuffer(&buf);
	printfPQExpBuffer(errormessage,
					  libpq_gettext("out of memory\n"));
	return NULL;
}
```

`build_client_final_message()` 函数的主要工作是构建客户端 SCRAM 认证的最终消息，在该消息后面可以附带 `proof` 信息，这个 `proof` 信息便是用于认证用户的，它由 [`calculate_client_proof()`](https://github.com/postgres/postgres/blob/REL_10_STABLE/src/interfaces/libpq/fe-auth-scram.c#L560) 函数通过用户密码、`salt` 和 `iterations` 构建，如下所示。

```c
static void
calculate_client_proof(fe_scram_state *state,
					   const char *client_final_message_without_proof,
					   uint8 *result)
{
	uint8		StoredKey[SCRAM_KEY_LEN];
	uint8		ClientKey[SCRAM_KEY_LEN];
	uint8		ClientSignature[SCRAM_KEY_LEN];
	int			i;
	scram_HMAC_ctx ctx;

	/*
	 * Calculate SaltedPassword, and store it in 'state' so that we can reuse
	 * it later in verify_server_signature.
	 */
	scram_SaltedPassword(state->password, state->salt, state->saltlen,
						 state->iterations, state->SaltedPassword);

	scram_ClientKey(state->SaltedPassword, ClientKey);
	scram_H(ClientKey, SCRAM_KEY_LEN, StoredKey);

	scram_HMAC_init(&ctx, StoredKey, SCRAM_KEY_LEN);
	scram_HMAC_update(&ctx,
					  state->client_first_message_bare,
					  strlen(state->client_first_message_bare));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  state->server_first_message,
					  strlen(state->server_first_message));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  client_final_message_without_proof,
					  strlen(client_final_message_without_proof));
	scram_HMAC_final(ClientSignature, &ctx);

	for (i = 0; i < SCRAM_KEY_LEN; i++)
		result[i] = ClientKey[i] ^ ClientSignature[i];
}
```

当您看到上面的代码是否有种似成相识的感觉，没错，它与 `scram_build_verifier()` 函数有些许类似，即计算 `StoredKey` 这部分代码是相同的，而后面的代码则结合认证过程中的消息计算 `ClientSignature`，最后将 `ClientKey` 和 `ClientSignature` 进行异或并发送给服务器。服务器在接收到该 `proof` 信息之后将通过 [`verify_client_proof()`](https://github.com/postgres/postgres/blob/REL_10_STABLE/src/backend/libpq/auth-scram.c#L910) 函数结合 `proof` 信息和服务器存储的 `StoredKey` 反推出 `client key`，随后在根据推导出来的 `ClientKey` 计算客户端认证的 `StoredKey` 并与服务器存储的 `StoredKey` 进行比较，相同则认证成功，不同则认证失败。

```
static bool
verify_client_proof(scram_state *state)
{
	uint8		ClientSignature[SCRAM_KEY_LEN];
	uint8		ClientKey[SCRAM_KEY_LEN];
	uint8		client_StoredKey[SCRAM_KEY_LEN];
	scram_HMAC_ctx ctx;
	int			i;

	/* calculate ClientSignature */
	scram_HMAC_init(&ctx, state->StoredKey, SCRAM_KEY_LEN);
	scram_HMAC_update(&ctx,
					  state->client_first_message_bare,
					  strlen(state->client_first_message_bare));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  state->server_first_message,
					  strlen(state->server_first_message));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  state->client_final_message_without_proof,
					  strlen(state->client_final_message_without_proof));
	scram_HMAC_final(ClientSignature, &ctx);

	/* Extract the ClientKey that the client calculated from the proof */
	for (i = 0; i < SCRAM_KEY_LEN; i++)
		ClientKey[i] = state->ClientProof[i] ^ ClientSignature[i];

	/* Hash it one more time, and compare with StoredKey */
	scram_H(ClientKey, SCRAM_KEY_LEN, client_StoredKey);

	if (memcmp(client_StoredKey, state->StoredKey, SCRAM_KEY_LEN) != 0)
		return false;

	return true;
}
```

### Server Signature

相较于 `client signature` 而言，`server signature` 就要简单许多，类似的，它是由 [`build_server_final_message()`](https://github.com/postgres/postgres/blob/REL_10_STABLE/src/backend/libpq/auth-scram.c#L1095) 函数生成，如下所示。

```c
static char *
build_server_final_message(scram_state *state)
{
	uint8		ServerSignature[SCRAM_KEY_LEN];
	char	   *server_signature_base64;
	int			siglen;
	scram_HMAC_ctx ctx;

	/* calculate ServerSignature */
	scram_HMAC_init(&ctx, state->ServerKey, SCRAM_KEY_LEN);
	scram_HMAC_update(&ctx,
					  state->client_first_message_bare,
					  strlen(state->client_first_message_bare));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  state->server_first_message,
					  strlen(state->server_first_message));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  state->client_final_message_without_proof,
					  strlen(state->client_final_message_without_proof));
	scram_HMAC_final(ServerSignature, &ctx);

	server_signature_base64 = palloc(pg_b64_enc_len(SCRAM_KEY_LEN) + 1);
	siglen = pg_b64_encode((const char *) ServerSignature,
						   SCRAM_KEY_LEN, server_signature_base64);
	server_signature_base64[siglen] = '\0';

	/*------
	 * The syntax for the server-final-message is: (RFC 5802)
	 *
	 * verifier		   = "v=" base64
	 *					 ;; base-64 encoded ServerSignature.
	 *
	 * server-final-message = (server-error / verifier)
	 *					 ["," extensions]
	 *
	 *------
	 */
	return psprintf("v=%s", server_signature_base64);
}
```

客户端在接收到 `server signature` 之后，通过 [`verify_server_signature()`](https://github.com/postgres/postgres/blob/REL_10_STABLE/src/interfaces/libpq/fe-auth-scram.c#L603) 函数进行验证，该函数根据 `salt` 和 `password` 计算出 `ServerKey` 随后在结合认证过程中的消息生成 `ServerSignature` 并与接收到的 `ServerSignature` 进行比对，相同则认证成功，不同则认证失败。

**注意：**

1. 我在分析 MD5 加密存储的时候使用的是 9.6 的代码，在分析 SCRAM 的时候用的是 10 的代码，它们之间关于 MD5 的处理存在一定的差异，但是大体流程是一样的。
2. PostgreSQL 11 版本中支持了 `channel binding`，可以将 SCRAM 与 TLS 结合实现安全传输。

## 参考

[1] https://www.pgcon.org/2019/schedule/attachments/530_scram.pdf
[2] https://github.com/postgres/postgres/tree/REL9_6_STABLE
[3] https://github.com/postgres/postgres/tree/REL_10_STABLE

<div class="just-for-fun">
笑林广记 - 老面皮

或问世间何物最硬，曰：“石头与钢铁。”
其人曰：“石可碎，铁可錾，安得为硬？以弟看来惟兄面上的髭须最硬，铁石总不如也。”
问其故，答曰：“兄面皮厚，竟被其出。”
须者回嘲曰：“足下面皮更老，这等硬须还钻不透。”
</div>
