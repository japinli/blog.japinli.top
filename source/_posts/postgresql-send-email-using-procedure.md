---
title: "PostgreSQL 使用存储过程发送邮件"
date: 2021-11-17 22:38:34 +0800
categories: 数据库
tags:
  - PostgreSQL
---

在{% post_link postgresql-send-http-using-procedure 上一篇 %}中我介绍了如何在 PostgreSQL 数据库中使用存储过程来发送 HTTP 请求，本文则介绍如何使用 PostgreSQL 的存储过程发送邮件。

Oracle 数据库提供了 ult_smtp 来发送邮件，PostgreSQL 同样的不支持该功能，因此只能采取曲线救国的策略，本文将采用 plpython3u 来编写存储过程并发送邮件。

<!--more-->

## 准备工作

这里的准备工作与上一篇文章类似，唯一不同的是我们不需要装任何 Python 的依赖，因为 Python 默认已经安装好了。这里简要提一下如何在数据库中安装 plpython3u 插件。

```sql
$ psql postgres -c 'ALTER SYSTEM SET shared_preload_libraries TO plpython3;'
$ pg_ctl restart
$ psql postgres -c 'CREATE EXTENSION plpython3u;'
```

## 编写存储过程发送邮件

准备工作已经就绪，接下来就可以编译存储过程了。下面是一个简单的用例。

```sql
CREATE OR REPLACE PROCEDURE send_email(
    sender      varchar,
    receiver    varchar,
    copyto      varchar,
    title       varchar,
    content     varchar,
    filenames   varchar,
    smtp_user   varchar default 'your-email@hotmail.com',
    smtp_passwd varchar default 'your-password',
    smtp_server varchar default 'outlook.office365.com',
    smtp_port   int default 587)
AS $$

import os
import ssl
import smtplib
from email.mime.text import MIMEText
from email.header import Header
from email.mime.multipart import MIMEMultipart

message = MIMEMultipart()
message['From'] = sender
message['To'] = receiver
message['Cc'] = copyto
message['Subject'] = title

try:
    message.attach(MIMEText(content, 'plain', 'utf-8'))

    # Add attachement to email
    if filenames:
        for fname in filenames.split(';'):
            if not fname:
                continue

            attach = MIMEText(open(fname, 'rb').read(), 'base64', 'utf-8')
            attach['Content-Type'] = 'application/octect-stream'
            attach['Content-Disposition'] = 'attachement;filename="{0}"'.format(os.path.basename(fname))
            message.attach(attach)

    context = ssl.create_default_context()
    rcpts = receiver.split(',') + copyto.split(',')
    serv = smtplib.SMTP(smtp_server, smtp_port)
    serv.starttls(context=context)
    serv.login(smtp_user, smtp_passwd)
    serv.sendmail(sender, rcpts, message.as_string())
    plpy.log('ok')
except Exception as e:
    plpy.error('failed' + str(e))

$$ LANGUAGE plpython3u;
```

您可以将上面的存储过程导入到已经安装了 plpython3u 插件的数据库中（注意，您需要修改邮件服务器和用户信息），随后执行下面的命令进行测试。

```sql
call send_email(
    'japinli@hotmail.com',     -- 发送者
    'jianping.li@xxxxx.cn',    -- 接收者
    '',                        -- 抄送
    'Send Email using PostgreSQL Procedure',      -- 邮件主题
    'This email is sent by PostgreSQL procedure', -- 邮件内容
    '/tmp/scor2272ueR'                            -- 附件
);
```

测试结果如下所示。

{% asset_img email.jpg %}

<div class="just-for-fun">
笑林广记 - 太监观风

镇守太监观风，出“后生可畏焉”为题，众皆掩口而笑，乃问其故，
教官禀曰：“诸生以题目太难，求减得一字为好。”
乃笑曰：“既如此，除了‘后’字，只做‘生可畏焉’罢。”
</div>
