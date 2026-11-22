#!/usr/bin/env bash
# =============================================================================
# SCU Maker 展台 —— 统一开机自启管理（推荐用法）
# -----------------------------------------------------------------------------
#  一次性保证「所有该自动跑的东西」都随开机启动，并且当前已跑起来：
#    - maker-sync.timer         每 5 分钟从 GitHub 拉取更新
#    - nginx                    HTTP 服务（若你用 http:// 方案）
#    - maker-kiosk.service      开机全屏打开页面（可选）
#    - maker-poweroff.timer     22:30 自动关机（可选）
#    - maker-rtc-alarm.service  每次开机写 RTC 07:00 唤醒闹钟（可选）
#
#  用法：
#     sudo bash deploy/autostart.sh status     # 看每个组件是否 enabled / 运行中
#     sudo bash deploy/autostart.sh enable     # 全部启用并立即启动
#     sudo bash deploy/autostart.sh disable    # 全部关闭开机自启
#     sudo bash deploy/autostart.sh enable --with-kiosk       # 同时装全屏 kiosk
#     sudo bash deploy/autostart.sh enable --no-nginx         # 只用 file:// 本机播放时
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-status}"
WITH_KIOSK=0
NO_NGINX=0
for a in "$@"; do
  case "$a" in
    --with-kiosk) WITH_KIOSK=1 ;;
    --no-nginx)   NO_NGINX=1 ;;
  esac
done

UNITS=(
  "nginx"
  "maker-sync.timer"
  "maker-kiosk.service"
  "maker-poweroff.timer"
  "maker-rtc-alarm.service"
)

need_root() { [ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行：sudo bash deploy/autostart.sh $ACTION"; exit 1; }; }

show() {
  local u state active
  printf '%-28s %-12s %s\n' "组件" "开机自启" "当前状态"
  printf '%-28s %-12s %s\n' "----------------------------" "--------" "--------"
  for u in "${UNITS[@]}"; do
    if systemctl list-unit-files "$u" --no-legend 2>/dev/null | grep -q .; then
      state="$(systemctl is-enabled "$u" 2>/dev/null || echo '未启用')"
      active="$(systemctl is-active "$u" 2>/dev/null || echo 'inactive')"
      printf '%-28s %-12s %s\n' "$u" "$state" "$active"
    else
      printf '%-28s %-12s %s\n' "$u" "（未安装）" "-"
    fi
  done
}

desktop_autostart_user() {
  loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^$' | head -n1
}

show_desktop() {
  local u home
  u="$(desktop_autostart_user)"; [ -n "$u" ] || u="$(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1}' | head -n1)"
  home="$(getent passwd "$u" | cut -d: -f6)"
  if [ -f "$home/.config/autostart/maker-kiosk.desktop" ]; then
    echo "桌面自启     : 已安装（$home/.config/autostart/maker-kiosk.desktop）"
  else
    echo "桌面自启     : 未安装（sudo /opt/maker/local-kiosk.sh install）"
  fi
  grep -E '^AutomaticLogin' /etc/gdm3/custom.conf 2>/dev/null || echo "自动登录     : 未开启"
}

status() {
  show
  echo
  show_desktop
  echo
  echo "提示："
  echo "  - nginx 提供 http://<IP>/ 访问（局域网其它设备可用）"
  echo "  - maker-kiosk 开机全屏打开页面（本机显示器）"
  echo "  - 两者可同时存在：kiosk 打开本机文件，nginx 给其它设备用"
}

enable_all() {
  echo "==> 1/4 自动更新定时器"
  systemctl enable --now maker-sync.timer

  echo "==> 2/4 nginx"
  if [ "$NO_NGINX" = "1" ]; then
    echo "    按要求跳过 nginx（--no-nginx）"
  elif [ -f /etc/nginx/sites-enabled/maker.conf ] || [ -f /etc/nginx/conf.d/maker.conf ]; then
    systemctl enable --now nginx
  else
    echo "    未找到 maker 站点配置，跳过。请先运行 deploy/install.sh"
  fi

  echo "==> 3/4 开机全屏播放器"
  if [ "$WITH_KIOSK" = "1" ]; then
    # 带 --with-kiosk：安装并启用（桌面自启 + 自动登录 + 立刻启动）
    if [ -x /opt/maker/local-kiosk.sh ]; then
      bash /opt/maker/local-kiosk.sh install
    else
      bash "$SCRIPT_DIR/local-kiosk.sh" install
    fi
  else
    local u home
    u="$(desktop_autostart_user)"
    home="$(getent passwd "$u" | cut -d: -f6 2>/dev/null)"
    if [ -f "$home/.config/autostart/maker-kiosk.desktop" ]; then
      echo "    桌面自启已存在"
    elif systemctl list-unit-files maker-kiosk.service --no-legend 2>/dev/null | grep -q .; then
      systemctl enable --now maker-kiosk.service
    else
      echo "    未安装（加 --with-kiosk 一键安装开机全屏播放器）"
    fi
  fi

  echo "==> 4/4 定时开关机"
  if systemctl list-unit-files maker-poweroff.timer --no-legend 2>/dev/null | grep -q .; then
    systemctl enable --now maker-poweroff.timer
    systemctl enable maker-rtc-alarm.service
  else
    echo "    未安装（需要时运行 deploy/power-schedule.sh install）"
  fi

  echo
  show
}

disable_all() {
  for u in "${UNITS[@]}"; do
    if systemctl list-unit-files "$u" --no-legend 2>/dev/null | grep -q .; then
      systemctl disable "$u" 2>/dev/null || true
      echo "已关闭开机自启：$u（当前仍在运行，如需停止用 systemctl stop $u）"
    fi
  done
}

case "$ACTION" in
  status)  status ;;
  enable)  need_root; enable_all ;;
  disable) need_root; disable_all ;;
  *) echo "用法：$0 [status|enable|disable] [--with-kiosk] [--no-nginx]"; exit 2 ;;
esac
