#!/bin/bash
# 微信 / QQ / Chrome 磁盘清理 —— 只删媒体与缓存，聊天文字一律保留
#
#   clean.sh                        预演，只报告不删
#   clean.sh --yes                  立即清理（App 若在运行则跳过其缓存目录）
#   clean.sh --yes --restart-apps   关掉 App → 彻底清理 → 重新打开
#   clean.sh --scheduled            定时入口：每月 1 号执行，失败则 2、3 号重试，
#                                   三次都失败则跳过本月
set -uo pipefail
export LANG="${LANG:-en_US.UTF-8}"

RETAIN_DAYS=90
MAX_ATTEMPTS=3
STATE_DIR="$HOME/Library/Application Support/tencent-cleaner"
STATE="$STATE_DIR/state"

CUT_MONTH=$(date -v-${RETAIN_DAYS}d +%Y-%m)
DRY=1; RESTART=0; SCHEDULED=0
for a in "$@"; do case "$a" in
  --yes)          DRY=0 ;;
  --restart-apps) RESTART=1 ;;
  --scheduled)    SCHEDULED=1; DRY=0; RESTART=1 ;;
esac; done

FREED=0
declare -a NOTES=()
APPS=("WeChat" "QQ" "Google Chrome")
declare -a RELAUNCH=()

WX_ROOT="$HOME/Library/Containers/com.tencent.xinWeChat/Data"
QQ_ROOT="$HOME/Library/Containers/com.tencent.qq/Data"
CR_SUP="$HOME/Library/Application Support/Google/Chrome"
CR_CACHE="$HOME/Library/Caches/Google/Chrome"

running(){ pgrep -x "$1" >/dev/null 2>&1; }

# ---- 每月一次的调度闸门 ------------------------------------------------
MONTH=$(date +%Y-%m); DAY=$(date +%d); DAY=${DAY#0}
LAST_SUCCESS_MONTH=""; ATTEMPT_MONTH=""; ATTEMPTS=0
[ -f "$STATE" ] && . "$STATE"
[ "$ATTEMPT_MONTH" != "$MONTH" ] && ATTEMPTS=0

save_state(){
  mkdir -p "$STATE_DIR"
  printf 'LAST_SUCCESS_MONTH="%s"\nATTEMPT_MONTH="%s"\nATTEMPTS=%s\n' \
    "$LAST_SUCCESS_MONTH" "$MONTH" "$ATTEMPTS" > "$STATE"
}

if [ $SCHEDULED -eq 1 ]; then
  if [ "$LAST_SUCCESS_MONTH" = "$MONTH" ]; then
    echo "$(date '+%F %T') 本月（${MONTH}）已成功清理，跳过。"; exit 0; fi
  if [ "$DAY" -gt "$MAX_ATTEMPTS" ]; then exit 0; fi
  if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then
    echo "$(date '+%F %T') 本月已尝试 ${ATTEMPTS} 次均失败，跳过本月。"; exit 0; fi
  echo "$(date '+%F %T') 第 $((ATTEMPTS+1)) 次尝试（每月上限 ${MAX_ATTEMPTS} 次）"
fi

fail(){
  echo "!! 失败: $*"
  if [ $SCHEDULED -eq 1 ]; then
    ATTEMPTS=$((ATTEMPTS+1)); save_state
    if [ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]; then echo "已达本月上限，下月再试。"
    else echo "明天同一时间重试。"; fi
  fi
  exit 1
}

# ---- 安全闸门：聊天记录数据库永不删除 ----------------------------------
guard(){
  case "$1" in
    *db_storage*|*nt_db*|*/xwechat_files/*/config*|*/Default/IndexedDB*|*/Default/Extensions*)
      echo "!! 已阻止删除受保护路径: $1" >&2; return 1;;
  esac
  return 0
}

del(){
  local p="$1"; [ -e "$p" ] || return 0
  guard "$p" || return 1
  local k; k=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); FREED=$((FREED+${k:-0}))
  [ $DRY -eq 0 ] && rm -rf "$p"
  return 0
}

# 只删目录内容，保留目录本身（用于 App 期望其存在的缓存目录）
del_contents(){
  local d="$1"; [ -d "$d" ] || return 0
  guard "$d" || return 1
  local k; k=$(du -sk "$d" 2>/dev/null | awk '{print $1}'); FREED=$((FREED+${k:-0}))
  [ $DRY -eq 0 ] && find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  return 0
}

# 删除目录内除缩略图外的所有文件（保留 *_t.dat 与 Thumb/）
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

each_old_month(){
  local root="$1" handler="$2" m b
  [ -d "$root" ] || return 0
  for m in "$root"/[0-9][0-9][0-9][0-9]-[0-9][0-9]; do
    [ -d "$m" ] || continue
    b=$(basename "$m")
    [[ "$b" < "$CUT_MONTH" ]] && "$handler" "$m"
  done
}

# ---- 关闭 App -----------------------------------------------------------
quit_apps(){
  local a i
  for a in "${APPS[@]}"; do
    running "$a" || continue
    RELAUNCH+=("$a")
    echo "  正在退出 $a ..."
    osascript -e "quit app \"$a\"" >/dev/null 2>&1
    for i in $(seq 1 24); do running "$a" || break; sleep 0.5; done
    running "$a" && fail "$a 未能在 12 秒内退出（可能有未保存的对话框）"
  done
  [ ${#RELAUNCH[@]} -gt 0 ] && sleep 2
  return 0
}

relaunch_apps(){
  local a
  for a in "${RELAUNCH[@]:-}"; do
    [ -n "$a" ] || continue
    echo "  重新打开 $a"
    open -a "$a" >/dev/null 2>&1
  done
}

echo "=== 磁盘清理 $(date '+%Y-%m-%d %H:%M') ==="
[ $DRY -eq 1 ] && echo "【预演模式】只统计，不删除"
echo "保留期: ${RETAIN_DAYS} 天（早于 ${CUT_MONTH} 的整月媒体将被清理）"
echo

if [ $RESTART -eq 1 ] && [ $DRY -eq 0 ]; then
  echo "--- 关闭 App ---"; quit_apps; echo
fi

# ======================= 微信 =======================
echo "--- 微信 ---"
if [ -d "$WX_ROOT" ]; then
  for U in "$WX_ROOT"/Documents/xwechat_files/*/; do
    [ -d "$U/msg" ] || continue
    each_old_month "$U/msg/file"  del
    each_old_month "$U/msg/video" del
    for H in "$U"/msg/attach/*/; do each_old_month "$H" del_keep_thumb; done
    del "$U/temp"; del "$U/cache"
  done
  echo "  旧媒体已统计"
  if running WeChat; then
    NOTES+=("微信在运行，已跳过其缓存目录。")
  else
    del "$WX_ROOT/Documents/app_data/radium/web"
    del "$WX_ROOT/Documents/app_data/radium/users"
    del "$WX_ROOT/Documents/app_data/radium/cache"
    del "$WX_ROOT/Documents/app_data/log"
    del "$WX_ROOT/Documents/app_data/crashinfo"
    del "$WX_ROOT/Library/Caches/profiles"
    del "$WX_ROOT/Library/Caches/com.tencent.xinWeChat"
    del "$WX_ROOT/tmp"
    echo "  视频号缓存 / 日志已清理"
  fi
else NOTES+=("未找到微信数据目录。"); fi
echo

# ======================= QQ =======================
echo "--- QQ ---"
QQ_APPSUP="$QQ_ROOT/Library/Application Support/QQ"
if [ -d "$QQ_APPSUP" ]; then
  for NT in "$QQ_APPSUP"/nt_qq_*/; do
    D="$NT/nt_data"; [ -d "$D" ] || continue
    each_old_month "$D/Pic" del_keep_thumb
    each_old_month "$D/Video"    del
    each_old_month "$D/Ptt"      del
    each_old_month "$D/dataline" del
    each_old_month "$D/File"     del
    del "$NT/nt_temp"
    if ! running QQ; then
      del "$D/log"; del "$D/log-cache"; del "$D/Emoji/emoji-recv"
    fi
  done
  echo "  旧媒体已统计"
  if running QQ; then
    NOTES+=("QQ 在运行，已跳过其缓存目录。")
  else
    del "$QQ_APPSUP/Partitions"; del "$QQ_APPSUP/Cache"; del "$QQ_APPSUP/log"
    del "$QQ_ROOT/tmp"; del "$QQ_ROOT/Library/Caches"
    echo "  webview 缓存 / 日志已清理"
  fi
else NOTES+=("未找到 QQ 数据目录。"); fi
echo

# ======================= Chrome =======================
# 只清纯缓存：不动书签、历史、Cookie、扩展、IndexedDB、Service Worker，
# 也不动 OptGuideOnDeviceModel（本地 AI 模型，删了会自动重下）。
echo "--- Chrome ---"
if [ -d "$CR_SUP" ]; then
  if running "Google Chrome"; then
    NOTES+=("Chrome 在运行，已整体跳过（缓存文件被占用，运行中删除会导致缓存报错）。")
  else
    del_contents "$CR_CACHE"                       # 网页缓存，最大头
    del "$CR_SUP/extensions_crx_cache"
    del "$CR_SUP/component_crx_cache"
    del "$CR_SUP/GraphiteDawnCache"
    del "$CR_SUP/GrShaderCache"
    del "$CR_SUP/ShaderCache"
    del "$CR_SUP/BrowserMetrics"
    del "$CR_SUP/Crashpad"
    for P in "$CR_SUP"/Default "$CR_SUP"/Profile\ *; do
      [ -d "$P" ] || continue
      del "$P/GPUCache"; del "$P/DawnWebGPUCache"; del "$P/Code Cache"
    done
    echo "  网页缓存 / shader / crx 缓存已清理"
  fi
else NOTES+=("未找到 Chrome 数据目录。"); fi
echo

if [ $RESTART -eq 1 ] && [ $DRY -eq 0 ] && [ ${#RELAUNCH[@]} -gt 0 ]; then
  echo "--- 重新打开 App ---"; relaunch_apps; echo
fi

MB=$((FREED/1024))
if [ $DRY -eq 1 ]; then echo "预计可释放: ${MB} MB"; else echo "实际释放: ${MB} MB"; fi
for n in "${NOTES[@]:-}"; do [ -n "$n" ] && echo "注意: $n"; done

if [ $SCHEDULED -eq 1 ]; then LAST_SUCCESS_MONTH="$MONTH"; ATTEMPTS=0; save_state; fi
echo "FREED_MB=${MB}"
