---
title: 关于我
date: 2020-08-23 15:55:41
type: about
comments: false
toc:
  enable: false
---

<div class="custom-black"></div>

{% note primary %}

## 基本信息

* 从事 PostgreSQL 数据库相关开发

{% endnote %}

{% note success %}

## 专业技能

* C
* Python
* Golang
* PostgreSQL
* GDB

{% endnote %}

{% note danger %}

## 演讲稿

* [2022-10-22 - 如何参与 PostgreSQL 贡献](./files/2022-10-22.How.to.Contribute.PostgreSQL.pdf)

{% endnote %}



{% note info %}

## 在线工具

* [crontab guru](https://crontab.guru/) - 用于 cron 计划表达式的快速简单的在线编辑器。
* [Compiler Explorer](https://godbolt.org/) - 一个在线的交互式编译器，可以展示 C++, Rust，Go 以及其他代码的汇编语言。
* [Real Favicon Generator](https://realfavicongenerator.net/) - Favicon 生成器。
* [PlantText](https://www.planttext.com/) - [PlantUML](https://plantuml.com/) 在线绘图工具。

{% endnote %}

{% note warning %}

## 更新日志

* [x] 2022-02-28 - 启用 mathjax 功能，支持 LaTeX 数学公式渲染。
* [x] 2022-01-07 - 添加评论系统，使用 utterances 实现，需要 Github 账号。
* [x] 2021-09-18 - 将收集的常用工具移到关于页面中。
* [x] 2021-09-15 - 博客主题升级到 NexT v8.7.1。
* [x] 2021-08-06 - 添加工具页面，用于收集常用的工具。
* [x] 2021-07-17 - 修改文章显示的时间为文章创建的时间，不采用文章更新时间，避免在不同电脑上导致不一致的情况。
* [x] 2021-05-13 - 移除 valine 热榜、评论和文章浏览记录（没有手机号卖）。
* [x] 2020-08-29 - 添加近期文章板块。
* [x] 2020-08-23 - 博客主题升级到 NexT (v8.0.0-rc.5) 。

{% endnote %}

<!--
* Ubuntu PostgreSQL

#+begin_src bash
  sudo apt-get install vim emacs git tmux
  sudo apt-get install global gdb silversearcher-ag
  sudo apt-get install build-essential
  sudo apt-get install clangd-12 clang-12
  sudo update-alternatives --install /usr/bin/clangd clangd /usr/bin/clangd-12 100
  sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-12 100
  sudo update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-12 100
  sudo apt-get install pkg-config bison flex
  sudo apt-get install libreadline-dev zlib1g-dev

  sudo apt-get install libipc-run-perl # --enable-tap-tests
  sudo apt-get install libicu-dev      # --with-icu
  sudo apt-get install libkrb5-dev     # --with-gssapi
  sudo apt-get install libssl-dev      # --with-openssl
  sudo apt-get install libldap2-dev   # --with-ldap
  sudo apt-get install libxml2-dev     # --with-libxml
  sudo apt-get install libxslt1-dev    # --with-libxslt
  sudo apt-get install libpam0g-dev    # --with-pam
  sudo apt-get install libselinux1-dev # --with-selinux
  sudo apt-get install uuid-dev        # --with-uuid=e2fs
  sudo apt-get install libsystemd-dev  # --with-systemd
  sudo apt-get install gettext         # --enable-nls
  sudo apt-get install libperl-dev     # --with-perl
  sudo apt-get install libpython3-dev  # --with-python
#+end_src

Or, you can use the following command to install IPC::Run.

#+begin_src bash
  $ cpan    # --enable-tap-tests
  cpan[1]> install IPC::Run
#+end_src

* CentOS

#+begin_src bash
  sudo yum install -y centos-release-scl
  sudo yum install -y devtoolset-11
  sudo yum install -y git

  sudo yum install -y zlib-devel.x86_64
  sudo yum install -y readline-devel.x86_64

  sudo yum install -y devtoolset-11-systemtap-sdt-devel  # --enable-dtrace
  sudo yum install -y krb5-devel.x86_64                  # --with-gssapi
  sudo yum install -y libicu-devel                       # --with-icu
  sudo yum install -y libuuid-devel.x86_64               # --with-uuid=e2fs
  sudo yum install -y libxml2-devel.x86_64               # --with-libxml
  sudo yum install -y libxslt-devel.x86_64               # --with-libxslt
  sudo yum install -y llvm-toolset-7-llvm-devel.x86_64   # --with-llvm
  sudo yum install -y llvm-toolset-7.0-llvm-devel.x86_64
  sudo yum install -y llvm-toolset-7.0.x86_64            # --with-llvm
  sudo yum install -y lz4-devel.x86_64                   # --wit-lz4
  sudo yum install -y openldap-devel.x86_64              # --with-ldap
  sudo yum install -y openssl-devel.x86_64               # --with-openssl
  sudo yum install -y pam-devel.x86_64                   # --with-pam
  sudo yum install -y python3-devel.x86_64               # --with-python
  sudo yum install -y systemd-devel.x86_64               # --with-systemd

  # regression test
  sudo yum install -y perl-Test-Harness-3.28-3.el7.noarch
  sudo yum install -y perl-tests.x86_64
  sudo yum install -y perl-IPC-Run.noarch

  # make a RPM package
  sudo yum install -y rpmdevtools.noarch
#+end_src

#+begin_src bash
$ cpan
cpan[1]> install IPC::Run
#+end_src

#+begin_src bash
  sudo yum -y remove git
  sudo yum -y install https://packages.endpointdev.com/rhel/7/os/x86_64/endpoint-repo.x86_64.rpm
  sudo yum -y install git
#+end_src
-->
