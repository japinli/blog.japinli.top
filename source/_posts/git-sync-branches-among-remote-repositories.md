---
title: "Git 多仓库分支同步"
date: 2019-01-22 20:58:29 +0800
category: 杂项
tags:
  - git
---

今天遇到一个 git 远程仓库分支同步的问题，主要的诉求是将两个远程仓库的分支同步到一致状态。起初，项目只是在 GitHub 上进行维护，后期又在 GitLab 上创建了该项目，并且两个仓库之间的分支情况有所不同。我们可以使用如下命令同步两个远程仓库之间的分支信息。

```
$ git fetch --all -p
$ git push github "refs/remotes/gitlab/*:refs/heads/*"
$ git push gitlab "refs/remotes/github/*:refs/heads/*"
```

__备注：__ `github` 指向远端的 GitHub 项目地址，同理，`gitlab` 指向远端的 GitLab 项目地址。
