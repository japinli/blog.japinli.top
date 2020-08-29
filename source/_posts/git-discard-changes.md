---
title: "Git 撤销已经修改的文件"
date: 2019-12-16 22:28:51 +0800
category: 杂项
tags:
  - git
---

Git 中可以通过 `git checkout -- <file>...` 来撤销当前工作空间的修改。例如，我们有以下文件已经做出了修改：

```
$ git status
On branch hunghudb-11.3beta
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git checkout -- <file>..." to discard changes in working directory)

        modified:   src/backend/postmaster/pgstat.c
        modified:   src/backend/replication/logical/reorderbuffer.c
        modified:   src/backend/storage/file/buffile.c
        modified:   src/include/pgstat.h
        modified:   src/include/replication/reorderbuffer.h
        modified:   src/include/storage/buffile.h
```

如果此时我想要撤销这些修改，我们应该怎么做呢？

<!-- more -->

最简单的方法是针对每个文件，我们可以使用下面的命令进行撤销：

```
$ git checkout -- src/backend/postmaster/pgstat.c
```


下面的命令通过将 `git` 与 shell 结合使用，更为方便快捷。

```
$ git checkout -- $(git status -s | grep '^ M' | cut -d' ' -f 3)
```

此外，我们还可以使用 `git checkout .` 命令来撤销所有修改。

```
$ git checkout -- '*.c'
```

上面的命令可以撤销所有对 C 源文件的修改。


## 参考

[1] https://git-scm.com/docs/git-checkout
