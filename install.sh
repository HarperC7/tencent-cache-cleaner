#!/bin/bash
# 安装到 ~/bin 并注册每月 1 号 00:00 的定时任务
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.tencentcleaner.monthly"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$HOME/bin" "$HOME/Library/LaunchAgents"
install -m 755 "$SRC/tencent-cleaner.sh" "$HOME/bin/tencent-cleaner.sh"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/bin/tencent-cleaner.sh</string>
        <string>--yes</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Day</key><integer>1</integer>
        <key>Hour</key><integer>0</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/tencent-cleaner.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/tencent-cleaner.log</string>
    <key>RunAtLoad</key><false/>
</dict>
</plist>
PLIST_EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "已安装。脚本: ~/bin/tencent-cleaner.sh"
echo "定时: 每月 1 号 00:00   日志: ~/Library/Logs/tencent-cleaner.log"
echo "先跑一次预演看看:  bash ~/bin/tencent-cleaner.sh"
