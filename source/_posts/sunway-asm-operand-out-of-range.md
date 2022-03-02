---
title: "申威编译器优化指令操作数越界问题"
date: 2022-03-02 22:47:42 +0800
categories: 杂项
tags:
  - Sunway
  - Compiler
---

申威上面的编译器问题看来还不少，{% post_link sunway-float-to-short-compiler-bug 上一篇文章 %}说到了浮点型优化的问题，今天又遇到指令操作数越界的问题（虽然是个警告，但不排除可能存在其它隐含的问题）。

<!--more-->

<!-- git diff
diff --git a/src/include/storage/s_lock.h b/src/include/storage/s_lock.h
index 16ab2238e7..6c19749194 100644
--- a/src/include/storage/s_lock.h
+++ b/src/include/storage/s_lock.h
@@ -738,6 +738,49 @@ do \
 #endif /* __loongarch__ */


+#if defined(__sw_64) || defined(__sw_64__)	/* Sunway */
+#define HAS_TEST_AND_SET
+
+typedef unsigned long slock_t;
+
+#define TAS(lock) tas(lock)
+
+static __inline__ int
+tas(volatile slock_t *lock)
+{
+	register slock_t _res;
+	unsigned long tmp1;
+	__asm__ __volatile__(
+		"   ldl     $0, %1     \n"
+		"   bne     $0, 2f     \n"
+		"   lldl    %0, %1     \n"
+		"   cmpeq   %0, 0, %2  \n"
+		"   wr_f    %2         \n"
+		"   mov     %2, $0     \n"
+		"   lstl    $0, %1     \n"
+		"   rd_f    $0         \n"
+		"   beq     %2, 2f     \n"
+		"   beq     $0, 2f     \n"
+		"   memb               \n"
+		"   br      3f         \n"
+		"2: mov     1, %0      \n"
+		"3:                    \n"
+:       "=&r"(_res), "+m"(*lock), "=&r"(tmp1)
+:       /* no inputs */
+:       "memory", "0");
+	return (int) _res;
+}
+
+#define S_UNLOCK(lock)	\
+do \
+{ \
+	__asm__ __volatile__ ("memb \n"); \
+	*((volatile slock_t *) (lock)) = 0; \
+} while (0)
+
+#endif /* __sw_64 || __sw_64__ */
+
+
 #if defined(__m32r__) && defined(HAVE_SYS_TAS_H)	/* Renesas' M32R */
 #define HAS_TEST_AND_SET
-->

## 现象

环境与上篇文章提到的一致，在做申威平台的兼容时，采用嵌入式汇编实现 spinlock 时，开启 `-O2` 优化遇到了 `operand out of range` 警告。

```shell
$ gcc -S -Wall -Wmissing-prototypes -Wpointer-arith -Wdeclaration-after-statement -Werror=vla -Wendif-labels -Wmissing-format-attribute -Wimplicit-fallthrough=3 -Wcast-function-type -Wformat-security -fno-strict-aliasing -fwrapv -fexcess-precision=standard -Wno-format-truncation -Wno-stringop-truncation -O2 -I. -I/mnt/nvme0n1/postgres-14.2/build/../src/backend/replication -I../../../src/include -I/mnt/nvme0n1/postgres-14.2/build/../src/include  -D_GNU_SOURCE   -c -o walreceiverfuncs.s /mnt/nvme0n1/postgres-14.2/build/../src/backend/replication/walreceiverfuncs.c

$ gcc -Wall -Wmissing-prototypes -Wpointer-arith -Wdeclaration-after-statement -Werror=vla -Wendif-labels -Wmissing-format-attribute -Wimplicit-fallthrough=3 -Wcast-function-type -Wformat-security -fno-strict-aliasing -fwrapv -fexcess-precision=standard -Wno-format-truncation -Wno-stringop-truncation -O2 -I. -I/mnt/nvme0n1/postgres-14.2/build/../src/backend/replication -I../../../src/include -I/mnt/nvme0n1/postgres-14.2/build/../src/include  -D_GNU_SOURCE   -c -o walreceiverfuncs.o walreceiverfuncs.s
walreceiverfuncs.s: Assembler messages:
walreceiverfuncs.s:229: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:233: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:303: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:307: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:396: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:400: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:484: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:488: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:575: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:579: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:759: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:763: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:932: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:936: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:1053: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:1057: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:1159: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)
walreceiverfuncs.s:1163: 警告：operand out of range (0x00000000000008c0 is not between 0xfffffffffffff800 and 0x00000000000007ff)

$ sed -n 229,233p walreceiverfuncs.s
   lldl    $1, 2240($9)
   cmpeq   $1, 0, $2
   wr_f    $2
   mov     $2, $0
   lstl    $0, 2240($9)
   rd_f    $0
```

从警告信息来看，操作数的取值范围为 `[-2048, 2047]`，而实际上 `lldl $1, 2240($9)` 和 `lstl $0, 2240($9)` 这两个的取值已经超过了这个范围，从而导致警告（我想知道的是为什么是警告，而不是错误）。
程序能正常编译出来，回归测试也能顺利通过，但是这个警告总是让人不放心，为此将这个问题同样地转给了申威的人，希望他们能给出回答。

<div class="just-for-fun">
笑林广记 - 王监生

一监生姓王，加纳知县到任。
初落学，青衿呈书，得牵牛章，讲诵之际，忽问那“王见之”是何人，答曰：“此王诵之之兄也。”
又问那“王曰”然是何人，答曰：“此王曰，叟之弟也。”
曰：“妙得紧。且喜我王氏一门，都在书上。”
</div>
