---
title: "小米路由器刷 Breed 和 Padavan 固件"
date: 2020-07-12 14:06:41 +0800
category: 杂项
tags:
  - R3G
  - breed
  - padavan
---

本文主要记录一下小米路由器 3G 刷 breed 和 padavan 的过程。

* [Breed](https://openwrt.org/docs/techref/bootloader/breed) 是嵌入式设备的引导和恢复环境的简称。
* Padavan 是由俄罗斯人基于华硕源码开发的针对 mtk 芯片的固件。

我将整个过程分为分为 5 个步骤，更新 ROM、开启 SSH、备份路由器、刷 breed、刷 padavan。

<!-- more -->

## 更新路由器 ROM

首先，我们需要将小米路由器的 ROM 更新为开发版，在小米的 [miwifi 下载页面](http://miwifi.com/miwifi_download.html)找到路由器对应的开发版 ROM（[R3G ROM 开发版](http://bigota.miwifi.com/xiaoqiang/rom/r3g/miwifi_r3g_firmware_12f97_2.25.124.bin)）。

ROM 的升级有两种方式：

1. 登陆路由器后台在线升级，我采用的这种方式，简单快捷。

2. 如果不行的话，可以将其拷贝到 U 盘根目录，并命名为 miwifi.bin。__随后断开电源，插上 U 盘，并按住 reset 按钮后插入电源，等到指示灯变为黄色闪烁状态后松开 reset 键，之后路由器将更新 ROM 并重启进入正常状态（指示灯变为蓝色常亮）。__

## 开启 SSH

接下来，我们开启路由器的 ssh 功能，在 [miwifi 开放](http://miwifi.com/miwifi_open.html) 找到__开启 SSH 工具__下载 miwifi_ssh.bin，这里需要使用小米账号对路由器进行绑定，绑定了之后小米会给出一个 root 用户的密码。

接着将下载的 miwifi_ssh.bin 拷贝到 U 盘根目录（__名称必须为 miwifi_ssh.bin__），如果之前是用 U 盘升级的 ROM，建议将 miwifi.bin 删除。

最后，将路由器断电，插上 U 盘，并按住 reset 按钮后插入电源，等到指示灯变为黄色闪烁状态后松开 reset 键，待蓝灯亮起时表示 ssh 开启完成。我们便可以使用 `ssh root@192.168.1.1` 登陆路由器了。

## 备份路由器

这个步骤我其实是没有做的，一开始我是按照[参考文献 [1]](https://blog.csdn.net/z619193774/article/details/81507917) 来做的，现在想想还是挺后怕的，这就是所谓的无知者无谓吧！登陆路由器后，我们使用下面的命令对路由器进行备份。

``` shell
$ ls /dev/sd*
$ mount /dev/sda1 /mnt # 找到属于你的 U 盘
$ for name in $(grep -v 'dev' /proc/mtd | awk -F ':' '{print $1}'); do dd if=/dev/$name of=/mnt/$name.bin; done
```

## 刷 Breed

在 [Breed](https://breed.hackpascal.net/) 网址上找到对应的版本，小米路由器 R3G 对应的 breed 为 [breed-mt7621-xiaomi-r3g.bin](https://breed.hackpascal.net/breed-mt7621-xiaomi-r3g.bin)。然后将其通过 `scp` 拷贝到路由器上。

``` shell
$ scp breed-mt7621-xiaomi-r3g.bin root@192.168.1.1:/tmp/
```

随后登陆到小米路由器，执行下面的命令刷入 breed：

``` shell
$ mtd -r write /tmp/breed-mt7621-xiaomi-r3g.bin Bootloader
```

刷入成功后，路由器将会重启，等到重启完成之后，拔掉电源，按住 reset 按钮，插电开机，等到路由器蓝灯闪烁时，在浏览器中输入 192.168.1.1，就可以进入 breed 的控制台了。

在 breed 控制台中，选择__固件备份__，备份 EEPRO 和编程固件，这样我们可以在之后刷回原来的系统。


## 刷 Padavan 固件

在 [Padavan](http://opt.cn2qq.com/padavan/) 下载页面下载小米路由器 R3G 版本 [MI-R3G_3.4.3.9-099.trx](http://opt.cn2qq.com/padavan/MI-R3G_3.4.3.9-099.trx)。登陆 breed，在__固件更新__中选择__固件__，随后浏览本地文件选择我们下载的 MI-R3G_3.4.3.9-099.trx 文件，点击上传，上传成功之后将自动更新固件，最后完成之后，我们可以通过访问 192.168.123.1 来登陆 padavan，用户名和密码默均为 `admin`，初始化的 wifi 名称为 `PCDN` 和 `PCDN_5G`，密码为 `1234567890`。

{% asset_img padavan.jpg Padavan 管理界面 %}

## 注意

* 在上文中使用的 U 盘需为 FAT/FTA32 格式化的。
* 可能需要使用网线连接路由器进行配置。

## 参考文献

[1] https://blog.csdn.net/z619193774/article/details/81507917
[2] https://schaepher.github.io/2019/10/12/xiaomi-router-r3-openwrt/
