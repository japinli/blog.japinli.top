---
title: "Gtags 忽略不相关的目录"
date: 2021-06-05 17:09:59 +0800
category: 杂项
tags:
  - gtags
---

我在 Emacs 中使用 gtags (GNU global source code tag system) 来作为代码导航的基本工具，它默认标记根目录及其子目录，但是有一些子目录其实我并不想要被标记。本文简要记录一下如何告知 gtags 忽略某些目录或文件。

<!-- more -->

## 方法一

gtags 默认提供了一个配置文件，我们可以通过这个配置文件来进行定制。为了不影响其他用户，建议拷贝到各自用户的家目录下进行设置，如下所示。

Linux 系统一般为 `/usr/local/share/gtags/gtags.conf`（MacOS 系统在 `/usr/local/etc/gtags.conf`），我们将其拷贝到用户家目录下，并命名为 `.globalrc`，如下所示。

``` shell
-- Linux
$ cp /usr/local/share/gtags/gtags.conf ~/.globalrc
-- MacOS
$ cp /usr/local/etc/gtags.conf ~/.globalrc
```

接着，我们在该文件中搜索 `skip`，然后加上我们想要忽略的目录或文件即可，

```
common:\
    :skip=Debug/,HTML/,HTML.pub/,tags,TAGS,ID,y.tab.c,y.tab.h,gtags.files,cscope.files,cscope.out,cscope.po.out,cscope.in.out,SCCS/,RCS/,CVS/,CVSROOT/,{arch}/,autom4te.cache/,*.orig,*.rej,*.bak,*~,#*#,*.swp,*.tmp,*_flymake.*,*_flymake,*.o,*.a,*.so,*.lo,*.zip,*.gz,*.bz2,*.xz,*.lzh,*.Z,*.tgz,*.min.js,*min.css:
```

该项使用逗号作为分隔符，支持正则表达式。

## 方法二

上述方法稍微复杂，针对不同的项目，配置起来比较繁琐，最近在看到 [Peter Eisentraut](http://peter.eisentraut.org) 关于 [PostgreSQL 中使用 GNU Global 的文章](http://peter.eisentraut.org/blog/2016/07/20/using-gnu-global-with-postgresql)之后，才发现原来还可以这样优雅的解决。

```bash
$ git ls-files > gtags.files  # Git 托管的源码目录
$ gtags
```

我们利用 git 的特性来获取到所有的文件，然后将其保存到 `gtags.files` 文件中，随后在执行 `gtags` 命令来生成符号信息。这种方式也存在一些缺点：

1. 它不能为自动生成的文件提供导航；
2. 每次拉取新代码时，都需要重复执行 `git ls-files > gtags.files && gtags` 命令；
3. 新增的文件（尚未纳入 git 托管）同样不能提供导航。

## 参考

[1] https://stackoverflow.com/questions/42315741/how-gtags-exclude-some-specific-subdirectories
[2] http://peter.eisentraut.org/blog/2016/07/20/using-gnu-global-with-postgresql


<div class="just-for-fun">
笑林广记 - 帝怕妒妇

房夫人性妒悍，玄龄惧之，不敢置一妾。
太宗命后召夫人，告以媵妾之流，今有定制，帝将有美女之赐。
夫人执意不回，帝遣斟以恐之，曰：“若然，是抗旨矣，当饮此鸠。”
夫人一举而尽，略无留难。曰：“我见尚怕，何况于玄龄？”
</div>
