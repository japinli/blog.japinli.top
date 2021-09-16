---
title: "Hexo NexT (v8.x) 主题添加近期文章"
date: 2020-08-29 07:04:18 +0800
category: 博客
tags:
  - hexo
---

最近将博客由 NexT-v5.x 迁移到 NexT-v8.x 版本，这其中有很多东西已将发生变化了。本文简要介绍一下如何在新版中加入近期文章的功能。NexT-v8.x 版本将模版文件由原来的 `swig` 变更为 `njk` 后缀，因此，之前的近期文章的功能不再适用，我们需要稍作修改。

<!-- more -->

## 创建自定义文件

NexT-v8.x 支持自定义 `njk` 文件，从而避免修改 NexT 的源码，见参考链接 [[2](https://theme-next.js.org/docs/advanced-settings/custom-files.html?highlight=sideb)]。我们在站点的 `source` 目录下创建 `_data/sidebar.njk` 文件，并加入如下内容：

```
<!-- recent posts -->
{%- if theme.recent_posts %}
    <div class="links-of-blogroll motion-element {{ "links-of-blogroll-" + theme.recent_posts_layout }}">
        <div class="links-of-blogroll-title recent-posts-title">
	    <i class="fa fa-history {{ theme.recent_posts_icon | lower }}" aria-hidden="true"></i>
            {{ theme.recent_posts_title }}
	</div>
	<ul class="links-of-blogroll-list recent-posts-list">
	    {%- set posts = site.posts.sort('-date').toArray() %}
	    {%- for post in posts.slice('0', '5') %}
	        <li class="my-links-of-blogroll-item">
		    <a href="{{ url_for(post.path) }}" title="{{ post.title }}" target="">
		    {{ post.title }}
		    </a>
		</li>
	    {%- endfor %}
	</ul>
    </div>
{%- endif %}
```

## 修改主题配置文件

接着我们在站点目录下的主题配置文件（_config.next.yml）中加入如下内容开启近期文章功能。

```
recent_posts: true
recent_posts_title: 近期文章
recent_posts_layout: block
```

接着重启服务，我们便可以看到如下所示的近期文章板块。

{% asset_img recent-posts.jpg %}

## 参考

[1] https://theme-next.js.org/next-8-0-0-rc-1-released/
[2] https://theme-next.js.org/docs/advanced-settings/custom-files.html?highlight=sideb
[3] https://hasaik.com/posts/ab21860c.html
