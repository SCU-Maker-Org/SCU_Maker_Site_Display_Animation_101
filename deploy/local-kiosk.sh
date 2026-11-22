#!/usr/bin/env bash
# =============================================================================
# SCU Maker 展台 —— 开机即打开浏览器并全屏（kiosk）
# -----------------------------------------------------------------------------
#  行为：系统启动 → 自动登录桌面 → 桌面就绪 → 立刻全屏打开页面
#        页面地址： file:///srv/maker/current/index.html?lowfx=1
#                  或 http://127.0.0.1/ （配置 VIEW=http）
#
#  两种自启方式（自动选择）：
#    1) 桌面会话方式（默认）：写入 ~/.config/autostart/maker-kiosk.desktop
#       桌面一就绪就启动，比 systemd 早好几秒，且不会有权限/DISPLAY 问题。
#    2) systemd 方式（加 --systemd）：生成 maker-kiosk.service，开机即启动。
#
#  用法：
#     sudo bash local-kiosk.sh install              # 安装（桌面自启 + 启动一次）
#     sudo bash local-kiosk.sh install --systemd    # 改用 systemd 单元
#     sudo bash local-kiosk.sh start / stop / status / uninstall
#
#  可改参数（/etc/maker-kiosk.conf）：
#     BROWSER=firefox | chromium | chromium-browser
#     LOWFX=1          # 加 ?lowfx=1（板子上更省资源）
#     VIEW=file        # file = file:///srv/maker/current/index.html ；http = http://127.0.0.1/
#     KIOSK_DELAY=0    # 额外等待秒数（一般不用改）
#     KIOSK_USER=pi    # 默认自动探测
# =============================================================================
set -euo pipefail

CONF="/etc/maker-kiosk.conf"
SERVICE="/etc/systemd/system/maker-kiosk.service"
URL_FILE="/srv/maker/current/index.html"
RUNNER="/opt/maker/maker-kiosk-run.sh"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行：sudo bash local-kiosk.sh ${1:-install}"; exit 1; }; }

# 找到桌面用户
detect_user() {
  local u="${KIOSK_USER:-}"
  if [ -z "$u" ]; then
    u="$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v '^$' | head -n1 || true)"
  fi
  if [ -z "$u" ] || [ "$u" = "root" ]; then
    u="$(getent passwd | awk -F: '$3>=1000 && $3<65000 {print $1}' | head -n1)"
  fi
  echo "${u:-root}"
}

user_home() { getent passwd "$1" | cut -d: -f6; }

write_conf() {
  if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<'EOF'
# SCU Maker 展台全屏播放配置
BROWSER=chromium       # chromium / chromium-browser / firefox
LOWFX=1                # 1 = 加 ?lowfx=1（树莓派 4B 上明显更流畅），0 = 关闭
VIEW=file              # file = 打开本地文件；http = 打开 http://127.0.0.1/
KIOSK_DELAY=0          # 桌面就绪后额外等待秒数
# KIOSK_USER=pi        # 默认自动探测桌面用户
EOF
  fi
}

# 判断某个命令是否真的可用（snap 包装脚本在 snapd 不可用时也存在，但执行会失败）
usable() {
  local b="$1"
  command -v "$b" >/dev/null 2>&1 || return 1
  # snap 版：确认 snapd 正常
  case "$(readlink -f "$(command -v "$b")")" in
    /snap/*|*/snapd/*)
      systemctl is-active --quiet snapd 2>/dev/null || return 1
      ;;
  esac
  # firefox 还需能 --version 成功返回
  "$b" --version >/dev/null 2>&1 || return 1
  return 0
}

detect_browser() {
  if [ -n "${KIOSK_BROWSER:-}" ]; then echo "$KIOSK_BROWSER"; return; fi
  for b in chromium chromium-browser firefox firefox-esr epiphany epiphany-browser; do
    if usable "$b"; then echo "$b"; return; fi
  done
  echo ""
}

# 没有可用浏览器时给出可执行的建议
browser_hint() {
  echo "  不要再装 snap 版（snapd 在这台机器上被禁用了）。可选："
  echo
  echo "  A) 用系统自带 Firefox（如果版面上已有图形版 firefox，直接设）:"
  echo "     which firefox && firefox --version"
  echo "     sudo sed -i 's/^BROWSER=.*/BROWSER=firefox/' /etc/maker-kiosk.conf"
  echo
  echo "  B) 安装 Chromium 的 deb 版（推荐，配合 maker 站点最稳）:"
  echo "     sudo apt update"
  echo "     sudo apt install -y chromium-browser || sudo apt install -y chromium"
  echo
  echo "  C) 先用 deb 版 Firefox（snap 失效时 apt 的 firefox-esr 仍可装）:"
  echo "     sudo apt install -y firefox-esr"
}

# ---------------------------------------------------------------- 桌面自启 ----
install_desktop_autostart() {
  local user home dir
  user="$(detect_user)"
  home="$(user_home "$user")"
  dir="$home/.config/autostart"
  install -d -m 755 -o "$user" -g "$(id -gn "$user")" "$dir"

  cat > "$dir/maker-kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SCU Maker Display
Comment=开机全屏播放协会展示页
Exec=/bin/bash $RUNNER
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=${KIOSK_DELAY:-0}
Terminal=false
NoDisplay=false
EOF
  chown "$user":"$(id -gn "$user")" "$dir/maker-kiosk.desktop"
  chmod 644 "$dir/maker-kiosk.desktop"
  echo "已写入桌面自启：$dir/maker-kiosk.desktop"
}

remove_desktop_autostart() {
  local user home
  user="$(detect_user)"
  home="$(user_home "$user")"
  rm -f "$home/.config/autostart/maker-kiosk.desktop"
  echo "已移除桌面自启"
}

# ------------------------------------------------------------- systemd 自启 ---
install_systemd() {
  local user home
  user="$(detect_user)"
  home="$(user_home "$user")"
  cat > "$SERVICE" <<EOF
[Unit]
Description=SCU Maker kiosk (fullscreen browser)
After=graphical.target
Wants=graphical.target

[Service]
User=$user
Environment=DISPLAY=:0
Environment=XAUTHORITY=$home/.Xauthority
Environment=HOME=$home
Environment=KIOSK_DELAY=${KIOSK_DELAY:-0}
EnvironmentFile=-$CONF
ExecStartPre=/bin/bash -c 'for i in \$(seq 1 60); do [ -f /srv/maker/current/index.html ] && break; sleep 1; done'
ExecStart=/bin/bash $RUNNER
Restart=always
RestartSec=3
RestartForceExitStatus=0

[Install]
WantedBy=graphical.target
EOF
  systemctl daemon-reload
  systemctl enable --now maker-kiosk.service
  echo "已安装 systemd 单元：maker-kiosk.service（用户：$user）"
}

remove_systemd() {
  systemctl disable --now maker-kiosk.service 2>/dev/null || true
  rm -f "$SERVICE"
  systemctl daemon-reload
  echo "已移除 systemd 单元"
}

install_all() {
  need_root install
  local mode="${1-}"
  write_conf
  # 确保启动器存在且可执行
  if [ ! -x "$RUNNER" ]; then
    echo "错误：缺少 $RUNNER（请先运行 deploy/install.sh）"; exit 1
  fi
  [ -f "$URL_FILE" ] || echo "提示：$URL_FILE 还不存在，先运行 sudo /opt/maker/sync.sh；服务会自动等待"

  local b; b="$(detect_browser)"
  if [ -z "$b" ]; then
    echo "警告：没有找到可用的浏览器。"
    browser_hint
  else
    echo "使用浏览器：$b"
  fi

  if [ "$mode" = "--systemd" ]; then
    remove_desktop_autostart >/dev/null 2>&1 || true
    install_systemd
  else
    remove_systemd >/dev/null 2>&1 || true
    install_desktop_autostart
    echo "提示：桌面自启依赖“自动登录”（/etc/gdm3/custom.conf → AutomaticLoginEnable=true）"
  fi

  echo
  echo "现在立刻启动一次："
  start_now

  # GDM 自动登录：自动帮用户打开（可选，可用 KIOSK_AUTOLOGIN=0 关闭）
  if [ "${KIOSK_AUTOLOGIN:-1}" = "1" ] && [ -f /etc/gdm3/custom.conf ]; then
    local du; du="$(detect_user)"
    if grep -q '^[#[:space:]]*AutomaticLoginEnable[[:space:]]*=[[:space:]]*true' /etc/gdm3/custom.conf; then
      echo "✓ 已开启桌面自动登录"
    else
      cp -a /etc/gdm3/custom.conf "/etc/gdm3/custom.conf.bak.$(date +%s)" 2>/dev/null || true
      # 在 [daemon] 段里插入/替换
      if grep -q '^[#[:space:]]*AutomaticLoginEnable' /etc/gdm3/custom.conf; then
        sed -i "s/^[#[:space:]]*AutomaticLoginEnable.*/AutomaticLoginEnable=true/" /etc/gdm3/custom.conf
      else
        sed -i "/^\[daemon\]/a AutomaticLoginEnable=true" /etc/gdm3/custom.conf
      fi
      if grep -q '^[#[:space:]]*AutomaticLogin=' /etc/gdm3/custom.conf; then
        sed -i "s/^[#[:space:]]*AutomaticLogin=.*/AutomaticLogin=$du/" /etc/gdm3/custom.conf
      else
        sed -i "/^AutomaticLoginEnable=true/a AutomaticLogin=$du" /etc/gdm3/custom.conf
      fi
      echo "✓ 已开启桌面自动登录（用户 $du），下次开机会直接进入桌面并全屏播放"
      grep -E '^AutomaticLogin' /etc/gdm3/custom.conf || true
    fi
  fi
}

# 立刻启动（直接后台拉起浏览器，无需等服务）
start_now() {
  local user home
  user="$(detect_user)"
  home="$(user_home "$user")"
  if pgrep -u "$user" -f 'maker-kiosk-run|--kiosk' >/dev/null 2>&1; then
    echo "浏览器已经在运行"
    return
  fi
  echo "启动浏览器（用户 $user）…"
  if [ "$user" = "$(id -un 2>/dev/null || echo root)" ]; then
    setsid /bin/bash "$RUNNER" >/tmp/maker-kiosk.out 2>&1 &
  else
    runuser -u "$user" -- setsid /bin/bash "$RUNNER" >/tmp/maker-kiosk.out 2>&1 &
  fi
  sleep 2
}

stop_now() {
  pkill -f 'maker-kiosk-run' 2>/dev/null || true
  pkill -f -- '--kiosk' 2>/dev/null || true
  systemctl stop maker-kiosk.service 2>/dev/null || true
  echo "已停止浏览器"
}

status_now() {
  local user home
  user="$(detect_user)"; home="$(user_home "$user")"
  echo "== 页面 =="
  if [ -f "$URL_FILE" ]; then echo "  $URL_FILE 存在"; else echo "  $URL_FILE 不存在（先运行 sudo /opt/maker/sync.sh）"; fi
  echo "== 自启方式 =="
  if [ -f "$home/.config/autostart/maker-kiosk.desktop" ]; then
    echo "  桌面自启：$home/.config/autostart/maker-kiosk.desktop"
  else
    echo "  桌面自启：未安装"
  fi
  if systemctl list-unit-files maker-kiosk.service --no-legend 2>/dev/null | grep -q .; then
    echo "  systemd ：$(systemctl is-enabled maker-kiosk.service 2>/dev/null) / $(systemctl is-active maker-kiosk.service 2>/dev/null)"
  else
    echo "  systemd ：未安装"
  fi
  echo "== 浏览器进程 =="
  pgrep -a -u "$user" -f 'maker-kiosk-run|--kiosk|firefox|chromium' 2>/dev/null | head -n 5 || echo "  没有运行"
  echo "== 自动登录 =="
  grep -E '^AutomaticLogin' /etc/gdm3/custom.conf 2>/dev/null || echo "  未配置（建议开启）"
  echo "== 配置 =="
  cat "$CONF" 2>/dev/null | grep -v '^#' | grep -v '^$'
}

uninstall_all() {
  need_root uninstall
  stop_now
  remove_desktop_autostart
  remove_systemd
  echo "已卸载（页面文件与 /srv/maker 保留）"
}

case "${1:-install}" in
  install)   need_root install; install_all "${2-}" ;;
  uninstall) uninstall_all ;;
  start)     need_root start; start_now ;;
  stop)      need_root stop; stop_now ;;
  status)    status_now ;;
  *) echo "用法：$0 [install [--systemd]|uninstall|start|stop|status]"; exit 2 ;;
esac
