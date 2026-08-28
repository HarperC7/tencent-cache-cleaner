#!/bin/bash
# 微信 / QQ 缓存清理 —— 只删媒体与缓存，聊天文字一律保留
# 用法: clean.sh          预演，只报告不删
#       clean.sh --yes    真正删除
set -uo pipefail

RETAIN_DAYS=90
CUT_MONTH=$(date -v-${RETAIN_DAYS}d +%Y-%m)
DRY=1; [ "${1:-}" = "--yes" ] && DRY=0

FREED=0            # KB
declare -a NOTES=()

WX_ROOT="$HOME/Library/Containers/com.tencent.xinWeChat/Data"
QQ_ROOT="$HOME/Library/Containers/com.tencent.qq/Data"

running(){ pgrep -qx "$1"; }

# ---- 安全闸门：聊天记录数据库永不删除 ----------------------------------
guard(){
  case "$1" in
    *db_storage*|*nt_db*|*/Documents/xwechat_files/*/config*)
      echo "!! 已阻止删除受保护路径: $1" >&2; return 1;;
  esac
  return 0
}

# 删除整个目录/文件
del(){
  local p="$1"; [ -e "$p" ] || return 0
  guard "$p" || return 1
  local k; k=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); FREED=$((FREED+${k:-0}))
  [ $DRY -eq 0 ] && rm -rf "$p"
  return 0
}

# 删除目录内除缩略图外的所有文件（保留 *_t.dat 与 Thumb/ 目录）
del_keep_thumb(){
  local d="$1"; [ -d "$d" ] || return 0
  guard "$d" || return 1
  local bytes
  bytes=$(find "$d" -type f ! -name '*_t.dat' ! -path '*/Thumb/*' -print0 2>/dev/null \
          | xargs -0 stat -f %z 2>/dev/null | awk '{s+=$1} END{print s+0}')
  FREED=$((FREED + bytes/1024))
  [ $DRY -eq 0 ] && find "$d" -type f ! -name '*_t.dat' ! -path '*/Thumb/*' -delete 2>/dev/null
  return 0
}

# 遍历 root 下形如 YYYY-MM 的月份目录，对早于保留期的执行 handler
each_old_month(){
  local root="$1" handler="$2" m b
  [ -d "$root" ] || return 0
  for m in "$root"/[0-9][0-9][0-9][0-9]-[0-9][0-9]; do
    [ -d "$m" ] || continue
    b=$(basename "$m")
    [[ "$b" < "$CUT_MONTH" ]] && "$handler" "$m"
  done
}

echo "=== 腾讯缓存清理 $(date '+%Y-%m-%d %H:%M') ==="
[ $DRY -eq 1 ] && echo "【预演模式】只统计，不删除"
echo "保留期: ${RETAIN_DAYS} 天（早于 ${CUT_MONTH} 的整月媒体将被清理）"
echo

# ======================= 微信 =======================
echo "--- 微信 ---"
if [ -d "$WX_ROOT" ]; then
  for U in "$WX_ROOT"/Documents/xwechat_files/*/; do
    [ -d "$U/msg" ] || continue
    each_old_month "$U/msg/file"  del            # 聊天收到的文件
    each_old_month "$U/msg/video" del            # 视频
    for H in "$U"/msg/attach/*/; do              # 图片: 留缩略图
      each_old_month "$H" del_keep_thumb
    done
    del "$U/temp"; del "$U/cache"
  done
  echo "  旧媒体已统计"

  if running WeChat; then
    NOTES+=("微信正在运行，已跳过其缓存目录（radium/日志等），避免写冲突。关掉微信再跑可多清约 750MB。")
  else
    del "$WX_ROOT/Documents/app_data/radium/web"     # 视频号播放缓存
    del "$WX_ROOT/Documents/app_data/radium/users"
    del "$WX_ROOT/Documents/app_data/radium/cache"
    del "$WX_ROOT/Documents/app_data/log"
    del "$WX_ROOT/Documents/app_data/crashinfo"
    del "$WX_ROOT/Library/Caches/profiles"
    del "$WX_ROOT/Library/Caches/com.tencent.xinWeChat"
    del "$WX_ROOT/tmp"
    echo "  视频号缓存 / 日志已清理"
  fi
else
  NOTES+=("未找到微信数据目录，已跳过。")
fi
echo

# ======================= QQ =======================
echo "--- QQ ---"
QQ_APPSUP="$QQ_ROOT/Library/Application Support/QQ"
if [ -d "$QQ_APPSUP" ]; then
  for NT in "$QQ_APPSUP"/nt_qq_*/; do
    D="$NT/nt_data"; [ -d "$D" ] || continue
    each_old_month "$D/Pic" del_keep_thumb       # Pic/YYYY-MM/{Ori,Thumb} → 只删 Ori
    each_old_month "$D/Video"    del
    each_old_month "$D/Ptt"      del             # 语音
    each_old_month "$D/dataline" del             # 手机传文件
    each_old_month "$D/File"     del
    del "$NT/nt_temp"
    if ! running QQ; then
      del "$D/log"; del "$D/log-cache"; del "$D/Emoji/emoji-recv"
    fi
  done
  echo "  旧媒体已统计"

  if running QQ; then
    NOTES+=("QQ 正在运行，已跳过其缓存目录（Partitions/日志等），避免写冲突。关掉 QQ 再跑可多清约 390MB。")
  else
    del "$QQ_APPSUP/Partitions"                  # Electron webview 缓存
    del "$QQ_APPSUP/Cache"
    del "$QQ_APPSUP/log"
    del "$QQ_ROOT/tmp"
    del "$QQ_ROOT/Library/Caches"
    echo "  webview 缓存 / 日志已清理"
  fi
else
  NOTES+=("未找到 QQ 数据目录，已跳过。")
fi
echo

MB=$((FREED/1024))
if [ $DRY -eq 1 ]; then echo "预计可释放: ${MB} MB"; else echo "实际释放: ${MB} MB"; fi
for n in "${NOTES[@]:-}"; do [ -n "$n" ] && echo "注意: $n"; done
echo "FREED_MB=${MB}"
