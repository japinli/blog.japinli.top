---
title: "申威平台 PostgreSQL 使用 LLVM 导致崩溃"
date: 2022-04-01 20:53:57 +0800
categories: 杂项
tags:
  - PostgreSQL
  - Sunway
  - LLVM
---

继{% post_link sunway-float-to-short-compiler-bug 浮点数溢出问题 %}和{% post_link sunway-asm-operand-out-of-range 汇编指令操作数越界问题%}之后，我又发现申威平台上一个关于 LLVM 的问题，这个直接导致数据库进程崩溃了，本文简要记录一下这个问题（之前反馈的问题到现在还没有得到回复 :( ，估计是太忙了吧），目前这个问题同样反馈给申威相关的人员了，期待能尽快得到解决。

<!--more-->

## 问题

既然是与 LLVM 相关，那么我们在编译 PostgreSQL 的时候需要指定 `--with-llvm` 选项，同时在初始化数据库之后开启 `jit`，这里就不赘述了。我们来看示例，首先创建两个表 `booltbl1` 和 `booltbl2`，并插入数据，如下所示：

```sql
CREATE TABLE booltbl1 (f1 bool);
INSERT INTO booltbl1 (f1) VALUES (bool 't');
INSERT INTO booltbl1 (f1) VALUES (bool 'True');
INSERT INTO BOOLTBL1 (f1) VALUES (bool 'true');

CREATE TABLE booltbl2 (f1 bool);
INSERT INTO booltbl2 (f1) VALUES (bool 'f');
INSERT INTO booltbl2 (f1) VALUES (bool 'false');
INSERT INTO booltbl2 (f1) VALUES (bool 'False');
INSERT INTO booltbl2 (f1) VALUES (bool 'FALSE');
```

接着，我们可以使用下面的查询重现 crash 线程。

```shell
postgres=# SELECT booltbl1.*, booltbl2.*
postgres-# FROM BOOLTBL1, BOOLTBL2
postgres-# WHERE BOOLTBL2.f1 <> BOOLTBL1.f1;
server closed the connection unexpectedly
This probably means the server terminated abnormally
before or while processing the request.
```

从上面可以看到后端进程崩溃了。

## 分析

通过 gdb 跟踪 crash 时的堆栈情况如下所示：

```
gdb) bt
#0  0x0000400029b83514 in llvm::RuntimeDyldELF::resolveSW64Relocation(llvm::SectionEntry const&, unsigned long, unsigned long, unsigned int, int) ()
   from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#1  0x0000400029b8832c in llvm::RuntimeDyldELF::resolveRelocation(llvm::SectionEntry const&, unsigned long, unsigned long, unsigned int, long, unsigned long, unsigned int) ()
   from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#2  0x0000400029b880a4 in llvm::RuntimeDyldELF::resolveRelocation(llvm::RelocationEntry const&, unsigned long) () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#3  0x0000400029b48e64 in llvm::RuntimeDyldImpl::resolveRelocationList(llvm::SmallVector<llvm::RelocationEntry, 64u> const&, unsigned long) ()
   from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#4  0x0000400029b495d4 in llvm::RuntimeDyldImpl::applyExternalSymbolRelocations(llvm::StringMap<llvm::JITEvaluatedSymbol, llvm::MallocAllocator>) ()
   from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#5  0x0000400029b49eac in llvm::RuntimeDyldImpl::resolveExternalSymbols() () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#6  0x0000400029b411d8 in llvm::RuntimeDyldImpl::resolveRelocations() () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#7  0x0000400029b4bc6c in llvm::RuntimeDyld::resolveRelocations() () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#8  0x0000400029b4bec0 in llvm::RuntimeDyld::finalizeWithMemoryManagerLocking() () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#9  0x0000400026e43eec in llvm::orc::LegacyRTDyldObjectLinkingLayer::ConcreteLinkedObject<std::shared_ptr<llvm::RuntimeDyld::MemoryManager> >::finalize() ()
   from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#10 0x0000400026e442a0 in llvm::orc::LegacyRTDyldObjectLinkingLayer::ConcreteLinkedObject<std::shared_ptr<llvm::RuntimeDyld::MemoryManager> >::getSymbolMaterializer(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> >)::{lambda()#1}::operator()() const () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#11 0x0000400026e49328 in llvm::Expected<unsigned long> llvm::detail::UniqueFunctionBase<llvm::Expected<unsigned long>>::CallImpl<llvm::orc::LegacyRTDyldObjectLinkingLayer::ConcreteLinkedObject<std::shared_ptr<llvm::RuntimeDyld::MemoryManager> >::getSymbolMaterializer(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> >)::{lambda()#1}>(void*) () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#12 0x0000400026de8e3c in llvm::unique_function<llvm::Expected<unsigned long> ()>::operator()() () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#13 0x0000400026ddc5e0 in llvm::JITSymbol::getAddress() () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#14 0x0000400026de6500 in llvm::OrcCBindingsStack::findSymbolAddressIn(unsigned long, std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, bool)
    () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#15 0x0000400026dd8660 in LLVMOrcGetSymbolAddressIn () from /home/postgres/14-stable/build/pg/lib/postgresql/llvmjit.so
#16 0x0000400026dbe0c0 in llvm_get_function (context=0x121ad3bb0, funcname=0x121b73fd8 "evalexpr_0_3") at /home/postgres/14-stable/build/../src/backend/jit/llvm/llvmjit.c:336
#17 0x0000400026dd6cc8 in ExecRunCompiledExpr (state=0x121b73ca0, econtext=0x121b724c8, isNull=0x11fb2de18)
    at /home/postgres/14-stable/build/../src/backend/jit/llvm/llvmjit_expr.c:2402
#18 0x00000001204a4e44 in ExecEvalExprSwitchContext (state=0x121b73ca0, econtext=0x121b724c8, isNull=0x11fb2de18)
    at /home/postgres/14-stable/build/../src/include/executor/executor.h:339
#19 0x00000001204a4fe0 in ExecQual (state=0x121b73ca0, econtext=0x121b724c8) at /home/postgres/14-stable/build/../src/include/executor/executor.h:408
#20 0x00000001204a53e0 in ExecNestLoop (pstate=0x121b723b8) at /home/postgres/14-stable/build/../src/backend/executor/nodeNestloop.c:214
#21 0x0000000120452d80 in ExecProcNodeFirst (node=0x121b723b8) at /home/postgres/14-stable/build/../src/backend/executor/execProcnode.c:463
#22 0x00000001204433d4 in ExecProcNode (node=0x121b723b8) at /home/postgres/14-stable/build/../src/include/executor/executor.h:257
#23 0x0000000120446c3c in ExecutePlan (estate=0x121b72188, planstate=0x121b723b8, use_parallel_mode=false, operation=CMD_SELECT, sendTuples=true, numberTuples=0,
    direction=ForwardScanDirection, dest=0x121b6f498, execute_once=true) at /home/postgres/14-stable/build/../src/backend/executor/execMain.c:1551
#24 0x0000000120443d78 in standard_ExecutorRun (queryDesc=0x121ac0558, direction=ForwardScanDirection, count=0, execute_once=true)
    at /home/postgres/14-stable/build/../src/backend/executor/execMain.c:361
```

从堆栈信息可以看到问题出在 llvmjit.so 动态库中的 `llvm::RuntimeDyldELF::resolveSW64Relocation()` 函数，我尝试在 PostgreSQL 源码中找不到该函数，并且从这个名字来看，很大概率是申威平台针对 LLVM 做兼容提供的函数。

由于对 LLVM 不是很熟悉，还没法从这个错误里面拆出一个最小示例给到申威，不过这个场景是可以重现的，对于他们定位问题应该是足够了，今天已经将整个重现过程给到申威，不过，我总有一种泥牛入海的感觉 :(。

<div class="just-for-fun">
笑林广记 - 　附例

一秀才畏考援例。堂试之日，至晚不能成篇，乃大书卷面曰：“惟其如此，所以如此。若要如此，何苦如此。”
官见而笑曰：“写得此四句出，毕竟还是个附例。”
</div>
