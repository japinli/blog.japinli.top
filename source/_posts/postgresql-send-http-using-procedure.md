---
title: "PostgreSQL 使用存储过程发送 HTTP 请求"
date: 2021-11-16 22:46:35 +0800
categories: 数据库
tags:
  - PostgreSQL
---

在 Oracle 中可以通过 utl_http 来发送 HTTP 请求，PostgreSQL 中默认不支持，但是，我们可以通过 plpython3u 插件来实现这个功能。

<!--more-->

## 准备工作

首先我们需要安装 plpython3u 扩展，在编译 PostgreSQL 的时候加上 `--with-python` 选项，随后将其添加到 `shared_preload_libraries` 中。

```sql
ALTER SYSTEM SET shared_preload_libraries TO plpython3;
```

注意，我们在编译的时候需要安装 python3-devel 包。

接着重启数据库并以超级用户登录执行下面的命令在数据库中安装扩展（我们需要在使用到该功能的数据库中安装该插件）。

```sql
CREATE EXTENSION plpython3u;
```

在使用 Python 编写 PostgreSQL 存储过程发送 HTTP 请求时，我们使用到了 Python 的 requests 模块，因此需要先安装 requests 模块。

```shell
$ pip3 install requests
```

## 编写存储过程发送 HTTP 请求

现在一切工作准备就绪，我们可以通过 Python 来编写 PostgreSQL 的存储过程了，下面是一个简单的用例。

```sql
CREATE OR REPLACE PROCEDURE http_post(
    in    p_url      varchar,
    in    p_token    varchar,
    in    p_postdata text,
    inout x_status   varchar,
    inout x_response text)
AS $$
    plpy.log('start post')

    import requests

    plpy.log('set_header')
    headers = {'charset': 'utf8'}
    headers['Content-Type'] = 'application/json'

    l_token = ''
    if p_token:
        l_token = 'Bearer ' + p_token
        headers['Authorization'] = l_token
    plpy.log(l_token)

    try:
        r = requests.post(p_url, p_postdata, headers=headers, timeout=300)
        if r.status_code == 200:
            x_status = '200'
            x_response = r.text
        else:
            x_status = '400'
            x_response = 'Access Denied'
    except Exception as e:
        x_status = '500'
        x_response = str(e)
        plpy.log(str(e))

    return (x_status, x_response)
$$ LANGUAGE plpython3u;
```

我们可以将存储过程的执行权限赋予特定用户。

```sql
GRANT EXECUTE ON PROCEDURE http_post TO username;
```

## 测试

我们通过 Python 创建一个简单的 HTTP 服务器，代码如下所示。

```python
#!/bin/python2
import SimpleHTTPServer
import SocketServer

PORT = 8000

class ServerHandler(SimpleHTTPServer.SimpleHTTPRequestHandler):

    def do_POST(self):
        content_len = int(self.headers.getheader('content-length', 0))
        post_body = self.rfile.read(content_len)
        print post_body

        self.send_response(200)
        self.send_header('content-type', 'application/json')
        self.end_headers()
        self.wfile.write('{"data": "It works!"}')
        return

Handler = ServerHandler

httpd = SocketServer.TCPServer(("", PORT), Handler)

print "serving at :", PORT
httpd.serve_forever()
```

我们将上面的内容保存到 `httpd.py` 中，并赋予执行权限，随后在 psql 中执行下面的 SQL 来进行测试。

```sql
DO $$
DECLARE
    code varchar;
    resp text;
BEGIN
    CALL http_post('http://localhost:8000', 'xxxxx', '{"name": "Jim"}', code, resp);
    RAISE NOTICE '%: %', code, resp;
END;
$$ LANGUAGE plpgsql;
```

## 参考

[1] https://www.postgresql.org/docs/13/plpython.html

<div class="just-for-fun">
笑林广记 - 衙官隐语

衙官聚会，各问何职。
一官曰：“随常茶饭掇将来，盖义取现成（县丞）也。”
一官曰：“滚汤锅里下文书，乃煮（主）簿也。”
一官曰：“乡下蛮子租粪窖。”
问者不解，答曰：“典屎（史同音）也。”
</div>
