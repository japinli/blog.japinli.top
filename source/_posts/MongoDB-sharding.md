---
title: "MongoDB 数据库分片集群入门"
date: 2021-05-23 08:34:22 +0800
category: 数据库
tags:
  - MongoDB
---

本文结合官方文档整理记录了一下关于 MongoDB 中分片的概念以及如何搭建一个分片集群。

<!-- more -->

## 分片

分片（Sharding）是一种用于在多台计算机之间分配数据的方法。MongoDB 使用分片来支持具有非常大的数据集和高吞吐量操作的部署。

大数据集的数据库系统或高吞吐量应用程序对单个服务器的容量来说是一种挑战。例如，高查询率可能会耗尽服务器的 CPU 容量。大于系统 RAM 的工作集会增加磁盘驱动器的 I/O 压力。

垂直扩展（Vertical Scaling）可以增加单个服务器的处理能力，例如使用更快的 CPU，增加 RAM，或者增加存储空间。可用技术的局限性可能会限制一台计算机对于给定的工作负载没有足够的功能。此外，基于云的提供程序具有基于可用硬件配置的严格上限。因此，垂直扩展有一个实际的最大值。

水平扩展（Horizontal Scaling）涉及数据集的划分并在多台服务器上加载，同时添加其他服务器已根据需要增加容量。虽然单台计算机的整体速度或容量可能不高，但是每台计算机只能处理全部工作量的一部分，因此与单台高速大容量服务器相比，可能会提供更高的效率。扩展部署的容量仅需要根据需要添加其他服务器，这可以比单台机器的高端硬件降低总体成本。折衷方案是增加基础结构和部署维护的复杂性。

MongoDB 通过分片的方式支持水平扩展。

### 分片集群

MongoDB 分片集群（sharded cluster）包含以下组件：

* __shard__: 每个分片都包含分片数据的子集。每个分片都可以部署为副本集。
* __mongos__: mongos 充当查询路由器，在客户端应用程序和分片群集之间提供接口。
* __config servers__: 配置服务器（config servers）存储群集的元数据和配置设置。

下图描述了分片群集中组件的交互：

{% asset_img sharded-cluster-production-architecture.bakedsvg.svg %}

MongoDB 在 collection 级别对数据进行分片，从而将 collection 数据分布在集群中的各个分片上。

### 分片键

MongoDB 使用分片键（shard keys）在各个分片之间分发 collection 的文档。分片键由文档中的一个或多个字段组成。

* 从版本 4.4 开始，分片集合中的文档的分片键不再是必须的。缺少分片键在跨分片分发文档时被视为空值，但是在路由查询时则不会将其视为空值。
* 在 4.2 及更早版本中，分片集合中的每个文档中都必须存在分片键字段。

文档的分片键值决定了其在各个分片中的分布。

* 从 4.2 版本开始，如果您的文档分片键不包括不可变的 `_id` 域，那么您是可以更新文档分片键的。
* 在 4.0 及更早版本中，文档的分片键是不可变的。

### 分片键索引

要对已填充的集合进行分片，该集合必须具有以分片键开头的索引。在对一个空集合进行分片时，如果该集合还没有针对指定分片键的适当索引，则 MongoDB 会创建支持索引。

### 分片键策略

分片键的选择会影响分片群集的性能，效率和可伸缩性。在拥有最佳硬件和基础结构的集群中，分片键可能会成为性能的瓶颈。

### 块

MongoDB 分区将分片数据划分为块（chunks）。每个块都有一个基于分片键的范围，其包含下边界，而不包含上边界。

### 均衡器和均匀分配

为了在整个集群中的所有分片上实现块的均匀分布，均衡器在后台运行，以在各分片上迁移块。

## 部署

我们将在一台机器上部署 3 个配置服务器，3 个分片服务器（每个分片服务器包含 3 个副本集）以及 3 个 mongos 服务器，如下表所示。

| name           | IP        | port  |
| -------------- | --------- | ----- |
| config server1 | 127.0.0.1 | 27011 |
| config server2 | 127.0.0.1 | 27012 |
| config server3 | 127.0.0.1 | 27013 |
| shard01 repl01 | 127.0.0.1 | 28011 |
| shard01 repl02 | 127.0.0.1 | 28012 |
| shard01 repl03 | 127.0.0.1 | 28013 |
| shard02 repl01 | 127.0.0.1 | 28021 |
| shard02 repl02 | 127.0.0.1 | 28022 |
| shard02 repl03 | 127.0.0.1 | 28023 |
| shard03 repl03 | 127.0.0.1 | 28031 |
| shard03 repl03 | 127.0.0.1 | 28032 |
| shard03 repl03 | 127.0.0.1 | 28033 |
| mongos01       | 127.0.0.1 | 27017 |
| mongos01       | 127.0.0.1 | 27018 |
| mongos01       | 127.0.0.1 | 27019 |

### 创建配置服务器

对于生产环境来说，需要至少部署配置服务器三个副本集。配置服务器 01 配置文件 `config-server01.yml`。

```yml
sharding:
  clusterRole: configsvr
replication:
  replSetName: configServerRepl
net:
  bindIp: 127.0.0.1
  port: 27011
storage:
  dbPath: /home/japin/MongoDB/shardData/config-server-data01
```

配置服务器 02 配置文件 `config-server02.yml`。

```yml
sharding:
  clusterRole: configsvr
replication:
  replSetName: configServerRepl
net:
  bindIp: 127.0.0.1
  port: 27012
storage:
  dbPath: /home/japin/MongoDB/shardData/config-server-data02
```

配置服务器 03 配置文件 `config-server03.yml`。

```yml
sharding:
  clusterRole: configsvr
replication:
  replSetName: configServerRepl
net:
  bindIp: 127.0.0.1
  port: 27013
storage:
  dbPath: /home/japin/MongoDB/shardData/config-server-data03
```

创建配置服务器数据目录。

```shell
$ mkdir -p /home/japin/MongoDB/shardData/config-server-data0{1,2,3}
```

启动配置服务器。

```shell
$ for i in $(seq 1 3); do mongod --fork --config config-server0$i.yml; done
```

初始化配置服务器副本集。

```javascript
$ mongo --host 127.0.0.1 --port 27011
rs.initiate(
  {
    _id: "configServerRepl",
    configsvr: true,
    members: [
      { _id: 1, host: "127.0.0.1:27011" },
      { _id: 2, host: "127.0.0.1:27012" },
      { _id: 3, host: "127.0.0.1:27013" }
    ]
  }
)
```

### 创建分片服务器

分片节点 `01` 的配置文件，包含三个副本集合。分片节点 `01` 副本集 `01` 的配置 `shard01-01.yml` 如下所示。

```yml
systemLog:
  destination: file
  path: '/home/japin/MongoDB/log/shard01-01.log'
  logAppend: true
sharding:
  clusterRole: shardsvr
replication:
  replSetName: shardServer01Repl
net:
  bindIp: 127.0.0.1
  port: 28011
storage:
  dbPath: /home/japin/MongoDB/shardData/shard01-data01
```

分片节点 `01` 副本集 `02` 的配置 `shard01-02.yml` 如下所示。

```yml
systemLog:
  destination: file
  path: '/home/japin/MongoDB/log/shard01-02.log'
  logAppend: true
sharding:
  clusterRole: shardsvr
replication:
  replSetName: shardServer01Repl
net:
  bindIp: 127.0.0.1
  port: 28012
storage:
  dbPath: /home/japin/MongoDB/shardData/shard01-data02
```

分片节点 `01` 副本集 `03` 的配置 `shard01-03.yml` 如下所示。

```yml
systemLog:
  destination: file
  path: '/home/japin/MongoDB/log/shard01-03.log'
  logAppend: true
sharding:
  clusterRole: shardsvr
replication:
  replSetName: shardServer01Repl
net:
  bindIp: 127.0.0.1
  port: 28013
storage:
  dbPath: /home/japin/MongoDB/shardData/shard01-data03
```

其他两个分片服务器机器副本集与上面类似，这里就不赘述了。接下来我们创建目录。

```shell
$ mkdir -p /home/japin/MongoDB/shardData/shard0{1,2,3}-data0{1,2,3}
```

启动所有分片副本集节点。

```shell
$ for i in $(seq 1 3); do for j in $(seq 1 3); do mongod --fork --config shard0$i-0$j.yml; done done
```

初始化 `shard01` 分片副本集。

```shell
$ mongo --host 127.0.0.1 --port 28011
rs.initiate(
  {
    _id: "shardServer01Repl",
    members: [
      { _id: 1, host: "127.0.0.1:28011" },
      { _id: 2, host: "127.0.0.1:28012" },
      { _id: 3, host: "127.0.0.1:28013" }
    ]
  }
)
```

初始化 `shard02` 分片副本集。

```shell
$ mongo --host 127.0.0.1 --port 28021
rs.initiate(
  {
    _id: "shardServer02Repl",
    members: [
      { _id: 1, host: "127.0.0.1:28021" },
      { _id: 2, host: "127.0.0.1:28022" },
      { _id: 3, host: "127.0.0.1:28023" }
    ]
  }
)
```

初始化 `shard03` 分片副本集l。

```shell
$ mongo --host 127.0.0.1 --port 28031
rs.initiate(
  {
    _id: "shardServer03Repl",
    members: [
      { _id: 1, host: "127.0.0.1:28031" },
      { _id: 2, host: "127.0.0.1:28032" },
      { _id: 3, host: "127.0.0.1:28033" }
    ]
  }
)
```

### 创建 mongos 服务器

```yml
systemLog:
  destination: file
  path: '/home/japin/MongoDB/log/mongos01.log'
  logAppend: true
sharding:
  configDB: configServerRepl/127.0.0.1:27011,127.0.0.1:27012,127.0.0.1:27013
net:
  bindIp: 127.0.0.1
  port: 27017
```

```yml
systemLog:
  destination: file
  path: '/home/japin/MongoDB/log/mongos02.log'
  logAppend: true
sharding:
  configDB: configServerRepl/127.0.0.1:27011,127.0.0.1:27012,127.0.0.1:27013
net:
  bindIp: 127.0.0.1
  port: 27018
```

```yml
systemLog:
  destination: file
  path: '/home/japin/MongoDB/log/mongos03.log'
  logAppend: true
sharding:
  configDB: configServerRepl/127.0.0.1:27011,127.0.0.1:27012,127.0.0.1:27013
net:
  bindIp: 127.0.0.1
  port: 27019
```

```shell
$ for i in $(seq 1 3); do mongos --fork --config mongos0$i.yml; done
```

### 添加分片服务器到集群

以下操作将单个分片副本集添加到集群：

```shell
$ mongo --host 127.0.0.1 --port 27017
sh.addShard("shardServer01Repl/127.0.0.1:28011,127.0.0.1:28012,127.0.0.1:28013")
sh.addShard("shardServer02Repl/127.0.0.1:28021,127.0.0.1:28022,127.0.0.1:28023")
sh.addShard("shardServer03Repl/127.0.0.1:28031,127.0.0.1:28032,127.0.0.1:28033")
```

### 为数据库开启分片

首先使用 `use mydb` 创建一个数据库，随后通过 `sh.enableSharding("mydb")` 为其开启分片功能。

```shell
mongos> sh.enableSharding("mydb")
{
	"ok" : 1,
	"operationTime" : Timestamp(1621422117, 7),
	"$clusterTime" : {
		"clusterTime" : Timestamp(1621422117, 8),
		"signature" : {
			"hash" : BinData(0,"AAAAAAAAAAAAAAAAAAAAAAAAAAA="),
			"keyId" : NumberLong(0)
		}
	}
}
```

我们可以通过下面的命令查看服务器分片信息。

```shell
mongos> db.serverStatus().sharding
{
	"configsvrConnectionString" : "configServerRepl/127.0.0.1:27011,127.0.0.1:27012,127.0.0.1:27013",
	"lastSeenConfigServerOpTime" : {
		"ts" : Timestamp(1621422635, 17),
		"t" : NumberLong(1)
	},
	"maxChunkSizeInBytes" : NumberLong(67108864)
}
mongos> db.serverStatus().shardingStatistics
{
	"numHostsTargeted" : {
		"find" : {
			"allShards" : 0,
			"manyShards" : 0,
			"oneShard" : 0,
			"unsharded" : 0
		},
		"insert" : {
			"allShards" : 0,
			"manyShards" : 0,
			"oneShard" : 0,
			"unsharded" : 0
		},
		"update" : {
			"allShards" : 0,
			"manyShards" : 0,
			"oneShard" : 0,
			"unsharded" : 0
		},
		"delete" : {
			"allShards" : 0,
			"manyShards" : 0,
			"oneShard" : 0,
			"unsharded" : 0
		},
		"aggregate" : {
			"allShards" : 0,
			"manyShards" : 0,
			"oneShard" : 0,
			"unsharded" : 0
		}
	},
	"catalogCache" : {
		"numDatabaseEntries" : NumberLong(1),
		"numCollectionEntries" : NumberLong(1),
		"countStaleConfigErrors" : NumberLong(0),
		"totalRefreshWaitTimeMicros" : NumberLong(3385241),
		"numActiveIncrementalRefreshes" : NumberLong(0),
		"countIncrementalRefreshesStarted" : NumberLong(2),
		"numActiveFullRefreshes" : NumberLong(0),
		"countFullRefreshesStarted" : NumberLong(2),
		"countFailedRefreshes" : NumberLong(0),
		"operationsBlockedByRefresh" : {
			"countAllOperations" : NumberLong(0),
			"countInserts" : NumberLong(0),
			"countQueries" : NumberLong(0),
			"countUpdates" : NumberLong(0),
			"countDeletes" : NumberLong(0),
			"countCommands" : NumberLong(0)
		}
	}
}
mongos> db.printShardingStatus()
--- Sharding Status ---
  sharding version: {
  	"_id" : 1,
  	"minCompatibleVersion" : 5,
  	"currentVersion" : 6,
  	"clusterId" : ObjectId("60a4e790c9fbede2e257b1f8")
  }
  shards:
        {  "_id" : "shardServer01Repl",  "host" : "shardServer01Repl/127.0.0.1:28011,127.0.0.1:28012,127.0.0.1:28013",  "state" : 1 }
        {  "_id" : "shardServer02Repl",  "host" : "shardServer02Repl/127.0.0.1:28021,127.0.0.1:28022,127.0.0.1:28023",  "state" : 1 }
        {  "_id" : "shardServer03Repl",  "host" : "shardServer03Repl/127.0.0.1:28031,127.0.0.1:28032,127.0.0.1:28033",  "state" : 1 }
  active mongoses:
        "4.4.4" : 3
  autosplit:
        Currently enabled: yes
  balancer:
        Currently enabled:  yes
        Currently running:  yes
        Collections with active migrations:
                config.system.sessions started at Wed May 19 2021 19:16:45 GMT+0800 (CST)
        Failed balancer rounds in last 5 attempts:  0
        Migration Results for the last 24 hours:
                248 : Success
  databases:
        {  "_id" : "config",  "primary" : "config",  "partitioned" : true }
                config.system.sessions
                        shard key: { "_id" : 1 }
                        unique: false
                        balancing: true
                        chunks:
                                shardServer01Repl	776
                                shardServer02Repl	124
                                shardServer03Repl	124
                        too many chunks to print, use verbose if you want to force print
        {  "_id" : "mydb",  "primary" : "shardServer02Repl",  "partitioned" : true,  "version" : {  "uuid" : UUID("5d958304-ff6a-4568-88d4-20f3dcc568c5"),  "lastMod" : 1 } }
```

## 参考

[1] https://docs.mongodb.com/manual/sharding/
[2] https://docs.mongodb.com/manual/tutorial/deploy-shard-cluster/


<div class="just-for-fun">
笑林广记 - 偶遇知音

某生素善琴，尝谓世无知音，抑抑不乐。
一日无事，抚琴消遣，忽闻隔邻，有叹息声，大喜，以为知音在是，款扉叩之，
邻媪曰：“无他，亡儿存日，以弹絮为业，今客鼓此，酷类其音，闻之，不觉悲从中耳。”
</div>
