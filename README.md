# tencent-cache-cleaner

macOS 上定期清理微信 / QQ / Chrome 占用的磁盘空间，**保留全部聊天文字记录**，只删三个月以上的图片、视频、文件，以及各类纯缓存。

> Periodically reclaim disk space from WeChat / QQ / Chrome on macOS. Chat databases are never touched — only media older than 90 days and pure caches are removed.

实测在一台用了一年多的机器上清出 **3.5 GB**：微信 3.4G→2.2G，QQ 1.2G→647M，Chrome 网页缓存 1.5G→2M。

## 它删什么，不删什么

| 保留 | 删除 |
| --- | --- |
| 微信 `db_storage/`（聊天文字、联系人、会话） | 90 天前的图片**原图**、视频、聊天文件、语音 |
| QQ `nt_db/`（聊天文字） | 微信视频号播放缓存 `app_data/radium` |
| **所有图片的缩略图**（`*_t.dat`、`Thumb/`） | QQ webview 缓存 `Partitions` |
| Chrome 书签 / 历史 / Cookie / 登录信息 / 扩展 | Chrome 网页缓存、shader 缓存、crx 安装包缓存 |
| Chrome `IndexedDB`、`Service Worker` | 三者的日志、崩溃信息、tmp |
| Chrome `OptGuideOnDeviceModel`（本地 AI 模型，4GB） | |

保留缩略图是有意的：翻旧聊天记录时图片位置仍显示小图，不会变成一片空白，而缩略图只有原图的 5%～10% 大小。

Chrome 那个 4GB 的 `OptGuideOnDeviceModel` 是内置的本地 AI 模型，脚本**不碰它**——删了 Chrome 会在联网时静默重新下载，白删。真想省这 4GB，得先去 `chrome://flags` 关掉 on-device model 再手工删除。

## 安全设计

- **硬闸门**：任何路径只要命中 `db_storage`、`nt_db`、`Default/IndexedDB`、`Default/Extensions`，`guard()` 直接拒绝删除并报错，即使清理规则写错也删不到真实数据。
- **默认预演**：不加参数运行只统计、不删除。必须显式传 `--yes` 才真正删。
- **运行中跳过**：未启用 `--restart-apps` 时，检测到 App 正在运行就跳过其被占用的缓存目录，避免边跑边删导致损坏。
- **按目录日期判断**：微信和 QQ 的媒体本身按 `YYYY-MM` 分目录存放，脚本据此判断年龄，不依赖容易被改写的文件 mtime。

## 用法

```bash
git clone https://github.com/HarperC7/tencent-cache-cleaner.git
cd tencent-cache-cleaner

bash tencent-cleaner.sh                      # 预演：只报告能清多少，不删任何东西
bash tencent-cleaner.sh --yes                # 执行（App 在运行则跳过其缓存）
bash tencent-cleaner.sh --yes --restart-apps # 关掉三个 App → 彻底清理 → 重新打开

./install.sh                                 # 安装定时任务
```

改保留期：编辑脚本顶部的 `RETAIN_DAYS=90`。

## 定时策略

`install.sh` 注册的 LaunchAgent **每天 15:00 唤醒**，但脚本自身用状态机控制真正的执行时机：

- 每月 1 号执行一次，成功后当月不再执行
- 失败（例如某个 App 有未保存的对话框而无法退出）则 2 号、3 号同一时间各重试一次
- 三次都失败就跳过本月，下个月 1 号重来

状态记在 `~/Library/Application Support/tencent-cleaner/state`，日志在 `~/Library/Logs/tencent-cleaner.log`。

定时执行走 `--scheduled`，它隐含 `--restart-apps`：会先关掉微信、QQ、Chrome，清理完再按原样重新打开（只重开原本就在运行的那些）。

> **注意**：15:00 大概率是你在用电脑的时间，自动关闭微信/QQ/Chrome 会打断手头的事。介意的话把 `Hour` 改成半夜，或改用 `--yes`（不关 App，代价是清不掉被占用的那部分缓存）。

## 卸载

```bash
launchctl unload ~/Library/LaunchAgents/com.tencentcleaner.monthly.plist
rm ~/Library/LaunchAgents/com.tencentcleaner.monthly.plist ~/bin/tencent-cleaner.sh
rm -rf ~/Library/Application\ Support/tencent-cleaner
```

## 适用范围

在 macOS 15 (Darwin 25)、微信 4.0 (`2.0b4.0.9`)、QQ NT 版、Chrome 152 上验证。旧版微信 3.x 目录结构不同（`Message/MessageTemp`），本脚本不适用。

删除是永久的，不进废纸篓。**第一次务必先跑预演。**

## License

MIT
