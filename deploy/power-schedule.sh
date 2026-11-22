#!/usr/bin/env bash
# =============================================================================
# SCU Maker 展台 —— 定时开关机
# -----------------------------------------------------------------------------
#  22:30 自动关机 ； 07:00 自动开机
#
#  关机：systemd timer（不要用 crontab 关机，22:30 之后 cron 任务会丢失）
#  开机：写 RTC 硬件闹钟（香橙派 Kunpeng Pro / RK3588 用 rtc-hym8563），
#        关机后主板仍供电，到达时间自动唤醒 —— 需要在 BIOS/固件或
#        /etc/rc.local 里让 RTC 闹钟保持有效，详见 README。
#
#  用法：
#     sudo bash power-schedule.sh install     # 安装（默认 22:30 关机 / 07:00 开机）
#     sudo bash power-schedule.sh uninstall   # 卸载
#     sudo bash power-schedule.sh status      # 查看 RTC 闹钟与定时器
#     sudo bash power-schedule.sh test        # 立即测试写 RTC 闹钟（不关机）
#
#  自定义时间：
#     OFF_TIME=22:00 ON_HOUR=6 ON_MIN=30 sudo bash power-schedule.sh install
# =============================================================================
set -euo pipefail

OFF_TIME="${OFF_TIME:-22:30}"       # 每天关机时间 HH:MM
ON_HOUR="${ON_HOUR:-7}"             # 每天开机小时（0-23）
ON_MIN="${ON_MIN:-0}"               # 每天开机分钟（0-59）

OFF_H="${OFF_TIME%:*}"
OFF_M="${OFF_TIME#*:}"
OFF_H=$((10#$OFF_H))          # 去掉前导 0
OFF_M=$((10#$OFF_M))
ON_HOUR=$((10#$ON_HOUR))
ON_MIN=$((10#$ON_MIN))

RTC_CONF="/etc/maker-rtc-alarm.conf"
RTC_UNIT="/etc/systemd/system/maker-rtc-alarm.service"
OFF_UNIT="/etc/systemd/system/maker-poweroff.service"
OFF_TIMER="/etc/systemd/system/maker-poweroff.timer"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行"; exit 1; }; }

# ---------------------------------------------------------------- 安装单位 ---
install_units() {
  local hh mm
  hh=$(printf '%02d' "$OFF_H"); mm=$(printf '%02d' "$OFF_M")
  local onh onm
  onh=$(printf '%02d' "$ON_HOUR"); onm=$(printf '%02d' "$ON_MIN")

  # 1) 22:30 关机
  cat > "$OFF_UNIT" <<EOF
[Unit]
Description=SCU Maker kiosk: scheduled shutdown at $hh:$mm

[Service]
Type=oneshot
# 顺序：关浏览器 -> 写 RTC 唤醒闹钟 -> 关机
ExecStart=-/bin/sh -c 'pkill -f "chromium.*--kiosk" || true'
ExecStart=-/usr/local/sbin/maker-rtc-alarm.sh
# 用 systemctl 关机：开机后无论当前是几点，都会立刻重新压入“下一个 07:00”的闹钟
ExecStart=/usr/bin/systemctl poweroff --message="SCU Maker kiosk: daily power-off"
TimeoutStartSec=0
EOF

  cat > "$OFF_TIMER" <<EOF
[Unit]
Description=Daily shutdown of SCU Maker kiosk ($hh:$mm)

[Timer]
OnCalendar=*-*-* $hh:$mm:00
AccuracySec=30s
Persistent=false

[Install]
WantedBy=timers.target
EOF

  # 2) 每次开机时写 RTC 闹钟（保证下次能自动唤醒）
  cat > "$RTC_CONF" <<EOF
# SCU Maker 展台 RTC 唤醒闹钟配置（由 power-schedule.sh 生成）
ON_HOUR=$onh
ON_MIN=$onm
EOF

  cat > "$RTC_UNIT" <<'EOF'
[Unit]
Description=SCU Maker kiosk: set RTC wake alarm
# 开机完成、以及关机前都会执行一次
WantedBy=multi-user.target
After=local-fs.target time-sync.target
Before=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/usr/bin/env bash /usr/local/sbin/maker-rtc-alarm.sh
EOF

  # 3) 真正写硬件闹钟的小脚本
  cat > /usr/local/sbin/maker-rtc-alarm.sh <<'EOF'
#!/usr/bin/env bash
# 写 RTC 硬件唤醒闹钟：每天 ON_HOUR:ON_MIN 唤醒
set -u
[ -r /etc/maker-rtc-alarm.conf ] && . /etc/maker-rtc-alarm.conf
ON_HOUR="${ON_HOUR:-7}"
ON_MIN="${ON_MIN:-0}"
H=$((10#$ON_HOUR)); M=$((10#$ON_MIN))

if [ -w /sys/class/rtc/rtc0/wakealarm ]; then
  # 绝对时间方式（最通用）：今天若已过则取明天
  target="$(date -d "today $(printf '%02d:%02d' $H $M)" +%s 2>/dev/null || echo 0)"
  now="$(date +%s)"
  if [ "$target" -le "$now" ]; then
    target="$(date -d "tomorrow $(printf '%02d:%02d' $H $M)" +%s)"
  fi
  echo 0 > /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
  echo "$target" > /sys/class/rtc/rtc0/wakealarm 2>/dev/null \
    && echo "RTC wakealarm set: $(date -d @"$target") ($(cat /sys/class/rtc/rtc0/wakealarm))" \
    || { echo "RTC wakealarm 写入失败（驱动可能未使能），请按 README 用 rtcwake 方案"; exit 0; }
  exit 0
fi

# 没有 sysfs 接口时退化为 rtcwake（需要 rtcwake 命令）
if command -v rtcwake >/dev/null 2>&1; then
  rtcwake -m no -l -t "$(date -d "tomorrow $(printf '%02d:%02d' $H $M)" +%s)" >/dev/null 2>&1 \
    && echo "rtcwake alarm set" || echo "rtcwake 设置失败"
else
  echo "未找到 /sys/class/rtc/rtc0/wakealarm 也没有 rtcwake，跳过"
fi
EOF
  chmod 755 /usr/local/sbin/maker-rtc-alarm.sh

  systemctl daemon-reload
  systemctl enable --now maker-poweroff.timer
  systemctl enable maker-rtc-alarm.service

  # 现在就写一次，保证今晚关机后明天能唤醒
  /usr/local/sbin/maker-rtc-alarm.sh || true

  echo "已安装：每天 ${hh}:${mm} 关机，${onh}:${onm} RTC 唤醒"
  echo "验证 RTC：sudo rtcwake -m off -l -t \"\$(date -d '+10 minutes' +%s)\"   # 10 分钟后应自动开机"
}

uninstall_units() {
  systemctl disable --now maker-poweroff.timer 2>/dev/null || true
  systemctl disable maker-rtc-alarm.service 2>/dev/null || true
  rm -f "$OFF_UNIT" "$OFF_TIMER" "$RTC_UNIT" "$RTC_CONF" /usr/local/sbin/maker-rtc-alarm.sh
  systemctl daemon-reload
  echo "已卸载定时开关机"
}

status_units() {
  echo "== 关机定时器 =="
  systemctl list-timers maker-poweroff.timer --no-pager 2>/dev/null || true
  echo
  echo "== RTC 唤醒闹钟 =="
  if [ -r /sys/class/rtc/rtc0/wakealarm ]; then
    local w
    w="$(cat /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true)"
    if [ -n "$w" ]; then echo "wakealarm = $w  ($(date -d @"$w" 2>/dev/null || echo '无法解析'))"; else echo "wakealarm 为空（未设置）"; fi
  else
    echo "/sys/class/rtc/rtc0/wakealarm 不存在，尝试 rtcwake -m show："
    rtcwake -m show 2>/dev/null || echo "不支持"
  fi
  echo
  echo "== 当前时间 =="
  date
  hwclock -r 2>/dev/null || true
  echo
  echo "== 板子信息 =="
  ( . /etc/os-release 2>/dev/null; echo "系统: ${PRETTY_NAME:-未知} $(uname -m)" )
  grep -m1 "Model" /proc/cpuinfo 2>/dev/null || true
}

case "${1:-install}" in
  install)   need_root; install_units ;;
  uninstall) need_root; uninstall_units ;;
  status)    status_units ;;
  test)      need_root; /usr/local/sbin/maker-rtc-alarm.sh ;;
  *) echo "用法：$0 [install|uninstall|status|test]"; exit 2 ;;
esac
