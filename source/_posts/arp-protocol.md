---
title: "重拾 ARP 协议"
date: 2019-09-28 12:40:14 +0800
category: 杂项
tags:
  - ARP
---

ARP (Address Resolution Protoco)，中文地址解析协议，用来将网络层的 IP 地址转换为数据链路层的物理地址，该协议属于 TCP/IP 协议簇。当一台主机把以太网数据帧发送到位于同一局域网上的另一台主机时，是根据 48 bit 的以太网地址来确定目的接口的。设备驱动程序从不检查 IP 数据报中的目的 IP 地址。而地址解析为这两种不同的地址形式提供映射: 32 bit 的 IP 地址和数据链路层使用的任何类型的地址。[RFC 826][] 给出了 ARP 协议的规范。ARP 协议为 IP 地址到对应的硬件物理地址提供了动态映射，通常情况下用户或系统管理员不用担心。

<!-- more -->

## ARP 原理

我们知道主机之间是通过 IP 地址来进行通信的，而 IP 地址属于网络层，而实际上网络通信需要知道通信设备的硬件地址（即 MAC 地址）。ARP 协议便是做这项工作的。假设我们在局域网中有两台主机 `A` 和 `B`，`A` 想要与 `B` 进行通信，但是 `A` 只知道 `B` 的 IP 地址，其通信的硬件地址查询过程如下：

1. 主机 `A` 首先检测自己的 ARP 缓存中是否包含主机 `B` 的 IP 与 MAC 地址之间的映射关系。如果存在则可以直接通信；反之，则需要先获取主机 `B` 的 IP 与 MAC 地址之间的映射关系。
2. 主机 `A` 的 ARP 缓存中不存在该 IP 地址的映射记录，因此主机 `A` 需要想局域网广播请求该 IP 对应的 MAC 地址。
3. 局域网内的其它机器在收到该 ARP 请求之后，会获取主机 `A` 的 IP 地址和 MAC 地址并添加到自己的 ARP 缓存中，若该主机的 IP 地址为 ARP 所请求的 IP 地址，那么它需要发送 ARP 响应包，反之，则忽略该 ARP 请求。
4. 主机 `B` 在接收到该 ARP 请求之后会将自己的 IP 地址和 MAC 地址填入数据包中并__定向__ 发送给主机 `A`。
5. 主机 `A` 在接收到主机  `B` 的 ARP 响应之后使用该包的 IP 和 MAC 地址更新 ARP 缓存。此时，主机 `A` 和 `B` 便可以正常通信了。

我们可以通过 `arp -a` 查看当前的 ARP 缓存。例如：

```
$ arp -a
xiaoqiang (192.168.31.1) at 50:64:2b:18:b8:e3 on en0 ifscope [ethernet]
? (192.168.31.29) at e0:6:e6:ca:25:26 on en0 ifscope [ethernet]
? (192.168.31.126) at 40:83:1d:b9:f4:71 on en0 ifscope [ethernet]
? (192.168.31.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
? (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
? (239.255.255.250) at 1:0:5e:7f:ff:fa on en0 ifscope permanent [ethernet]
```

## ARP 报文格式

在以太网上解析 IP 地址时，ARP 请求和应答的格式如下图所示。

{% asset_img arp.png ARP 报文结构 %}

* 以太网报头中的前两个字段是以太网的目的地址和源地址（即物理地址、MAC 地址）。若目的地址全为 `1`，这表明其为广播地址。局域网中的所有以太网接口都要接收广播的数据帧。
* 帧类型则表明后续的数据类型，对于 ARP 请求和应答来说，它为 `0x0806`。
* 硬件类型和协议类型用来描述 ARP 分组中的各个字段。 例如，一个 ARP 请求分组询问协议地址（这里是 IP 地址）对应的硬件地址（这里是以太网地址)。硬件类型字段表示硬件地址的类型。它的值为 `1` 即表示以太网地址。协议类型字段表示要映射的协议地址类型。它的值为 `0x0800` 即表示 IP 地址。
* 硬件地址长度和协议地址长度分别指出硬件地址和协议地址的长度，以字节为单位。对于以太网上 IP 地址的 ARP 请求或应答来说，它们的值分别为 `6` 和 `4`。
* 操作字段 `op` 给出了操作类型，它包含 ARP 请求 （`1`）、ARP 应答（`2`）、RARP 请求（`3`）和 RARP 应答（`4`）四种操作。
* 最后四个字段分别是发送端的以太网地址和协议地址以及目的端的以太网地址和协议地址。

## ARP 请求与响应

现在我们对 ARP 的工作原理以及报文格式有所了解，接下来就是如何去填充 ARP 报文？当我们请求一个 IP 地址的 MAC 地址时，我们是不知道其 MAC 地址的，即__以太网目的地址__和__目的端以太网地址__，而__以太网源地址__、__发送端以太网地址__、__发送端 IP 地址__以及__目的端 IP 地址__我们是知道的。__op__ 字段则是根据 ARP 操作类型进行填充，这里为 ARP 请求，故值为 `1`。其它五个字段则是固定的，__帧类型__为 `0x0806`；__硬件类型__为 `0x01`；__协议类型__为 `0x0800`；__硬件地址长度__为 `6`；__协议地址长度__为 `4`。那么我们该如何填充__以太网目的地址__和__目的端以太网地址__呢？其实它们是相同的。我们需要将其设置为广播地址（`0xFF,0xFF, 0xFF,0xFF,0xFF, 0xFF`），这样局域网中的每个网络接口都会接收这个数据包并进行处理。

如下图所示，我在主机 `lenovo` 上通过 `arping -I interface 192.168.31.138` 向局域网查询 IP 地址为 `192.168.31.138` 的 MAC 地址，同时在该主机上通过 `tcpdum` 捕获 ARP 数据包。

{% asset_img tcpdump_arp.png ARP 请求响应 %}

ARP 响应报文则是将 ARP 请求包中的__以太网源地址__设置为响应主机的以太网地址，同时将 ARP 请求报文中的__以太网源地址__设置为响应报文中的__以太网目的地址__，同时需要将 ARP 请求报文中的 __发送端以太网地址__和__发送端 IP 地址__分别设置为 ARP 响应报文中的 __目的端以太网地址__和__目的端 IP 地址__，ARP 请求报文中的 __目的端 IP 地址__设置为 ARP 响应报文的__发送端 IP 地址__，并将该 IP 地址所在网卡的 MAC 地址设置为 ARP 响应报文中的 __发送端以太网地址__，最后更新 __op__ 为 `2`，即 ARP 响应。

## 免费 ARP

如果在 ARP 请求报文中的__目的端 IP 地址__和__发送端 IP 地址__相同时会出现什么情况呢？这种情况属于 ARP 的一种特性，即免费 ARP （Gratuitous ARP）。

免费ARP可以有两个方面的作用：

1. 一个主机可以通过它来确定另一个主机是否设置了相同的IP地址。
2. 通过发送免费 ARP 来更新局域网中该 IP 地址对应的 MAC 地址，即刷新局域网主机的 ARP 缓存。

我们可以通过 `arping -I interface -U ipaddress` 来发送免费 ARP。

## 关于 ARP 的编程

在 Linux 平台上，`<netinet/if_ether.h>` 头文件中定义了 ARP 地址解析协议的数据结构，如下所示：

``` C
/*
 * Ethernet Address Resolution Protocol.
 *
 * See RFC 826 for protocol description.  Structure below is adapted
 * to resolving internet addresses.  Field names used correspond to
 * RFC 826.
 */
struct  ether_arp {
        struct  arphdr ea_hdr;          /* fixed-size header */
        uint8_t arp_sha[ETH_ALEN];      /* sender hardware address */
        uint8_t arp_spa[4];             /* sender protocol address */
        uint8_t arp_tha[ETH_ALEN];      /* target hardware address */
        uint8_t arp_tpa[4];             /* target protocol address */
};
#define arp_hrd ea_hdr.ar_hrd
#define arp_pro ea_hdr.ar_pro
#define arp_hln ea_hdr.ar_hln
#define arp_pln ea_hdr.ar_pln
#define arp_op  ea_hdr.ar_op
```

`struct arphdr` 则定义在 `<net/if_arp.h>` 头文件中，如下所示：

``` C
/* ARP protocol opcodes. */
#define ARPOP_REQUEST   1               /* ARP request.  */
#define ARPOP_REPLY     2               /* ARP reply.  */
#define ARPOP_RREQUEST  3               /* RARP request.  */
#define ARPOP_RREPLY    4               /* RARP reply.  */
#define ARPOP_InREQUEST 8               /* InARP request.  */
#define ARPOP_InREPLY   9               /* InARP reply.  */
#define ARPOP_NAK       10              /* (ATM)ARP NAK.  */

/* See RFC 826 for protocol description.  ARP packets are variable
   in size; the arphdr structure defines the fixed-length portion.
   Protocol type values are the same as those for 10 Mb/s Ethernet.
   It is followed by the variable-sized fields ar_sha, arp_spa,
   arp_tha and arp_tpa in that order, according to the lengths
   specified.  Field names used correspond to RFC 826.  */

struct arphdr
  {
    unsigned short int ar_hrd;          /* Format of hardware address.  */
    unsigned short int ar_pro;          /* Format of protocol address.  */
    unsigned char ar_hln;               /* Length of hardware address.  */
    unsigned char ar_pln;               /* Length of protocol address.  */
    unsigned short int ar_op;           /* ARP opcode (command).  */
#if 0
    /* Ethernet looks like this : This bit is variable sized
       however...  */
    unsigned char __ar_sha[ETH_ALEN];   /* Sender hardware address.  */
    unsigned char __ar_sip[4];          /* Sender IP address.  */
    unsigned char __ar_tha[ETH_ALEN];   /* Target hardware address.  */
    unsigned char __ar_tip[4];          /* Target IP address.  */
#endif
  };
```

而以太网首都则定义在 `<net/ethernet.h>` 头文件中，如下所示：

``` C
/* This is a name for the 48 bit ethernet address available on many
   systems.  */
struct ether_addr
{
  uint8_t ether_addr_octet[ETH_ALEN];
} __attribute__ ((__packed__));

/* 10Mb/s ethernet header */
struct ether_header
{
  uint8_t  ether_dhost[ETH_ALEN];       /* destination eth addr */
  uint8_t  ether_shost[ETH_ALEN];       /* source ether addr    */
  uint16_t ether_type;                  /* packet type ID field */
} __attribute__ ((__packed__));

/* Ethernet protocol ID's */
#define ETHERTYPE_PUP           0x0200          /* Xerox PUP */
#define ETHERTYPE_SPRITE        0x0500          /* Sprite */
#define ETHERTYPE_IP            0x0800          /* IP */
#define ETHERTYPE_ARP           0x0806          /* Address resolution */
#define ETHERTYPE_REVARP        0x8035          /* Reverse ARP */
#define ETHERTYPE_AT            0x809B          /* AppleTalk protocol */
#define ETHERTYPE_AARP          0x80F3          /* AppleTalk ARP */
#define ETHERTYPE_VLAN          0x8100          /* IEEE 802.1Q VLAN tagging */
#define ETHERTYPE_IPX           0x8137          /* IPX */
#define ETHERTYPE_IPV6          0x86dd          /* IP protocol version 6 */
#define ETHERTYPE_LOOPBACK      0x9000          /* used to test interfaces */


#define ETHER_ADDR_LEN  ETH_ALEN                 /* size of ethernet addr */
#define ETHER_TYPE_LEN  2                        /* bytes in type field */
#define ETHER_CRC_LEN   4                        /* bytes in CRC field */
#define ETHER_HDR_LEN   ETH_HLEN                 /* total octets in header */
#define ETHER_MIN_LEN   (ETH_ZLEN + ETHER_CRC_LEN) /* min packet length */
#define ETHER_MAX_LEN   (ETH_FRAME_LEN + ETHER_CRC_LEN) /* max packet length */
```

## 参考

[1] https://tools.ietf.org/rfc/rfc826.txt
[2] [TCP/IP 详解，卷 1： 协议 - 第 4 章 ARP 地址解析协议](http://docs.52im.net/extend/docs/book/tcpip/vol1/4/)


[RFC 826]: https://tools.ietf.org/rfc/rfc826.txt
