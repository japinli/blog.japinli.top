---
title: "MacOS Mojave 上 GDB 调试配置"
date: 2019-06-22 15:45:06 +0800
category: Misc
tags:
  - MacOS
  - gdb
---

最近在 MacOS 上写代码，需要使用 gdb 进行调试，踩了一些坑，因此在这里做一个简要记录。稍微搜索一下我们就可以知道要在 MacOS 上使用 gdb 需要先创建一个自签名证书（[看这里](https://gist.github.com/gravitylow/fb595186ce6068537a6e9da6d8b5b96d))。

但是我们在 Mojave 上按照文章给出的方式进行，还是出现下面的错误。

```
Unable to find Mach task port for process-id 432: (os/kern) failure (0x5).
 (please check gdb is codesigned - see taskgated(8))
```

在这个过程中，我还遇到了不能创建系统证书的问题。

<!-- more -->

## 解决方法

首先，系统证书的问题可以通过先创建一个登陆证书，然后将其拖拽到系统条目下即可。那么证书的问题就可以解决了，原以为就可以高高兴兴的调试代码了，可是发现还是出现 `Unable to find Mach task ...` 错误。

> 1. Open Keychain Access
> 2. In menu, open Keychain Access > Certificate Assistant > Create a certificate
> 3. Give it a name (e.g. gdbc)
>    * Identity type: Self Signed Root
>    * Certificate type: Code Signing
>    * Check: let me override defaults
> 4. Continue until "specify a location for..."
> 5. Set Keychain location to System
> 6. Create certificate and close Certificate Assistant.
> 7. Find certificate in System keychain.
> 8. Double click certificate
> 9. Expand Trust, set Code signing to always trust
> 10. Restart taskgated in terminal: `killall taskgated`


实际上我们在上面的步骤 7 是选择的 `Login` 而非 `System`，在证书创建成功之后在将其拖拽到 `System` 类别下的。我只执行到了步骤 10，之后的步骤便没有继续执行。而是使用下面的方式，

原来是代码签署权利的问题。原文如下：

> This is related to codesign entitlements. you must add "com.apple.security.cs.debugger" key in signing process.
>
> for example you must change `codesign -fs gdbcert /usr/local/bin/gdb` to `codesign --entitlements gdb.xml -fs gdbcert /usr/local/bin/gdb`.
>
> `gdb.xml` content must something like following code.
>
> ```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.debugger</key>
    <true/>
</dict>
</plist>
> ```

因此，我们在使用 `codesign` 时采用了如下命令：

```
$ cat gdb.xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.debugger</key>
    <true/>
</dict>
</plist>
$ codesign --entitlements gdb.xml -fs gdbcert /usr/local/bin/gdb
```

按照上面命令执行之后，果然能愉快的使用 gdb 了。

## 参考

[1] https://gist.github.com/gravitylow/fb595186ce6068537a6e9da6d8b5b96d
[2] https://stackoverflow.com/questions/52699661/macos-mojave-how-to-achieve-codesign-to-enable-debugging-gdb
