---
title: "Ubuntu - Barrier 鼠标消失"
date: 2023-12-18 13:50:47 +0800
categories: 杂项
tags:
  - Ubuntu
  - Barrier
---

{% asset_img barrier-cursor.jpg %}

最近在使用 [Barrier](https://github.com/debauchee/barrier) 时遇到了鼠标无法在 Ubuntu 上显示，实际上鼠标是从 MacOS 移动到了 Ubuntu 的，但是在 Ubuntu 上却无法正常显示，日志中包含如下信息：

```
[2023-12-18T13:52:07] WARNING: cursor may not be visible
```

<!--more-->

## 分析 & 解决

这个是由于 Wayland 导致的，可以通过禁用 Wayland 解决，如下所示：

```bash
$ echo "WaylandEnable=false" | sudo tee -a /etc/gdm3/custom.conf
$ sudo systemctl restart gdm3
```

注意：这会禁用手势功能，但您的 Barrier 鼠标能正常工作。

## 参考

[1] https://askubuntu.com/questions/1407275/mouse-disappears-while-using-barrier
[2] https://github.com/debauchee/barrier/issues/40

<div class="just-for-fun">
笑林广记 - 錾头

数人同舟，有撒屁者，众疑一童子，共錾其头。
童子哭曰：“阿弥陀佛，别人打我也罢了，亏那撒屁的乌龟担得这只手起，也来打我！”
</div>
