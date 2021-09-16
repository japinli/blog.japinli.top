---
title: "MacOS 上创建 U 盘启动器"
date: 2020-07-26 17:04:51 +0800
category: 杂项
tags:
  - MacOS
---

本文记载了如何在 MacOS 平台制作 U 盘安装镜像，这里主要使用到了 hdiutil，diskutil 和 dd 三个命令。

<!-- more -->

我们在官网现在的镜像大都是以 iso 结尾的文件，例如，本文中使用的 ubuntu-16.04-server-amd64.iso 镜像，在 Linux 平台，我们可以直接使用 dd 将这个镜像写到 U 盘上即可作为启动盘，但是在 MacOS 平台上，则需要将 iso 文件转换为 dmg 格式。

``` shell
$ hdiutil convert -format UDRW ubuntu-16.04-server-amd64.iso -o ubuntu-16.04-server-amd64.img
Reading Master Boot Record (MBR : 0)…
Reading Ubuntu-Server 18.04.4 LTS arm64  (Apple_ISO : 1)…
Reading  (Type CD : 2)…
....................................................................................................
Reading  (Type EF : 3)…
....................................................................................................
Elapsed Time:  2.094s
Speed: 454.9Mbytes/sec
Savings: 0.0%
created: /Users/japin/Downloads/ubuntu-18.04.4-server-arm64.img.dmg
```

从上面的命令我们可以看到，文件将自动加上 dmg 后缀。上面的命令将 ubuntu-16.04-server-amd64.iso 镜像转换为 UDRW 格式并存储到 ubuntu-16.04-server-amd64.img.dmg 文件中。

接下来我们通过 diskutil 命令查看当前 U 盘的位置。

``` shell
$ diskutil list
/dev/disk0 (internal, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *251.0 GB   disk0
   1:                        EFI EFI                     314.6 MB   disk0s1
   2:                 Apple_APFS Container disk1         250.7 GB   disk0s2

/dev/disk1 (synthesized):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      APFS Container Scheme -                      +250.7 GB   disk1
                                 Physical Store disk0s2
   1:                APFS Volume Macintosh HD            11.1 GB    disk1s1
   2:                APFS Volume Macintosh HD - Data     76.8 GB    disk1s2
   3:                APFS Volume Preboot                 81.3 MB    disk1s3
   4:                APFS Volume Recovery                528.1 MB   disk1s4
   5:                APFS Volume VM                      3.2 GB     disk1s5

/dev/disk2 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     Apple_partition_scheme                        *8.1 GB     disk2
   1:        Apple_partition_map                         4.1 KB     disk2s1
   2:                  Apple_HFS                         2.5 MB     disk2s2
```

可以看到，我们的 U 盘对应的是 `/dev/disk2`，使用下面的命令卸载 U 盘。

```shell
$ diskutil unmountDisk /dev/disk2
Unmount of all volumes on disk2 was successful
```

最后，使用 dd 命令将其写入到 U 盘中，这里需要注意我们的 U 盘设备名应使用 `/dev/rdisk2`，即在 `/dev/disk2` 的磁盘名前面加上 `r` 字母。

``` shell
$ sudo dd if=ubuntu-18.04.4-server-arm64.img.dmg of=/dev/rdisk2 bs=1m
```
