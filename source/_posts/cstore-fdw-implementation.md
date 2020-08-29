---
title: 列存数据库 cstore_fdw 的实现
date: 2018-10-27 20:55:21 +0800
category: 数据库
tags:
  - cstore_fdw
  - 列存
---

在{% post_link introduction-cstore-fdw-columnar-store 上一篇 %}中我介绍了如何安装和使用列存数据库 cstore_fdw。接着，我将在本篇中介绍 cstore_fdw 是如何实现的。

Cstore_fdw 是基于 PostgreSQL 开发的一款列存数据库，它采用 ORC 作为低层的物理存储格式 (有部分改动)，使用 protobuf 进行序列化并采用 PostgreSQL 外部插件的形式集成到数据库中。Cstore_fdw 包含 3 个头文件以及 5 个源文件：

* __cstore_compression.c__ - 该文件包含 cstore_fdw 使用的压缩和解压缩的算法实现。
* __cstore_fdw.c__ - 该文件包含列存扫描、分析以及复制数据到 cstore_fdw 外部表的函数的定义。它使用了 cstore_reader 和 cstore_writer 提供的 API 接口来读写 cstore 文件。
* __cstore_fdw.h__ - 该文件包含 cstore_fdw 使用的类型及函数声明。
* __cstore_metadata_serialization.c__ - 该文件包含 cstore_fdw 序列化和反序列化元数据的函数的实现。
* __cstore_metadata_serialization.h__ - 该文件包含 cstore_fdw 序列化和反序列化元数据的函数的声明。
* __cstore_reader.c__ - 该文件包含读取 cstore 文件的函数定义。它包括读取文件元数据，row stripes 以及跳跃不相关的数据块或列数据。
* __cstore_version_compat.h__ - 该文件包含用于编写与 PostgreSQL 版本无关的代码宏。
* __cstore_writer.c__ - 该文件包含写入 cstore 文件的函数定义。它包括写入文件元数据，row stripes 以及计算跳跃块节点信息。

<!-- more -->

## 物理结构

Cstore_fdw 使用表数据文件 (Table Data File) 和表页脚文件 (Table Footer File) 来管理列存数据。

* __表数据文件__ - 该文件包含表数据以及用于执行 WHERE 查询时所用到的跳跃块信息。如果为外部表指定了 `filename` 参数，那么数据文件则存储在该参数指定的位置。否则，他将采用 `$PGDATA/$dboid/$relfilenode` 的路径进行存储。
* __表页脚文件__ - 该文件包含每个 stripe 在表数据文件中的偏移位置及其长度。它的存储路径则是在表数据文件后添加 `.footer` 后缀。

### 表页脚文件

表页脚文件同样由三个部分组成，它们是 Table Footer，Postscript 和 Postscript Size。

* __Table Footer__ - 该部分包含每个 stripe 的文件偏移位置以及不同部分的长度。我们可以使用这些信息来读取 stripe 结构。
* __Postscript__ - 该部分包含 table footer 的长度以及签名和版本信息。
* __Postscript Size__ - 表页脚文件的最后一个字节用于读取 postscript 结构。

我们可以在 [cstore_fdw.h](https://github.com/citusdata/cstore_fdw/blob/master/cstore_fdw.h) 文件和 [cstore.proto](https://github.com/citusdata/cstore_fdw/blob/master/cstore.proto) 文件中查看该文件的物理布局。图 1 展示了包含四个 stripe 结构的表页脚的物理布局结构。

{% asset_img Physical-of-Table-Footer.svg The Physical Layout of Table Footer %}
<p style="text-align:center">图 1 表页脚的物理布局</p>

### 表数据文件

Cstore_fdw 中数据被划分为单个的 row stripe 结构并存储在表数据文件中，每个 row stripe 中包含的行数可以通过 `stripe_row_count` 参数进行修改，每个 stripe 包含下面三个部分：

* __Stripe Skip List__ - 该部分包含 stripe 中每个列数据块的统计信息 (最大值、最小值以及位置信息，参考 [cstore_fdw.h](https://github.com/citusdata/cstore_fdw/blob/master/cstore_fdw.h) 中的定义)。我们可以通过这是信息来执行 WHERE 条件的过滤从而避免读取不必要的数据块。
* __Stripe Data__ - 在列数据块中我们存储两个内容： "exists" 和 "value"。其中 "exists" 是一个布尔数组，它表明哪些值不为 NULL，而 "value" 数组则包含不为 NULL 的数据。如果使用了压缩，那么 "value" 的内容将会被压缩后在存储。我们可以使用 `compression=pglz` 来启用压缩。Cstore_fdw 使用 PostgreSQL 中的 Datum 结构来表示磁盘上的数据值。
* __Stripe Footer__ - 该部分包含 stripe skip list 和 stripe data 的数据长度。

图 2 给出了 cstore_fdw 中表数据文件的物理布局。

{% asset_img Physical-of-Table-Data.svg The Physical Layout of Table Data %}
<p style="text-align:center">图 2 表数据的物理布局</p>

正如上文所述，表数据文件被划分为 stripe 结构，而 strip 内部又由 skip list，stripe data 和 stripe footer 组成。然而在 skip list 和 stripe data 内部则是由每个属性列组成，并且每个属性列又被划分为 block 结构。Skip list 中包含 block skip node 用于执行过滤，从而跳过不相关的数据块。Stripe data 则将数据进一步划分为 exists block 和 values block，它们分别存储属性值存储标志和属性值。

## 列存读写实现

Cstore_fdw 在读写数据文件分为两个步骤：(a) 读写表页脚文件；(b) 读写表数据文件。本节主要介绍 cstore_fdw 的读写实现。

### 数据写入

Cstore_fdw 在写入数据时通过 TableStateWrite 结构维护数据写入状态，其定义如下：

``` C
typedef struct TableWriteState
{
        FILE *tableFile;                     /* 数据文件描述符 */
        TableFooter *tableFooter;            /* 表页脚文件结构 */
        StringInfo tableFooterFilename;      /* 表页脚文件名称 */
        CompressionType compressionType;     /* 压缩类型，用于压缩数据值 */
        TupleDesc tupleDescriptor;           /* 元组描述符 */
        FmgrInfo **comparisonFunctionArray;  /* 压缩函数数组 */
        uint64 currentFileOffset;            /* 当前文件写入的偏移位置 */
        Relation relation;                   /* 当前关系表结构 */

        MemoryContext stripeWriteContext;    /* Stripe 内存管理句柄 */
        StripeBuffers *stripeBuffers;        /* 用于存储 stripe data 数据 */
        StripeSkipList *stripeSkipList;      /* 跳跃表信息 */
        uint32 stripeMaxRowCount;            /* Stripe 最大的行记录数 */
        ColumnBlockData **blockDataArray;    /* 当前 stripe 每个列的 block 信息 */

        /*
         * compressionBuffer 用于进行压缩时的临时存储，将它放至在这里主要是为了
         * 减小内存的分配，它位于 stripeWriteContext 内存上下文并且在该内存上下
         * 文重置时被删除。
         */
        StringInfo compressionBuffer;
} TableWriteState;
```

假设我们有一个名为 test 的数据表，其中包含两个属性，cstore_fdw 在执行 COPY 命令导入数据时会先执行 `CStoreBeginWrite()` 函数来初始化 TableWriteState 结构。图 3 给出了 TableWriteState 的逻辑结构。

{% asset_img Logical-of-TableWriteState.svg The Logical Layout of TableWriteState %}
<p style="text-align:center">图 3 TableWriteState 的逻辑结构</p>

`CStoreBeginWrite()` 函数的执行主要分为以下四个步骤：

1. 检测表页脚文件是否存在。如果存在，则将其内容读取出来并反序列化到 TableFooter 对象中；反之，若是不存在该文件，说明是第一次向表中插入数据，cstore_fdw 则在内存中创建一个新的 TableFooter 对象。其实在构造 TableFooter 之前，cstore_fdw 会根据表页脚文件的存在与否来决定表数据文件的打开方式。
2. 从 tableFooter->stripMetadataList 中读取当前表数据文件的写入位置，并将表数据文件的文件写入指针移动到该位置，即读取最后一个 StripeMetadata 并将四个成员相加从而计算下个 stripe 应该写入的位置。
3. 遍历所有的列并获取该列的压缩算法。
4. 创建 stripe 内存上下文，在此之后，所有的列存相关的内存分配都在该内存上下文上进行分配，以便进行内存管理。同时我们需要为每个列新建 ColumnBlockData 对象用于存储插入的值，详细见 `CreateEmptyBlockDataArray()` 函数。

在初始化 TableWriteState 完成之后，我们就需要向列存写入数据了，cstore_fdw 通过 `CStoreWriteRow()` 函数来实现该功能，其执行过程如下：

1. 检测 TableWriteState->stripeBuffers 是否为空。若为空，则调用 `CreateEmptyStripeBuffers()` 函数和 `CreateEmptyStripeSkipList()` 函数为每个列创建 ColumnBuffers 对象和 ColumnBlockSkipNode 对象。
2. 遍历所有属性列并如果该属性列为空则设置 existsArray 中对应的值为 false；反之则调用 `SerializeSingleDatum()` 函数将值序列化到 valueBuffer 中，同时它将调用 `UpdateBlockSkipNodeMinMax()` 函数更新当前数据块中的最大值、最小值的统计信息。
3. 判断当前数据块是否已满。若当前数据块已满，则调用 `SerializeBlockData()` 函数对当前数据块进行序列化。该函数内部首先将所有列的 exists 信息分别序列化到对应的 ColumnBlockBuffers 中的 existsBuffer 中，随后将所有列的 values 信息分别序列化到对应的 ColumnBlockBuffers 中的 valueBuffer 中。需要注意的是，在序列化属性值的时候，将根据属性列是否可以压缩来对其进行数据压缩。
4. 最后，检查当前 stripe 的行记录数是否已经达到 stripe 可容纳的最大行记录数。若是则调用 `FlushStrip()` 函数将当前 stripe 刷到磁盘，并在 TableFooter 中新增一条 stripeMetadata 元数据；反之则进行下一条记录的写入操作。

当所有记录通过 `CStoreWriteRow()` 函数写入到列存数据库中后，cstore_fdw 将通过 `CStoreEndWrite()` 函数来执行最后的清理动作。该函数主要进行以下工作：

1. 如果 stripe 不为空，则将 stripe 信息刷写到磁盘。
2. 将数据文件内容同步到磁盘（stripe 信息的刷写可能只是到达了磁盘驱动的缓存中，而并没有实际落盘）。
3. 创建临时文件刷写 TableFooter 信息，当 TableFooter 落盘成功后重名该文件为标准的表页脚文件名。

至此，整个 cstore_fdw 的数据写入过程就介绍完毕了，接下来我们将介绍其数据读取部分的实现。

### 数据读取

同样，cstore_fdw 在读取数据时也通过一个名为 TableReadState 的结构来维护数据读取的相关信息，其定义如下：

```
typedef struct TableReadState
{
    FILE *tableFile;
    TableFooter *tableFooter;
    TupleDesc tupleDescriptor;

    /*
     * 指向查询中的列的 Var 指针，使用它来获取投影的列
     */
    List *projectedColumnList;

    List *whereClauseList;                 /* 过滤条件 */
    MemoryContext stripeReadContext;
    StripeBuffers *stripeBuffers;          /* Stripe 对象 */
    uint32 readStripeCount;
    uint64 stripeReadRowCount;             /* 已经读取的行记录数（当前 stripe 中）*/
    ColumnBlockData **blockDataArray;
    int32 deserializedBlockIndex;          /* 当前反序列化的数据块编号 */
} TableReadState;
```

当我们从 cstore_fdw 中读取数据时，首先需要通过 `CStoreBeginRead()` 函数来初始化 TableReadState 结构，随后调用 `CStoreReadNextRow()` 函数读取行记录，最后通过 `CStoreEndRead()` 函数进行清理工作。上述函数均依赖 TableReadState 结构来维护当前读取的信息。图 4 给出了 TableReadState 的逻辑结构。

{% asset_img Logical-of-TableReadState.svg The Logical Layout of TableReadState %}
<p style="text-align:center">图 4 TableReadState 的逻辑结构</p>

`CStoreBeginRead()` 函数主要负责初始化工作，它返回的 TableReadState 结构将用于整个读取过程。该函数的执行步骤如下：

1. 尝试从表页脚文件中读取 TableFooter 信息。函数 `CStoreReadFooter()` 用于读取表页脚文件，该函数首先读取文件的最后一个字节作为 postcript 的长度；随后对去 postscript 信息并通过 `DeserializePostScript()` 函数进行反序列化并校验其是否被修改，然后返回 TableFooter 信息的长度；最后将文件中的 TableFooter 信息通过 `DescrializeTableFooter()` 函数反序列化到 TableReadState->tableFooter 结构中。
2. 打开表数据文件并创建 stripeReadContext 内存上下文。
3. 由 `ProjectedColumnMask()` 函数根据 projectedColumnList 参数获取投影列信息，并使用 `CreateEmptyBlockDataArray()` 函数为所有投影的列新建 ColumnBlockData 对象。
4. 最后，初始化反序列的数据块索引、当前 stripe 已读的行数、已读取的 stripe 数量等信息并返回 TableReadState 结构。

接着，cstore_fdw 将通过 `CStoreReadNextRow()` 函数读取行记录。函数在成功读取到行数据时会将返回 true 并将数据通过参数的形式返回；若没有更多的记录可读，函数将返回 false。该函数的执行过程如下：

1. 首先判断 TableReadState->stripeBuffers 是否为空。若为空，则说明没有载入 stripe 信息，因此需要载入一个非空的 stripe 以便读取数据。如果当前读取的 stripe 编号与 TableFooter 中记录的 stripeMetadata 的数量相等，则说明没有可读的 stripe 信息，这标志了数据已经读取完，返回 false；反之则通过 `LoadFilteredStripeBuffers()` 函数载入 stripe 信息并将 TableReadState->readStripeCount 加 1。如果读取的 stripe 中行记录数为 0 则说明该 stripe 中不包含记录，因此我们需要继续读取下一个 stripe；反之则重置 TableReadState->stripeReadRowCount、TableReadState->deserializeBlockIndex 等与 stripe 相关的信息。
2. 判断当前所读取的行是否在已经反序列化的数据块中。若是则转至 3，反之则需要通过函数 `DeserializeBlockData()` 来反序列化一个新的数据块用于读取数据。
3. 调用函数 `ReadStripeNextRow()` 读取一条行记录。如果当前读取的 TableReadState->stripeReadRowCount 与 TableReadState->stripeBuffers->rowCount 相等则说明当前 stripe 中的行记录以及读取完，将 TableReadState->stripeBuffers 置为 NULL 为下次读取作准备。

当表中所有的数据都已读出，cstore_fdw 将通过 `CStoreEndRead()` 函数来进行后续的善后工作。其中主要包括内存上下文的释放，文件的关闭等。

## 总结

本文结合 cstore_fdw 的源码分析了其物理的存储格式，梳理了其数据读写的流程。从源码角度我们可以看到 cstore_fdw 在每次插入都会新建 stripe 来处理插入的数据，若是大量的小数据插入势必会导致元数据信息的迅速膨胀，从而影响性能，因此 cstore_fdw 不支持 INSERT 语句。
