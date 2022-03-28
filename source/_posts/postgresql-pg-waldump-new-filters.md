---
title: "PostgreSQL 15 特性 - 新增 pg_waldump 过滤选项"
date: 2022-03-28 21:31:55 +0800
categories: 数据库
tags:
  - PostgreSQL
  - pg_waldump
  - PG15
---

PostgreSQL 主分支中针对 pg_waldump 新增了四类过滤选项，分别为 `RelFileNode`、`BlockNumber`、`ForkNum` 和 `FPW`。本文将简要介绍一下这四个过滤选项。

<!--more-->

## RelFileNode 过滤选项

该过滤选项可以通过 `Tablespace OID/Database OID/relfilenode` 的方式来过滤 WAL 日志。例如，我们新建一个表，并插入记录，如下所示。

```sql
CREATE TABLE account(id int, name text);
INSERT INTO account SELECT id, 'account' || id::text FROM generate_series(1, 1000) id;
```

接着，我们通过下面的语句查询表 `account` 的表空间 OID、数据库 OID 以及 `relfilenode`。

```sql
SELECT
    relname,
    CASE WHEN reltablespace = 0
        THEN (SELECT oid FROM pg_tablespace WHERE spcname = 'pg_default')
        ELSE reltablespace
    END AS tablespace,
    (SELECT oid FROM pg_database WHERE datname = current_database()) AS database,
    relfilenode
FROM
    pg_class
WHERE
    relname = 'account';
```

```
 relname | tablespace | database | relfilenode
---------+------------+----------+-------------
 account |       1663 |        5 |       16387
(1 row)
```

现在我们便可以通过 `RelFileNode` 的方式来过滤 WAL 日志，指定 `--relation` 选项。

```shell
$ pg_waldump --relation 1663/5/16387 000000010000000000000001
rmgr: Heap        len (rec/tot):     68/    68, tx:        723, lsn: 0/014C17A8, prev 0/014C1360, desc: INSERT+INIT off 1 flags 0x00, blkref #0: rel 1663/5/16387 blk 0
rmgr: Heap        len (rec/tot):     68/    68, tx:        723, lsn: 0/014C17F0, prev 0/014C17A8, desc: INSERT off 2 flags 0x00, blkref #0: rel 1663/5/16387 blk 0
rmgr: Heap        len (rec/tot):     68/    68, tx:        723, lsn: 0/014C1838, prev 0/014C17F0, desc: INSERT off 3 flags 0x00, blkref #0: rel 1663/5/16387 blk 0
rmgr: Heap        len (rec/tot):     68/    68, tx:        723, lsn: 0/014C1880, prev 0/014C1838, desc: INSERT off 4 flags 0x00, blkref #0: rel 1663/5/16387 blk 0
[...]
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4BE0, prev 0/014C4B98, desc: INSERT+INIT off 1 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4C28, prev 0/014C4BE0, desc: INSERT off 2 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4C70, prev 0/014C4C28, desc: INSERT off 3 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4CB8, prev 0/014C4C70, desc: INSERT off 4 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
[...]
pg_waldump: fatal: error in WAL record at 0/14D66A0: invalid record length at 0/14D66D8: wanted 24, got 0
```

这里需要注意的是，`tablespace OID` 和 `relfilenode` 必须是非负数，而 `Database OID` 则可以为 `0`，例如，`pg_database` 表是共享的，我们可以通过指定 `--relation 1664/0/1262` 来查看该表的 WAL 日志。

```sql
$ pg_waldump pgdata/pg_wal/000000010000000000000001 --relation 1664/0/1262 --fork vm --limit 1
rmgr: Heap2       len (rec/tot):     64/  8256, tx:          0, lsn: 0/01491F20, prev 0/01491EC0, desc: VISIBLE cutoff xid 1 flags 0x03, blkref #0 : rel 1664/0/1262 fork vm blk 0 FPW, blkref #1: rel 1664/0/1262 blk 0
```

## BlockNumber 过滤选项

`BlockNumber` 过滤选项（`--block` 选项）需要与 `RelFileNode` 过滤选项一起使用，即指定 `--block` 选项必须指定 `--relation` 选项，它可以显示指定的数据块的修改日志，如下所示。

```shell
$ pg_waldump --block 1 --relation 1663/5/16387 000000010000000000000001
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4BE0, prev 0/014C4B98, desc: INSERT+INIT off 1 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4C28, prev 0/014C4BE0, desc: INSERT off 2 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4C70, prev 0/014C4C28, desc: INSERT off 3 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4CB8, prev 0/014C4C70, desc: INSERT off 4 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4D00, prev 0/014C4CB8, desc: INSERT off 5 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4D48, prev 0/014C4D00, desc: INSERT off 6 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4D90, prev 0/014C4D48, desc: INSERT off 7 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4DD8, prev 0/014C4D90, desc: INSERT off 8 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4E20, prev 0/014C4DD8, desc: INSERT off 9 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4E68, prev 0/014C4E20, desc: INSERT off 10 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
rmgr: Heap        len (rec/tot):     70/    70, tx:        723, lsn: 0/014C4EB0, prev 0/014C4E68, desc: INSERT off 11 flags 0x00, blkref #0: rel 1663/5/16387 blk 1
[...]
pg_waldump: fatal: error in WAL record at 0/14D66A0: invalid record length at 0/14D66D8: wanted 24, got 0
```

## ForkNum 过滤选项

PostgreSQL 在后端存储的时候会将数据表组织为 `main`, `vm`, `fsm` 和 `init` 四种类型，他们被被称为 `ForkNum`，`ForkNum` 过滤选项（`--fork` 选项）可以过滤指定 `Fork` 类型的 WAL 日志。首先我们删除一些记录。

```sql
ANALYZE;
DELETE FROM account WHERE id < 500;
ANALYZE;
```

接着我们通过 pg_waldump 来查看 `vm` 的修改日志。

```shell
$ pg_waldump --fork vm --relation 1663/5/16387 000000010000000000000001
rmgr: Heap2       len (rec/tot):     64/  8256, tx:          0, lsn: 0/01572228, prev 0/01572080, desc: VISIBLE cutoff xid 0 flags 0x03, blkref #0: rel 1663/5/16387 fork vm blk 0 FPW, blkref #1: rel 1663/5/16387 blk 0
rmgr: Heap2       len (rec/tot):     59/    59, tx:          0, lsn: 0/01574760, prev 0/015745B8, desc: VISIBLE cutoff xid 0 flags 0x03, blkref #0: rel 1663/5/16387 fork vm blk 0, blkref #1: rel 1663/5/16387 blk 1
rmgr: Heap2       len (rec/tot):     59/    59, tx:          0, lsn: 0/015754D0, prev 0/01575398, desc: VISIBLE cutoff xid 723 flags 0x01, blkref #0: rel 1663/5/16387 fork vm blk 0, blkref #1: rel 1663/5/16387 blk 2
rmgr: Heap2       len (rec/tot):     59/    59, tx:          0, lsn: 0/01575510, prev 0/015754D0, desc: VISIBLE cutoff xid 723 flags 0x01, blkref #0: rel 1663/5/16387 fork vm blk 0, blkref #1: rel 1663/5/16387 blk 3
rmgr: Heap2       len (rec/tot):     59/    59, tx:          0, lsn: 0/01575550, prev 0/01575510, desc: VISIBLE cutoff xid 723 flags 0x01, blkref #0: rel 1663/5/16387 fork vm blk 0, blkref #1: rel 1663/5/16387 blk 4
rmgr: Heap2       len (rec/tot):     59/    59, tx:          0, lsn: 0/01575590, prev 0/01575550, desc: VISIBLE cutoff xid 723 flags 0x01, blkref #0: rel 1663/5/16387 fork vm blk 0, blkref #1: rel 1663/5/16387 blk 5
pg_waldump: fatal: error in WAL record at 0/15A01E8: invalid record length at 0/15A0220: wanted 24, got 0
```

## `FPW` 过滤选项

`FPW` 过滤选项（`--fullpage` 选项），即 `full page write`，它可以用于过滤 `full page write` 相关的 WAL 日志。

```sql
CHECKPOINT
UPDATE account SET name = 'xxx100' WHERE id = 600;
```

如下所示，我们过滤了表 `account` 相关的 `full page write` 日志。

```shell
$ pg_waldump --fullpage --relation 1663/5/16387 000000010000000000000001
rmgr: Heap        len (rec/tot):     59/  8223, tx:        765, lsn: 0/0153B660, prev 0/0153B628, desc: DELETE off 1 flags 0x00 KEYS_UPDATED , blkref #0: rel 1663/5/16387 blk 0 FPW
rmgr: Heap        len (rec/tot):     59/  8223, tx:        765, lsn: 0/0153FEF0, prev 0/0153FEB8, desc: DELETE off 1 flags 0x00 KEYS_UPDATED , blkref #0: rel 1663/5/16387 blk 1 FPW
rmgr: Heap        len (rec/tot):     59/  8223, tx:        765, lsn: 0/01544798, prev 0/01544760, desc: DELETE off 1 flags 0x00 KEYS_UPDATED , blkref #0: rel 1663/5/16387 blk 2 FPW
rmgr: Heap2       len (rec/tot):     59/   823, tx:          0, lsn: 0/01571D30, prev 0/01571CF8, desc: PRUNE latestRemovedXid 765 nredirected 0 ndead 185, blkref #0: rel 1663/5/16387 blk 0 FPW
rmgr: Heap2       len (rec/tot):     64/  8256, tx:          0, lsn: 0/01572228, prev 0/01572080, desc: VISIBLE cutoff xid 0 flags 0x03, blkref #0: rel 1663/5/16387 fork vm blk 0 FPW, blkref #1: rel 1663/5/16387 blk 0
rmgr: Heap2       len (rec/tot):     59/   823, tx:          0, lsn: 0/01574280, prev 0/01572228, desc: PRUNE latestRemovedXid 765 nredirected 0 ndead 185, blkref #0: rel 1663/5/16387 blk 1 FPW
rmgr: Heap2       len (rec/tot):     59/  3063, tx:          0, lsn: 0/015747A0, prev 0/01574760, desc: PRUNE latestRemovedXid 765 nredirected 0 ndead 129, blkref #0: rel 1663/5/16387 blk 2 FPW
rmgr: Heap        len (rec/tot):     59/  8223, tx:        806, lsn: 0/015A0308, prev 0/015A02D0, desc: LOCK off 45: xid 806: flags 0x00 LOCK_ONLY EXCL_LOCK , blkref #0: rel 1663/5/16387 blk 3 FPW
pg_waldump: fatal: error in WAL record at 0/15A23C0: invalid record length at 0/15A23F8: wanted 24, got 0
```

## 实现

上述四个过滤选项的实现还是比较简单的，它在 pg_waldump 新增了 `XLogRecordMatchesRelationBlock()` 和 `XLogRecordHasFPW()` 来判断 WAL 日志是否满足过滤条件，您可以在[这里](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=127aea2a65cd89c1c28357c6db199683e219491e)看到完整的代码，后续[这个](https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=52b5568432963b721698a2df1f37a0795b9611dc)提交涉及到了 `fork` 的优化。下面是 `XLogRecordMatchesRelationBlock()` 和 `XLogRecordHasFPW()` 函数的源码。

```c
/*
 * Boolean to return whether the given WAL record matches a specific relation
 * and optionally block.
 */
static bool
XLogRecordMatchesRelationBlock(XLogReaderState *record,
                                                          RelFileNode matchRnode,
                                                          BlockNumber matchBlock,
                                                          ForkNumber matchFork)
{
       int                     block_id;

       for (block_id = 0; block_id <= XLogRecMaxBlockId(record); block_id++)
       {
               RelFileNode rnode;
               ForkNumber      forknum;
               BlockNumber blk;

               if (!XLogRecHasBlockRef(record, block_id))
                       continue;

               XLogRecGetBlockTag(record, block_id, &rnode, &forknum, &blk);

               if ((matchFork == InvalidForkNumber || matchFork == forknum) &&
                       (RelFileNodeEquals(matchRnode, emptyRelFileNode) ||
                        RelFileNodeEquals(matchRnode, rnode)) &&
                       (matchBlock == InvalidBlockNumber || matchBlock == blk))
                       return true;
       }

       return false;
}

/*
 * Boolean to return whether the given WAL record contains a full page write.
 */
static bool
XLogRecordHasFPW(XLogReaderState *record)
{
       int                     block_id;

       for (block_id = 0; block_id <= XLogRecMaxBlockId(record); block_id++)
       {
               if (!XLogRecHasBlockRef(record, block_id))
                       continue;

               if (XLogRecHasBlockImage(record, block_id))
                       return true;
       }

       return false;
}
```

逻辑还是比较简单的，就是从 WAL 日志里面读取，然后匹配过滤选项。

## 参考

[1] https://postgr.es/m/3a4c2e93-7976-2320-fc0a-32097fe148a7%40enterprisedb.com
[2] https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=127aea2a65cd89c1c28357c6db199683e219491e
[3] https://git.postgresql.org/gitweb/?p=postgresql.git;a=commit;h=52b5568432963b721698a2df1f37a0795b9611dc


<div class="just-for-fun">
笑林广记 - 借药碾

一监生临终，谓妻曰：“我一生挣得这副衣冠，死后必为我殡殓。”
妻诺，既死穿衣套靴讫，惟圆帽左右欹侧难戴。
妻哭曰：“我的天，一顶帽子也无福戴。”
生复还魂张目谓妻曰：“必要戴的。”
妻曰：“非不欲带，恨枕不稳耳。”
生曰：“对门某医生家药碾槽，借来好做枕。”
</div>
