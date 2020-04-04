---
title: "PyInstaller 打包 PyQt5 失败 - 执行脚本失败"
date: 2019-07-21 10:06:18 +0800
category: Programming
tags:
  - Python
  - PyQt5
  - PyInstaller
---

最近用 Python 帮人写一个程序，主体工作完成之后，利用 PyQt 写了一个界面，通过命令行运行一切正常，然后，利用 PyInstaller 打包成一个单独的可执行文件时，问题就来了:( 。我使用打包命令如下：

```
pyinstaller -F -w xxx.py
```

运行可执行文件时，弹出的对话框显示如下信息，此外就没有别的其它信息了。

```
"failed to execute script xxx"
```

<!-- more -->

## 环境

| 类别        | 说明        |
|-------------|-------------|
| 操作系统    | Windows 10  |
| PyQt5       | 5.13.0      |
| Python      | 3.7.4       |
| PyInstaller | 3.5         |


## 问题追溯

但从上面的错误无法得到更多的信息，因此，我尝试使用 `-c` 的打包方式，即在程序后端运行一个终端。其打包命令如下：

```
pyinstaller -F -c xxx.py
```

这是再次运行，可以后终端中看到如下错误：

```
Traceback (most recent call last):
  File "gui.py", line 8, in <module>
    from PyQt5.QtCore import Qt
  File "c:\python37-32\lib\site-packages\PyInstaller\loader\pyimod03_importers.py", line 627, in exec_module
    exec(bytecode, module.__dict__)
  File "site-packages\PyQt5\__init__.py", line 41, in <module>
  File "site-packages\PyQt5\__init__.py", line 33, in find_qt
ImportError: unable to find Qt5Core.dll on PATH
[6852] Failed to execute script gui
```

此时，问题就比较明显了，程序运行时缺少 `Qt5Core.dll` 动态库。此时，我尝试把 `Qt5Core.dll` 文件拷贝到当前目录后，再次运行依然出现上述问题。

搜索时发现这个问题还是个普遍问题，大家都遇到了，具体参考[这里](https://github.com/pyinstaller/pyinstaller/issues/4293)。

## 解决

在 PyQt5.13 中，其 `__init__.py` 文件内容如下：

``` Python
# Copyright (c) 2019 Riverbank Computing Limited <info@riverbankcomputing.com>
#
# This file is part of PyQt5.
#
# This file may be used under the terms of the GNU General Public License
# version 3.0 as published by the Free Software Foundation and appearing in
# the file LICENSE included in the packaging of this file.  Please review the
# following information to ensure the GNU General Public License version 3.0
# requirements will be met: http://www.gnu.org/copyleft/gpl.html.
#
# If you do not wish to use this file under the terms of the GPL version 3.0
# then you may purchase a commercial license.  For more information contact
# info@riverbankcomputing.com.
#
# This file is provided AS IS with NO WARRANTY OF ANY KIND, INCLUDING THE
# WARRANTY OF DESIGN, MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.


def find_qt():
    import os

    path = os.environ['PATH']

    dll_dir = os.path.dirname(__file__) + '\\Qt\\bin'
    if os.path.isfile(dll_dir + '\\Qt5Core.dll'):
        path = dll_dir + ';' + path
        os.environ['PATH'] = path
    else:
        for dll_dir in path.split(';'):
            if os.path.isfile(dll_dir + '\\Qt5Core.dll'):
                break
        else:
            raise ImportError("unable to find Qt5Core.dll on PATH")

    try:
        os.add_dll_directory(dll_dir)
    except AttributeError:
        pass


find_qt()
del find_qt
```

从上面可以看到，错误是在 `raise ImportError("unable to find Qt5Core.dll on PATH")` 这里报出来。这段代码的大致意思就是在系统的环境变量 PATH 路径下去找 `Qt5Core.dll` 文件，而实际上这个文件并不在 PATH 路径下。

我们在使用 PyInstaller 打包时，指定 `-F` 选项理论上是会将 `Qt5Core.dll` 文件打包进可执行文件的，但是由于 PyQT5.13 默认在系统 PATH 路径下查找，因此出错了。

我们可以将下面的内容注释掉，然后一切运行正常。
```
        else:
            raise ImportError("unable to find Qt5Core.dll on PATH")
```

当然，我们也可以使用之前版本的代码替换现有代码。

``` python
import os as _os

_path = _os.path.dirname(__file__) + '\\Qt\\bin;' + _os.environ['PATH']
_os.environ['PATH'] = _path
```

经过修改后，再次打包运行一切正常。

## 参考

[1] https://github.com/pyinstaller/pyinstaller/issues/4293#issuecomment-507254991
