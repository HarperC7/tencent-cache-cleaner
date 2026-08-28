# tencent-cache-cleaner

macOS 上定期清理微信 / QQ 占用的磁盘空间，**保留全部聊天文字记录**，只删三个月以上的图片、视频、文件，以及各类纯缓存。

> Periodically reclaim disk space from WeChat / QQ on macOS. Chat text databases are never touched — only media older than 90 days and pure caches are removed.

实测在一台用了一年多的机器上，一次清出 **1.8 GB**（微信 3.4G→2.2G，QQ 1.2G→647M）。

## 它删什么，不删什么

| 保留 | 删除 |
| --- | --- |
| 微信 `db_storage/`（聊天文字、联系人、会话） | 90 天前的图片**原图**、视频、聊天文件、语音 |
| QQ `nt_db/`（聊天文字） | 微信视频号播放缓存 `app_data/radium` |
| **所有图片的缩略图**（`*_t.dat`、`Thumb/`） | QQ webview 缓存 `Partitions` |
| 90 天内的一切 | 两者的日志、崩溃信息、tmp、profiles 缓存 |

保留缩略图是有意的：翻旧聊天记录时图片位置仍显示小图，不会变成一片空白，而缩略图只有原图的 5%～10% 大小。

## 安全设计

- **硬闸门**：任何路径只要命中 `db_storage`、`nt_db`，`guard()` 直接拒绝删除并报错，即使清理规则写错也删不到聊天记录。
- **默认预演**：不加参数运行只统计、不删除。必须显式传 `--yes` 才真正删。
- **运行中跳过**：检测到微信/QQ 正在运行时，自动跳过被内存映射的缓存目录（`radium`、`Partitions`），避免边跑边删导致损坏。这也是定时任务设在半夜的原因。
- **按目录日期判断**：微信和 QQ 的媒体本身就按 `YYYY-MM` 分目录存放，脚本据此判断年龄，不依赖容易被改写的文件 mtime。

## 用法

```bash
git clone https://github.com/HarperC7/tencent-cache-cleaner.git
cd tencent-cache-cleaner

bash tencent-cleaner.sh          # 预演：只报告能清多少，不删任何东西
bash tencent-cleaner.sh --yes    # 真正执行

./install.sh                     # 装到 ~/bin 并注册每月 1 号 00:00 自动运行
```

想彻底清干净，先退出微信和 QQ 再跑 `--yes`，否则那部分缓存会被跳过。

改保留期：编辑脚本顶部的 `RETAIN_DAYS=90`。

## 卸载

```bash
launchctl unload ~/Library/LaunchAgents/com.tencentcleaner.monthly.plist
rm ~/Library/LaunchAgents/com.tencentcleaner.monthly.plist ~/bin/tencent-cleaner.sh
```

## 适用范围

在 macOS 15 (Darwin 25) + 微信 4.0 (`2.0b4.0.9`) + QQ NT 版上验证。旧版微信 3.x 的目录结构不同（`Message/MessageTemp`），本脚本不适用。

删除是永久的，不进废纸篓。**第一次务必先跑预演。**

## License

MIT
