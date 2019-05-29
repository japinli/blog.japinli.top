---
title: "PyQt5 信号槽自定义参数"
date: 2019-04-14 21:45:29
category: Programming
tags: PyQt5
---

我们知道 PyQt5 利用信号和槽在对象之间传递数据，当特定的事件发生时，信号将通过 `emit` 发出，槽则负责响应该信号。QT 中的对象已经包含了非常多信号的定义。本文对信号槽的使用不做具体介绍，感兴趣的朋友可以参考[这里](https://www.riverbankcomputing.com/static/Docs/PyQt5/signals_slots.html)，我在这里主要记录如何对信号传递用户自定义参数。

<!-- more -->

## 示例

下面我想给出一个典型的示例程序，在这个程序中我只是简单的添加一个按钮，然后给出按钮被按下的次数，完整的代码如下所示：

``` python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
from PyQt5.QtWidgets import QLabel
from PyQt5.QtWidgets import QWidget
from PyQt5.QtWidgets import QPushButton
from PyQt5.QtWidgets import QHBoxLayout
from PyQt5.QtWidgets import QMainWindow
from PyQt5.QtWidgets import QApplication

class TestApp(QMainWindow):

    def __init__(self):
        super().__init__()
        self.clicknum = 1

        hbox = QHBoxLayout()
        self.label = QLabel('Hello')
        self.button = QPushButton('click me')
        self.button.clicked.connect(self.clickMe)
        hbox.addWidget(self.button)
        hbox.addWidget(self.label)
        widget = QWidget()
        widget.setLayout(hbox)
        self.setCentralWidget(widget)
        self.show()

    def clickMe(self):
        if self.clicknum > 1:
            message = 'click: {0} times'.format(self.clicknum)
        else:
            message = 'click: {0} time'.format(self.clicknum)

        self.label.setText(message)
        self.clicknum += 1

if __name__ == '__main__':
    app = QApplication(sys.argv)
    testapp = TestApp()
    sys.exit(app.exec_())

```

上面的程序非常简单，就是记录从程序开始运行到结束时一共按了多少次按钮。

{% asset_img simple-test.png %}

## 参数传递

其实此处我主要是为了演示而特意给出这个不太符合常理的做法 (相当的无厘头)。下面请看代码：

``` python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
from PyQt5.QtWidgets import QLabel
from PyQt5.QtWidgets import QWidget
from PyQt5.QtWidgets import QPushButton
from PyQt5.QtWidgets import QHBoxLayout
from PyQt5.QtWidgets import QMainWindow
from PyQt5.QtWidgets import QApplication

class TestApp(QMainWindow):

    def __init__(self):
        super().__init__()
        self.clicknum = 1

        hbox = QHBoxLayout()
        self.label = QLabel('Hello')
        self.button = QPushButton('click me')
        self.button.clicked.connect(lambda: self.clickMe(self.clicknum))
        hbox.addWidget(self.button)
        hbox.addWidget(self.label)
        widget = QWidget()
        widget.setLayout(hbox)
        self.setCentralWidget(widget)
        self.show()

    def clickMe(self, clicknum):
        if clicknum > 1:
            message = 'click: {0} times'.format(clicknum)
        else:
            message = 'click: {0} time'.format(clicknum)

        self.label.setText(message)
        self.clicknum += 1

if __name__ == '__main__':
    app = QApplication(sys.argv)
    testapp = TestApp()
    sys.exit(app.exec_())
```

在上面的例子中，我们将按钮所关联的槽使用 `lambda` 方式给出，并为它赋予了一个参数。这样每次在信号被触发时，`self.clicknum` 的值都将被传递过去。

## 参考

[1] [Passing extra arguments to PyQt slots](https://eli.thegreenplace.net/2011/04/25/passing-extra-arguments-to-pyqt-slot/)
