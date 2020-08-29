---
title: 热榜
date: 2020-08-29 19:42:32 +0800
comments: false
---

<div class="custom-black"></div>

<div id="hot"></div>
<script src="https://cdn1.lncld.net/static/js/av-core-mini-0.6.4.js"></script>
<script>AV.initialize("rwarexb07A58sdb9Xp5RyQRw-gzGzoHsz", "zPiGgSOJ5I1qJMAVXWBgRWe6");</script>
<script type="text/javascript">
  var time = 0
  var title = ""
  var url = ""
  var query = new AV.Query('Counter');
  query.notEqualTo('id',0);
  query.descending('time');
  query.limit(100);
  query.find().then(function (todo) {
    for (var i = 0; i < 100; i++) {
      var result = todo[i].attributes;
      time = result.time;
      title = result.title;
      url = result.url;
      var content = "<p>" +
      "<font color='#1C1C1C'>" + "【热度: " + time + " ℃】" + "</font>" +
      "<a href='" + "https://blog.japinli.top/" + url + "'>" + title + "</a>" +
      "</p>";
      document.getElementById("hot").innerHTML += content
    }
  }, function (error) {
    console.log("error");
  });
</script>
