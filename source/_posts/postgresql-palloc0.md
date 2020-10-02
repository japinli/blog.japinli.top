---
title: "PostgreSQL palloc0 函数优化"
date: 2020-10-02 22:45:16 +0800
category: 数据库
tags:
  - PostgreSQL
  - 源码分析
---

最近在查看 PostgreSQL 数据库中内存分配相关的代码时，我发现 `palloc()` 和 `palloc0()` 函数存在大量的冗余代码。本着减少冗余代码的想法，我将修改后的代码提交到社区，得到的反馈是这样修改会影响整体效率。本文简要分析一下这是如何影响效率的。

<!-- more -->

## PATCH 文件

我提交的 PATCH 文件如下所示，其实非常简单，本质上就是将 `palloc0()` 函数中的部分代码改由 `palloc()` 函数来实现。

```diff
diff --git a/src/backend/utils/mmgr/mcxt.c b/src/backend/utils/mmgr/mcxt.c
index dda70ef9f3..cb07958a1f 100644
--- a/src/backend/utils/mmgr/mcxt.c
+++ b/src/backend/utils/mmgr/mcxt.c
@@ -982,28 +982,8 @@ palloc0(Size size)
 {
 	/* duplicates MemoryContextAllocZero to avoid increased overhead */
 	void	   *ret;
-	MemoryContext context = CurrentMemoryContext;
-
-	AssertArg(MemoryContextIsValid(context));
-	AssertNotInCriticalSection(context);

-	if (!AllocSizeIsValid(size))
-		elog(ERROR, "invalid memory alloc request size %zu", size);
-
-	context->isReset = false;
-
-	ret = context->methods->alloc(context, size);
-	if (unlikely(ret == NULL))
-	{
-		MemoryContextStats(TopMemoryContext);
-		ereport(ERROR,
-				(errcode(ERRCODE_OUT_OF_MEMORY),
-				 errmsg("out of memory"),
-				 errdetail("Failed on request of size %zu in memory context \"%s\".",
-						   size, context->name)));
-	}
-
-	VALGRIND_MEMPOOL_ALLOC(context, ret, size);
+	ret = palloc(size);

 	MemSetAligned(ret, 0, size);
```

## 分析

在 Alvaro Herrera 的指导下，我通过分析原始代码和修改后代码的汇编代码进行分析。原版 PostgreSQL 数据库 `palloc()` 和 `palloc0()` 的汇编代码如下：

```
00000000005175b0 <palloc>:
  5175b0:	55                   	push   %rbp
  5175b1:	53                   	push   %rbx
  5175b2:	48 89 fd             	mov    %rdi,%rbp
  5175b5:	48 83 ec 08          	sub    $0x8,%rsp
  5175b9:	48 81 ff ff ff ff 3f 	cmp    $0x3fffffff,%rdi
  5175c0:	48 8b 1d b9 0d 48 00 	mov    0x480db9(%rip),%rbx        # 998380 <CurrentMemoryContext>
  5175c7:	0f 87 85 00 00 00    	ja     517652 <palloc+0xa2>
  5175cd:	48 8b 43 10          	mov    0x10(%rbx),%rax
  5175d1:	48 89 fe             	mov    %rdi,%rsi
  5175d4:	c6 43 04 00          	movb   $0x0,0x4(%rbx)
  5175d8:	48 89 df             	mov    %rbx,%rdi
  5175db:	ff 10                	callq  *(%rax)
  5175dd:	48 85 c0             	test   %rax,%rax
  5175e0:	74 0e                	je     5175f0 <palloc+0x40>
  5175e2:	48 83 c4 08          	add    $0x8,%rsp
  5175e6:	5b                   	pop    %rbx
  5175e7:	5d                   	pop    %rbp
  5175e8:	c3                   	retq
  5175e9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  5175f0:	48 8b 3d 81 0d 48 00 	mov    0x480d81(%rip),%rdi        # 998378 <TopMemoryContext>
  5175f7:	be 64 00 00 00       	mov    $0x64,%esi
  5175fc:	e8 4f fa ff ff       	callq  517050 <MemoryContextStatsDetail>
  517601:	31 f6                	xor    %esi,%esi
  517603:	bf 14 00 00 00       	mov    $0x14,%edi
  517608:	e8 83 6e fd ff       	callq  4ee490 <errstart>
  51760d:	bf c5 20 00 00       	mov    $0x20c5,%edi
  517612:	e8 c9 9c fd ff       	callq  4f12e0 <errcode>
  517617:	48 8d 3d 37 55 03 00 	lea    0x35537(%rip),%rdi        # 54cb55 <__func__.7554+0x45>
  51761e:	31 c0                	xor    %eax,%eax
  517620:	e8 db 9e fd ff       	callq  4f1500 <errmsg>
  517625:	48 8b 53 38          	mov    0x38(%rbx),%rdx
  517629:	48 8d 3d b0 12 16 00 	lea    0x1612b0(%rip),%rdi        # 6788e0 <__func__.6248+0x150>
  517630:	48 89 ee             	mov    %rbp,%rsi
  517633:	31 c0                	xor    %eax,%eax
  517635:	e8 86 a3 fd ff       	callq  4f19c0 <errdetail>
  51763a:	48 8d 15 37 13 16 00 	lea    0x161337(%rip),%rdx        # 678978 <__func__.7318>
  517641:	48 8d 3d 50 12 16 00 	lea    0x161250(%rip),%rdi        # 678898 <__func__.6248+0x108>
  517648:	be cc 03 00 00       	mov    $0x3cc,%esi
  51764d:	e8 3e 96 fd ff       	callq  4f0c90 <errfinish>
  517652:	31 f6                	xor    %esi,%esi
  517654:	bf 14 00 00 00       	mov    $0x14,%edi
  517659:	e8 32 6e fd ff       	callq  4ee490 <errstart>
  51765e:	48 8d 3d 0b 12 16 00 	lea    0x16120b(%rip),%rdi        # 678870 <__func__.6248+0xe0>
  517665:	48 89 ee             	mov    %rbp,%rsi
  517668:	31 c0                	xor    %eax,%eax
  51766a:	e8 c1 99 fd ff       	callq  4f1030 <errmsg_internal>
  51766f:	48 8d 15 02 13 16 00 	lea    0x161302(%rip),%rdx        # 678978 <__func__.7318>
  517676:	48 8d 3d 1b 12 16 00 	lea    0x16121b(%rip),%rdi        # 678898 <__func__.6248+0x108>
  51767d:	be c0 03 00 00       	mov    $0x3c0,%esi
  517682:	e8 09 96 fd ff       	callq  4f0c90 <errfinish>
  517687:	66 0f 1f 84 00 00 00 	nopw   0x0(%rax,%rax,1)
  51768e:	00 00

0000000000517690 <palloc0>:
  517690: 55                    push   %rbp
  517691: 53                    push   %rbx
  517692: 48 89 fb              mov    %rdi,%rbx
  517695: 48 83 ec 08           sub    $0x8,%rsp
  517699: 48 81 ff ff ff ff 3f  cmp    $0x3fffffff,%rdi
  5176a0: 48 8b 2d d9 0c 48 00  mov    0x480cd9(%rip),%rbp        # 998380 <CurrentMemoryContext>
  5176a7: 0f 87 d5 00 00 00     ja     517782 <palloc0+0xf2>
  5176ad: 48 8b 45 10           mov    0x10(%rbp),%rax
  5176b1: 48 89 fe              mov    %rdi,%rsi
  5176b4: c6 45 04 00           movb   $0x0,0x4(%rbp)
  5176b8: 48 89 ef              mov    %rbp,%rdi
  5176bb: ff 10                 callq  *(%rax)
  5176bd: 48 85 c0              test   %rax,%rax
  5176c0: 48 89 c1              mov    %rax,%rcx
  5176c3: 74 5b                 je     517720 <palloc0+0x90>
  5176c5: f6 c3 07              test   $0x7,%bl
  5176c8: 75 36                 jne    517700 <palloc0+0x70>
  5176ca: 48 81 fb 00 04 00 00  cmp    $0x400,%rbx
  5176d1: 77 2d                 ja     517700 <palloc0+0x70>
  5176d3: 48 01 c3              add    %rax,%rbx
  5176d6: 48 39 d8              cmp    %rbx,%rax
  5176d9: 73 35                 jae    517710 <palloc0+0x80>
  5176db: 0f 1f 44 00 00        nopl   0x0(%rax,%rax,1)
  5176e0: 48 83 c0 08           add    $0x8,%rax
  5176e4: 48 c7 40 f8 00 00 00  movq   $0x0,-0x8(%rax)
  5176eb: 00
  5176ec: 48 39 c3              cmp    %rax,%rbx
  5176ef: 77 ef                 ja     5176e0 <palloc0+0x50>
  5176f1: 48 83 c4 08           add    $0x8,%rsp
  5176f5: 48 89 c8              mov    %rcx,%rax
  5176f8: 5b                    pop    %rbx
  5176f9: 5d                    pop    %rbp
  5176fa: c3                    retq
  5176fb: 0f 1f 44 00 00        nopl   0x0(%rax,%rax,1)
  517700: 48 89 cf              mov    %rcx,%rdi
  517703: 48 89 da              mov    %rbx,%rdx
  517706: 31 f6                 xor    %esi,%esi
  517708: e8 e3 0e ba ff        callq  b85f0 <memset@plt>
  51770d: 48 89 c1              mov    %rax,%rcx
  517710: 48 83 c4 08           add    $0x8,%rsp
  517714: 48 89 c8              mov    %rcx,%rax
  517717: 5b                    pop    %rbx
  517718: 5d                    pop    %rbp
  517719: c3                    retq
  51771a: 66 0f 1f 44 00 00     nopw   0x0(%rax,%rax,1)
  517720: 48 8b 3d 51 0c 48 00  mov    0x480c51(%rip),%rdi        # 998378 <TopMemoryContext>
  517727: be 64 00 00 00        mov    $0x64,%esi
  51772c: e8 1f f9 ff ff        callq  517050 <MemoryContextStatsDetail>
  517731: 31 f6                 xor    %esi,%esi
  517733: bf 14 00 00 00        mov    $0x14,%edi
  517738: e8 53 6d fd ff        callq  4ee490 <errstart>
  51773d: bf c5 20 00 00        mov    $0x20c5,%edi
  517742: e8 99 9b fd ff        callq  4f12e0 <errcode>
  517747: 48 8d 3d 07 54 03 00  lea    0x35407(%rip),%rdi        # 54cb55 <__func__.7554+0x45>
  51774e: 31 c0                 xor    %eax,%eax
  517750: e8 ab 9d fd ff        callq  4f1500 <errmsg>
  517755: 48 8b 55 38           mov    0x38(%rbp),%rdx
  517759: 48 8d 3d 80 11 16 00  lea    0x161180(%rip),%rdi        # 6788e0 <__func__.6248+0x150>
  517760: 48 89 de              mov    %rbx,%rsi
  517763: 31 c0                 xor    %eax,%eax
  517765: e8 56 a2 fd ff        callq  4f19c0 <errdetail>
  51776a: 48 8d 15 ff 11 16 00  lea    0x1611ff(%rip),%rdx        # 678970 <__func__.7326>
  517771: 48 8d 3d 20 11 16 00  lea    0x161120(%rip),%rdi        # 678898 <__func__.6248+0x108>
  517778: be eb 03 00 00        mov    $0x3eb,%esi
  51777d: e8 0e 95 fd ff        callq  4f0c90 <errfinish>
  517782: 31 f6                 xor    %esi,%esi
  517784: bf 14 00 00 00        mov    $0x14,%edi
  517789: e8 02 6d fd ff        callq  4ee490 <errstart>
  51778e: 48 8d 3d db 10 16 00  lea    0x1610db(%rip),%rdi        # 678870 <__func__.6248+0xe0>
  517795: 48 89 de              mov    %rbx,%rsi
  517798: 31 c0                 xor    %eax,%eax
  51779a: e8 91 98 fd ff        callq  4f1030 <errmsg_internal>
  51779f: 48 8d 15 ca 11 16 00  lea    0x1611ca(%rip),%rdx        # 678970 <__func__.7326>
  5177a6: 48 8d 3d eb 10 16 00  lea    0x1610eb(%rip),%rdi        # 678898 <__func__.6248+0x108>
  5177ad: be df 03 00 00        mov    $0x3df,%esi
  5177b2: e8 d9 94 fd ff        callq  4f0c90 <errfinish>
  5177b7: 66 0f 1f 84 00 00 00  nopw   0x0(%rax,%rax,1)
  5177be: 00 00
```

修改之后的汇编代码如下所示：

```
00000000005175b0 <palloc>:
  5175b0: 55                    push   %rbp
  5175b1: 53                    push   %rbx
  5175b2: 48 89 fd              mov    %rdi,%rbp
  5175b5: 48 83 ec 08           sub    $0x8,%rsp
  5175b9: 48 81 ff ff ff ff 3f  cmp    $0x3fffffff,%rdi
  5175c0: 48 8b 1d b9 0d 48 00  mov    0x480db9(%rip),%rbx        # 998380 <CurrentMemoryContext>
  5175c7: 0f 87 85 00 00 00     ja     517652 <palloc+0xa2>
  5175cd: 48 8b 43 10           mov    0x10(%rbx),%rax
  5175d1: 48 89 fe              mov    %rdi,%rsi
  5175d4: c6 43 04 00           movb   $0x0,0x4(%rbx)
  5175d8: 48 89 df              mov    %rbx,%rdi
  5175db: ff 10                 callq  *(%rax)
  5175dd: 48 85 c0              test   %rax,%rax
  5175e0: 74 0e                 je     5175f0 <palloc+0x40>
  5175e2: 48 83 c4 08           add    $0x8,%rsp
  5175e6: 5b                    pop    %rbx
  5175e7: 5d                    pop    %rbp
  5175e8: c3                    retq
  5175e9: 0f 1f 80 00 00 00 00  nopl   0x0(%rax)
  5175f0: 48 8b 3d 81 0d 48 00  mov    0x480d81(%rip),%rdi        # 998378 <TopMemoryContext>
  5175f7: be 64 00 00 00        mov    $0x64,%esi
  5175fc: e8 4f fa ff ff        callq  517050 <MemoryContextStatsDetail>
  517601: 31 f6                 xor    %esi,%esi
  517603: bf 14 00 00 00        mov    $0x14,%edi
  517608: e8 83 6e fd ff        callq  4ee490 <errstart>
  51760d: bf c5 20 00 00        mov    $0x20c5,%edi
  517612: e8 c9 9c fd ff        callq  4f12e0 <errcode>
  517617: 48 8d 3d 77 54 03 00  lea    0x35477(%rip),%rdi        # 54ca95 <__func__.7554+0x45>
  51761e: 31 c0                 xor    %eax,%eax
  517620: e8 db 9e fd ff        callq  4f1500 <errmsg>
  517625: 48 8b 53 38           mov    0x38(%rbx),%rdx
  517629: 48 8d 3d f0 11 16 00  lea    0x1611f0(%rip),%rdi        # 678820 <__func__.6248+0x150>
  517630: 48 89 ee              mov    %rbp,%rsi
  517633: 31 c0                 xor    %eax,%eax
  517635: e8 86 a3 fd ff        callq  4f19c0 <errdetail>
  51763a: 48 8d 15 6f 12 16 00  lea    0x16126f(%rip),%rdx        # 6788b0 <__func__.7318>
  517641: 48 8d 3d 90 11 16 00  lea    0x161190(%rip),%rdi        # 6787d8 <__func__.6248+0x108>
  517648: be cc 03 00 00        mov    $0x3cc,%esi
  51764d: e8 3e 96 fd ff        callq  4f0c90 <errfinish>
  517652: 31 f6                 xor    %esi,%esi
  517654: bf 14 00 00 00        mov    $0x14,%edi
  517659: e8 32 6e fd ff        callq  4ee490 <errstart>
  51765e: 48 8d 3d 4b 11 16 00  lea    0x16114b(%rip),%rdi        # 6787b0 <__func__.6248+0xe0>
  517665: 48 89 ee              mov    %rbp,%rsi
  517668: 31 c0                 xor    %eax,%eax
  51766a: e8 c1 99 fd ff        callq  4f1030 <errmsg_internal>
  51766f: 48 8d 15 3a 12 16 00  lea    0x16123a(%rip),%rdx        # 6788b0 <__func__.7318>
  517676: 48 8d 3d 5b 11 16 00  lea    0x16115b(%rip),%rdi        # 6787d8 <__func__.6248+0x108>
  51767d: be c0 03 00 00        mov    $0x3c0,%esi
  517682: e8 09 96 fd ff        callq  4f0c90 <errfinish>
  517687: 66 0f 1f 84 00 00 00  nopw   0x0(%rax,%rax,1)
  51768e: 00 00

0000000000517690 <palloc0>:
  517690: 53                    push   %rbx
  517691: 48 89 fb              mov    %rdi,%rbx
  517694: e8 17 ff ff ff        callq  5175b0 <palloc>
  517699: f6 c3 07              test   $0x7,%bl
  51769c: 48 89 c1              mov    %rax,%rcx
  51769f: 75 2f                 jne    5176d0 <palloc0+0x40>
  5176a1: 48 81 fb 00 04 00 00  cmp    $0x400,%rbx
  5176a8: 77 26                 ja     5176d0 <palloc0+0x40>
  5176aa: 48 01 c3              add    %rax,%rbx
  5176ad: 48 39 d8              cmp    %rbx,%rax
  5176b0: 73 2e                 jae    5176e0 <palloc0+0x50>
  5176b2: 66 0f 1f 44 00 00     nopw   0x0(%rax,%rax,1)
  5176b8: 48 83 c0 08           add    $0x8,%rax
  5176bc: 48 c7 40 f8 00 00 00  movq   $0x0,-0x8(%rax)
  5176c3: 00
  5176c4: 48 39 c3              cmp    %rax,%rbx
  5176c7: 77 ef                 ja     5176b8 <palloc0+0x28>
  5176c9: 48 89 c8              mov    %rcx,%rax
  5176cc: 5b                    pop    %rbx
  5176cd: c3                    retq
  5176ce: 66 90                 xchg   %ax,%ax
  5176d0: 48 89 cf              mov    %rcx,%rdi
  5176d3: 48 89 da              mov    %rbx,%rdx
  5176d6: 31 f6                 xor    %esi,%esi
  5176d8: e8 13 0f ba ff        callq  b85f0 <memset@plt>
  5176dd: 48 89 c1              mov    %rax,%rcx
  5176e0: 48 89 c8              mov    %rcx,%rax
  5176e3: 5b                    pop    %rbx
  5176e4: c3                    retq
  5176e5: 90                    nop
  5176e6: 66 2e 0f 1f 84 00 00  nopw   %cs:0x0(%rax,%rax,1)
  5176ed: 00 00 00
```

从上面的汇编代码可以看到修改后的 `palloc0()` 额外引入了更多的汇编指令，从而导致其运行效率有所降低，由于该函数属于底层函数，很多地方都会调用该函数。因此对整体数据库的性能影响较大。当然，这只是从汇编指令级别得到的理论结果，我们还可以通过实际测试来进行对比。

## 链接

[1] https://www.postgresql.org/message-id/flat/3A57E434-BB2C-420C-86C8-0A81AE23F679%40hotmail.com


<div class="just-for-fun">
笑林广记 - 小恭五两

讹诈得财，蜀人谓之敲钉锤。
一广文善敲钉锤，见一生员在泮池旁出小恭，上前扭住吓之曰：“尔身列学门，擅在泮池解手，无礼已极。”
饬门斗：“押至明伦堂重惩，为大不敬者戒。”
生员央之曰：“生员一时错误，情愿认罚。”
广文云：“好在是出小恭，若是出大恭，定罚银十两。小恭五两可也。”
生员曰：“我这身边带银一块，重十两，愿分一半奉送。”
广文云：“何必分，全给了我就是了。”
生员说：“老师讲明，小恭五两，因何又要十两？”
广文曰：“不妨，你尽管全给了我，以后准你泮池旁再出大恭一次，让你五两。千万不可与外人说，恐坏了我的学规。”
</div>
