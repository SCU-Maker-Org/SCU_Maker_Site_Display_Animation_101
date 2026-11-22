#!/usr/bin/env bash
# =============================================================================
# SCU Maker 展台 —— 一键安装（树莓派 4B + Ubuntu 24.04 为主，兼容 Debian / openEuler）
# -----------------------------------------------------------------------------
#  做的事情：
#    1. 安装 nginx、git、rsync、curl
#    2. 创建用户与目录：/srv/maker
#    3. 安装部署脚本 /opt/maker/sync.sh
#    4. 安装 nginx 站点配置（/srv/maker/current 为网站根目录）
#    5. 首次拉取并发布
#    6. 安装 systemd 定时器（每 5 分钟检查一次 GitHub 更新）
#    7. 打开防火墙 80 端口（如有 firewalld / ufw）
#
#  用法：  sudo bash install.sh
# =============================================================================
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/SCU-Maker-Org/SCU_Maker_Site_Display_Animation_101.git}"
INTERVAL="${INTERVAL:-5min}"          # 自动更新间隔，可改成 1min / 10min
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_root() { [ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行：sudo bash install.sh"; exit 1; }; }
need_root

echo "==> 1/9 安装依赖（Ubuntu/Debian 走 apt，openEuler/CentOS 走 dnf/yum）"
if command -v apt-get >/dev/null 2>&1; then
  # Debian / Ubuntu（含树莓派 4B Ubuntu 24.04）
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y nginx git rsync curl ca-certificates
  systemctl enable --now nginx

  # 浏览器：Ubuntu 24.04 的 chromium 是 snap 包装脚本，snapd 异常时会“装着却跑不起来”，
  # 所以这里优先装 deb 版 Firefox（universe 源），失败也不中断安装。
  echo "     安装浏览器（firefox / firefox-esr）…"
  apt-get install -y --no-install-recommends firefox 2>/dev/null \
    || apt-get install -y --no-install-recommends firefox-esr 2>/dev/null \
    || echo "     浏览器未安装成功，可稍后手动装（见 deploy/README.md 第十九节）"
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx git rsync curl
  systemctl enable --now nginx
elif command -v yum >/dev/null 2>&1; then
  yum install -y nginx git rsync curl
  systemctl enable --now nginx
else
  echo "未识别的包管理器，请手动安装：nginx git rsync curl"; exit 1
fi

echo "==> 2/9 创建目录"
mkdir -p /srv/maker/{repo,releases,logs}
chmod 755 /srv/maker

echo "==> 3/9 安装同步脚本"
install -d -m 755 /opt/maker
install -m 755 "$SCRIPT_DIR/sync.sh" /opt/maker/sync.sh
install -m 755 "$SCRIPT_DIR/power-schedule.sh" /opt/maker/power-schedule.sh
install -m 755 "$SCRIPT_DIR/local-kiosk.sh" /opt/maker/local-kiosk.sh
install -m 755 "$SCRIPT_DIR/maker-kiosk-run.sh" /opt/maker/maker-kiosk-run.sh
install -m 755 "$SCRIPT_DIR/autostart.sh" /opt/maker/autostart.sh

echo "==> 4/9 安装 nginx 站点配置"
# 禁用发行版默认站点，避免与之冲突
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true
# 清掉可能残留的旧版（完整 http{} 配置）配置，避免重复 listen
rm -f /etc/nginx/sites-enabled/maker.conf /etc/nginx/sites-available/maker.conf /etc/nginx/conf.d/maker.conf 2>/dev/null || true

case "$( . /etc/os-release 2>/dev/null; echo "${ID:-unknown}")" in
  ubuntu|debian)
    # 只安装 server{} 片段，绝对不能把 worker_processes/events/http 放进 sites-enabled
    install -m 644 "$SCRIPT_DIR/nginx-maker.conf" /etc/nginx/sites-available/maker.conf
    ln -sfn /etc/nginx/sites-available/maker.conf /etc/nginx/sites-enabled/maker.conf
    ;;
  *)
    # openEuler / CentOS / RHEL：主配置里已有 http{}，同样只放 server{} 片段
    install -m 644 "$SCRIPT_DIR/nginx-server.conf" /etc/nginx/conf.d/maker.conf
    ;;
esac
# SELinux 放行（仅 openEuler/RHEL 需要；Ubuntu 上通常没有 getenforce，直接跳过）
if command -v getenforce >/dev/null 2>&1; then
  setsebool -P httpd_can_network_connect 1 2>/dev/null || true
  if ! command -v semanage >/dev/null 2>&1 && command -v dnf >/dev/null 2>&1; then
    dnf install -y policycoreutils-python-utils >/dev/null 2>&1 || true
  fi
  semanage fcontext -a -t httpd_sys_content_t "/srv/maker(/.*)?" 2>/dev/null || true
  restorecon -R /srv/maker 2>/dev/null || true
fi
# 目录权限（nginx 以 www-data/nginx 用户运行，需可进入并读文件）
chmod 755 /srv /srv/maker
chmod -R a+rX /srv/maker/releases 2>/dev/null || true

if ! nginx -t; then
  echo
  echo "nginx 配置检查失败，已回滚到安装前的配置，请把上面的报错发给维护者。"
  rm -f /etc/nginx/sites-enabled/maker.conf /etc/nginx/conf.d/maker.conf 2>/dev/null || true
  [ -L /etc/nginx/sites-enabled/default ] || ln -sfn /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true
  systemctl reload nginx 2>/dev/null || true
  exit 1
fi
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx

echo "==> 5/9 首次拉取并发布"
REPO_URL="$REPO_URL" /opt/maker/sync.sh || true

echo "==> 6/9 安装 systemd 定时器（每 $INTERVAL 检查一次）"
cat > /etc/systemd/system/maker-sync.service <<EOF
[Unit]
Description=SCU Maker display: pull latest site from GitHub
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=REPO_URL=$REPO_URL
ExecStart=/opt/maker/sync.sh --update
Nice=10
EOF

cat > /etc/systemd/system/maker-sync.timer <<EOF
[Unit]
Description=Periodically update SCU Maker display from GitHub

[Timer]
OnBootSec=1min
OnUnitActiveSec=$INTERVAL
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now maker-sync.timer

echo "==> 7/9 放行 80 端口"
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=http >/dev/null
  firewall-cmd --reload >/dev/null
elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q active; then
  ufw allow 80/tcp >/dev/null
fi

echo "==> 8/9 定时开关机（22:30 关机 / 07:00 RTC 唤醒）"
if [ "${WITH_POWER:-1}" = "1" ]; then
  bash "$SCRIPT_DIR/power-schedule.sh" install || echo "     定时开关机安装失败（树莓派需先开 RTC，见 README）"
else
  echo "     已跳过（WITH_POWER=0）"
fi

echo "==> 9/9 开机自动全屏播放器"
if [ "${WITH_KIOSK:-1}" = "1" ] && [ -x /opt/maker/local-kiosk.sh ]; then
  bash /opt/maker/local-kiosk.sh install \
    || echo "     播放器安装未完全成功，可稍后执行 sudo /opt/maker/local-kiosk.sh install"
else
  echo "     已跳过（WITH_KIOSK=0）；需要时执行 sudo /opt/maker/local-kiosk.sh install"
fi

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "================ 安装完成 ================"
echo "访问地址 : http://${IP:-<板子IP>}/"
echo "查看状态 : /opt/maker/sync.sh --status"
echo "手动更新 : sudo /opt/maker/sync.sh"
echo "退回上一版: sudo /opt/maker/sync.sh --rollback"
echo "播放器   : sudo /opt/maker/local-kiosk.sh status"
echo "开机自启 : sudo /opt/maker/autostart.sh status"
echo "定时开关机: sudo /opt/maker/power-schedule.sh status"
echo "=========================================="
