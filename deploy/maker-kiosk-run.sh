#!/usr/bin/env bash
# =============================================================================
# SCU Maker 展台 —— 全屏打开页面（由桌面自启 / systemd 调用）
#   手工执行：bash /opt/maker/maker-kiosk-run.sh
#
#  FireFox 注意事项：
#   Ubuntu 22 的 firefox 是 snap 包，启动很慢；这时“自启项 + 手动再启动”
#   会同时拉起两个实例，弹出：
#     “Firefox is already running, but is not responding…”
#   因此这里统一使用唯一 profile 并加互斥锁，第二个实例直接安静退出。
# =============================================================================
set -u

[ -r /etc/maker-kiosk.conf ] && . /etc/maker-kiosk.conf
BROWSER="${BROWSER:-}"
LOWFX="${LOWFX:-1}"
VIEW="${VIEW:-file}"
DELAY="${KIOSK_DELAY:-0}"

FILE="/srv/maker/current/index.html"
[ -f "$FILE" ] || { echo "找不到 $FILE（先运行 sudo /opt/maker/sync.sh）"; exit 1; }

if [ "$VIEW" = "http" ]; then
  URL="http://127.0.0.1/"
else
  URL="file://$FILE"
fi
[ "$LOWFX" = "1" ] && URL="$URL?lowfx=1"

# snap 版浏览器：snapd 被禁用时包装脚本虽在，执行必然失败，需要过滤掉
usable() {
  local b="$1"
  command -v "$b" >/dev/null 2>&1 || return 1
  case "$(readlink -f "$(command -v "$b")")" in
    /snap/*|*/snapd/*)
      systemctl is-active --quiet snapd 2>/dev/null || return 1
      ;;
  esac
  "$b" --version >/dev/null 2>&1 || return 1
  return 0
}

pick_browser() {
  local want="$1" b
  if [ -n "$want" ] && usable "$want"; then echo "$want"; return; fi
  for b in chromium chromium-browser firefox firefox-esr epiphany epiphany-browser; do
    if usable "$b"; then echo "$b"; return; fi
  done
  echo ""
}
BIN="$(pick_browser "$BROWSER")"
[ -n "$BIN" ] || { echo "没有可用的浏览器（chromium / chromium-browser / firefox）。snap 版不可用请改装 deb 版。"; exit 1; }

if [ "${DELAY%%.*}" -gt 0 ] 2>/dev/null; then sleep "$DELAY"; fi

# ---- 互斥锁：保证同一时刻只有一个播放器实例 -------------------------------
LOCK="/tmp/maker-kiosk.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "[$(date '+%F %T')] 播放器已在启动中，本次跳过"
  exit 0
fi

# 全局检查：任何 kiosk 浏览器在跑就不再启动
if pgrep -f -- "--kiosk" >/dev/null 2>&1; then
  echo "[$(date '+%F %T')] 已有 kiosk 浏览器在运行，跳过"
  exit 0
fi

# ---- firefox：清理残留的“僵死”实例（不会弹 already running 框） -------------
clean_stale_firefox() {
  local pids
  pids="$(pgrep -f 'firefox' 2>/dev/null || true)"
  [ -n "$pids" ] || return 0
  echo "[$(date '+%F %T')] 发现残留 firefox 进程，先结束：$pids"
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null || true
  sleep 2
  pids="$(pgrep -f 'firefox' 2>/dev/null || true)"
  if [ -n "$pids" ]; then kill -KILL $pids 2>/dev/null || true; fi
  # 清掉可能残留的 profile 锁
  rm -f "${KIOSK_PROFILE:-$HOME/.mozilla/maker-kiosk}/lock" \
        "${KIOSK_PROFILE:-$HOME/.mozilla/maker-kiosk}/.parentlock" 2>/dev/null || true
  rm -f "$HOME"/.mozilla/firefox/*.default*/lock 2>/dev/null || true
}

echo "[$(date '+%F %T')] 打开 $URL （$BIN）"

case "$BIN" in
  firefox*)
    PROFILE="${KIOSK_PROFILE:-$HOME/.mozilla/maker-kiosk}"
    mkdir -p "$PROFILE"
    if [ ! -f "$PROFILE/user.js" ]; then
      cat > "$PROFILE/user.js" <<'EOF'
// SCU Maker 展台专用配置
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("media.autoplay.default", 0);
user_pref("media.autoplay.blocking_policy", 0);
user_pref("security.fileuri.strict_origin_policy", false);
// 允许页面脚本请求全屏（kiosk 参数之外的双保险）
user_pref("full-screen-api.allow-trusted-requests-only", false);
user_pref("browser.fullscreen.autohide", true);
EOF
    fi
    clean_stale_firefox
    # MOZ_NO_REMOTE：不尝试连已有实例（避免 remote 探测导致卡住/弹窗）
    export MOZ_NO_REMOTE=1
    exec firefox --kiosk --no-remote --profile "$PROFILE" "$URL"
    ;;
  epiphany*)
    # GNOME Web：没有 --kiosk，用全屏 API（页面脚本可请求）+ 单独 profile
    exec "$BIN" --profile="${KIOSK_PROFILE:-$HOME/.config/maker-epiphany}" "$URL"
    ;;
  *)
    exec "$BIN" \
      --kiosk \
      --incognito \
      --noerrdialogs \
      --disable-infobars \
      --disable-session-crashed-bubble \
      --autoplay-policy=no-user-gesture-required \
      --disable-features=Translate,MediaRouter \
      --password-store=basic --use-mock-keychain \
      --disable-dev-shm-usage \
      --use-gl=egl \
      --user-data-dir="${KIOSK_PROFILE:-$HOME/.config/maker-kiosk-chromium}" \
      --allow-file-access-from-files \
      "$URL"
    ;;
esac
