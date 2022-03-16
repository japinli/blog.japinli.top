---
title: "申威平台 float 到 short 类型转换的编译器优化问题"
date: 2022-02-26 00:04:01 +0800
categories: 杂项
tags:
  - Sunway
  - Compiler
  - BUG
---

最近在做申威平台的兼容时发现一个关于编译器优化的 BUG。第一次遇到编译器优化的问题，因此在这里对其进行简要的记录。

<!--more-->

## 环境

下面是此次主角的基本信息，包括 CPU 硬件、操作系统和 GCC 编译器信息。

```shell
$ lscpu
架构：           sw_64
CPU 运行模式：   64-bit
字节序：         Little Endian
Address sizes:   48 bits physical, 53 bits virtual
CPU:             64
在线 CPU 列表：  0-63
每个核的线程数： 1
每个座的核数：   32
座：             2
NUMA 节点：      2
厂商 ID：        sunway
CPU 系列：       6
型号：           49
型号名称：       SW3231 CPU @ 2.40GHz
CPU MHz：        2400.00
BogoMIPS：       4800.00
L1d 缓存：       2 MiB
L1i 缓存：       2 MiB
L2 缓存：        32 MiB
L3 缓存：        64 MiB
NUMA 节点0 CPU： 0-31
NUMA 节点1 CPU： 32-63
标记：           fpu simd vpn upn cpuid

$ uname -a
Linux localhost.localdomain 4.19.90-25.0.v2101.ky10.sw_64 #1 SMP Wed Jun 16 18:08:09 CST 2021 sw_64 sw_64 sw_64 GNU/Linux

$ gcc --version
gcc (GCC) 8.3.0 20190222 (Kylin 8.3.0-4)
Copyright (C) 2018 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

## 问题

这个问题是在进行数据库产品兼容互认证的时候发现的。我当时采用 `-O2` 在该平台上编译代码，随后跑回归测试，发现回归测试失败，其中一条信息如下所示：

```diff
 -- test edge-case coercions to integer
 SELECT '32767.4'::float4::int2;
- int2
--------
- 32767
-(1 row)
+ERROR:  smallint out of range
```

这就很奇怪了，为什么超出了范围呢？这个代码在 x86 平台上是可以正常通过的啊！！！于是乎我尝试使用 `-O0` 来编译想要调试一下，在调试之前，我跑了一下回归测试，发现居然通过了！怎么回事？是我哪儿搞错了吗？我再次尝试 `-O2` 优化，回归测试依然不过。既然 `-O0` 编译是正常的那么调试这个版本就没有意义了，为此我使用 `-O2 -g` 来编译并对其进行调试，发现其在执行 `rint()` 函数的时候出现了异常，如下所示：

```gdb
1317    ftoi2(PG_FUNCTION_ARGS)
1318    {
1319    	float4	num = PG_GETARG_FLOAT4(0);
1320
1321    	/*
1322    	 * Get rid of any fractional part in the input.  This is so we don't fail
(gdb) n
1326    	num = rint(num);
(gdb) p num
$15 = 32767.4004
(gdb) n
1329    	if (unlikely(isnan(num) || !FLOAT4_FITS_IN_INT16(num)))
(gdb) p num
$15 = 32768
```

上面出现了异常，正常情况下调用了 `rint()` 函数之后应该返回 `32767`，然而这里却返回了 `32768`。

为了方便申威那边的人员调试，我将这个用例进行了简化，最开始我是直接调用 `rint()` 函数（如下所示），发现这样做并不能重现这个问题。

```shell
$ cat test.c
#include <stdio.h>
#include <math.h>

int
main(void)
{
    float num = 32767.4;
    float t = rint(num);
    printf("rint(%f) = %d\n", num, (short) t);
    return 0;
}
$ gcc -O2 -g -o t2 test.c -lm
$ ./t2
rint(32767.400391) = 32767

$ gcc -O0 -g -o t0 test.c -lm
$ ./t0
rint(32767.400391) = 32767
```

上面的测试一切都是正常的。为什么在我们的数据库代码中就不行呢？考虑到数据库的代码是通过函数调用的，因此我将其封装成函数调用来进行测试。

```shell
$ cat test.c
#include <stdio.h>
#include <math.h>

void
ftoi2(float num)
{
    float t = rint(num);
    printf("rint(%f) = %d\n", num, (short) t);
}

int
main(void)
{
    ftoi2(32767.4);
    return 0;
}

$ gcc -O2 -g -o t2 test.c -lm
$ ./t2
rint(32767.400391) = -32768

$ gcc -O0 -g -o t0 test.c -lm
$ ./t0
rint(32767.400391) = 32767
```

是不是很神奇！！！反正我是被惊艳到了。现在，问题得到复现了，从上面的结果来看，可以肯定的是申威平台上的 GCC 编译器优化存在问题，从而导致了计算结果错误。看到这里，我就没办法继续深入下去了，主要还是由于对申威平台不了解、不熟悉他的汇编指令，因此，我将这个问题转给了申威的人继续跟踪，期待这个问题能早日解决。

当前主流的趋势是国产替代，然而我们还是应该要认识到自身与西方国家差距，不能光靠 PPT。只有当潮水退去时，您才知道谁一直在裸泳。希望国产软件不是那个一直裸泳的。

<div class="just-for-fun">
笑林广记 - 监生娘娘

监生至城隍庙，傍有监生案，塑监生娘娘像。
归谓妻曰：“原来我们监生恁般尊贵，连你的像，早已都塑在城隍庙里了。”
</div>
