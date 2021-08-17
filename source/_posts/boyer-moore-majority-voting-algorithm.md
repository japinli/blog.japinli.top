---
title: "【译】Boyer-Moore 多数派投票算法"
date: 2021-08-17 14:37:42
category: 算法
tags:
  - 翻译
---

{% asset_img boyer-moore.gif %}

Boyer-Moore 投票算法是流行的最优算法之一，它用于在给定元素中找出出现次数超过 `N/2` 的元素。它需要对给定元素进行 2 次遍历，其时间复杂度为 `O(N)`，空间复杂度为 `O(1)`。

<!-- more -->

让我们通过一个例子来看看其算法背后的原理。

```
输入：{1,1,1,1,2,3,5}
输出：1
解释：1 出现超过 3 次。
输入：{1,2,3}
输出：-1
```

该算法的工作原理是，如果一个元素出现超过 `N/2` 次，则意味着除此之外的其余元素肯定会小于 `N/2`。那么，让我们检查一下算法的过程。

* 首先，从给定的元素集中选择一个候选元素，如果它与候选元素相同，则增加投票数。否则，减少票数如果票数变为 `0`，则选择另一个新元素作为新候选元素。

## 背后的原理

当元素与候选元素相同时，我们增加投票数；当元素与候选元素不相同时，我们减少投票数。我们减少投票实际上意味着我们正在降低所选候选元素获胜机会，因为我们知道如果获选元素是多数，那么它出现的次数必然超过 `N/2` 次，而其余的元素则少于 `N/2` 次。当我们发现与候选元素不同的元素时，我们会持续的减少投票数。当投票数变为 `0` 时，这就意味着有相同数量的不同元素，这不应该成为多数元素的情况。因此，候选元素不能成为多数元素，所以我们选择当前的元素作为新的候选元素，并继续上述过程，直到所有元素都完成。最后的候选元素将是我们的多数元素。我们用第 2 次遍历来检查候选元素的数量是否大于 `N/2`，如果是的话，我们就认为它是多数元素。

## 实现算法的步骤

1. 找到多数的候选元素
   * 初始化变量 `i, votes = 0, candidate = -1`
   * 使用 `for` 循环遍历数组
   * 如果 `votes = 0`，则选择 `candidate = arr[i]`，并且增加投票数 `votes = 1`
   * 如果当前的元素与候选元素相同，则 `votes++`
   * 否则 `votes--`
2. 检查候选元素是否有超过 `N/2` 投票数
   * 初始化变量 `count = 0`，如果元素与候选者相同则加 `1`
   * 检查 `count > N/2`，如果是返回候选元素
   * 否则返回 `-1`

```
我们模拟上面的例子：
给定元素：
  arr[] =       1    1    1    1    2    3    5
 votes = 0      1    2    3    4    3    2    1
 candidate = -1 1    1    1    1    1    1    1
 candidate = 1  第一次遍历后
                1    1    1    1    2    3    5
 count = 0      1    2    3    4    4    4    4
 candidate = 1
 Hence count > 7/2 =3
 因此，1 是多数元素。
```

```c++
// C++ implementation for the above approach
#include <iostream>
using namespace std;
// Function to find majority element
int findMajority(int arr[], int n)
{
    int i, candidate = -1, votes = 0;
    // Finding majority candidate
    for (i = 0; i < n; i++) {
        if (votes == 0) {
            candidate = arr[i];
            votes = 1;
        }
        else {
            if (arr[i] == candidate)
                votes++;
            else
                votes--;
        }
    }
    int count = 0;
    // Checking if majority candidate occurs more than n/2
    // times
    for (i = 0; i < n; i++) {
        if (arr[i] == candidate) {
            count++;
        }
    }

    if (count > n / 2)
        return candidate;
    else
        return -1;
}
int main()
{
    int arr[] = { 1, 1, 1, 1, 2, 3, 4 };
    int n = sizeof(arr) / sizeof(arr[0]);
    int majority = findMajority(arr, n);
    cout << " The majority element is : " << majority;
    return 0;
}
```

__时间复杂度：__ `O(n)`（对于数组的两次遍历）
__空间复杂度：__ `O(1)`


## 原文

[1] https://www.geeksforgeeks.org/boyer-moore-majority-voting-algorithm/

## 译者著

该算法来自于 [MJRTY - A Fast Majority Vote Algorithm](https://www.cs.ou.edu/~rlpage/dmtools/mjrty.pdf) 论文。您可以在[这里](https://www.cs.utexas.edu/~moore/best-ideas/mjrty/index.html)看到算法的演示。
