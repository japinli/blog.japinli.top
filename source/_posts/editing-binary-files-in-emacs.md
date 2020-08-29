---
title: "Emacs 编辑二进制文件"
date: 2018-10-16 22:00:23 +0800
category: 杂项
tags:
  - Emacs
---

二进制文件是以二进制格式存储的文件，它是计算机可读的，人类不直接阅读二进制文件。所有的可执行程序都以二进制文件存储。那我们该如何编辑二进制文件呢？在我使用的 Emacs 编辑器中提供了一个 hexl-mode 的主模式来编辑二进制文件。本文记录了 Emacs 中编辑二进制文件的基本操作。

{% asset_img Editing_Binary_File.png Editing Binary File %}

<!-- more -->

### 打开

我们可以使用 `M-x hexl-find-file` 取代 `C-x C-f` 命令来编辑二进制文件，该命令将文件内容转换为十六进制，并允许用户进行编辑。当用户保存文件时，它将会自动转换为二进制格式。

当然，我们也可以使用 `M-x hexl-mode** 来将现有的缓冲区转换为十六进制，这在以普通方式打开二进制文件时非常有用。

### 编辑

普通文本字符在 hexl-mode 下被覆盖。这是为了降低意外破坏文件中数据对齐的风险。针对二进制文件，hexl-mode 有特殊的插入命令。以下是 hexl-mode 的命令列表：

- **C-M-d** 插入一个包含十进制代码的字节。
- **C-M-o** 插入一个包含八进制代码的字节。
- **C-M-x** 插入一个包含十六进制代码的字节。
- **C-M-[** 移动到 1k 字节页面的开头。
- **C-M-]** 移动到 1k 字节页面的结尾。
- **M-g** 移至以十六进制指定的地址。
- **M-j** 移至以十进制指定的地址。
- **C-c C-c** 退出 hexl-mode，返回调用 hexl-mode 之前返回此缓冲区的主模式。


### 参考

[1] https://www.webopedia.com/TERM/B/binary_file.html
[2] https://www.gnu.org/software/emacs/manual/html_node/emacs/Editing-Binary-Files.html
