# SCU Maker 展台 —— 树莓派 4B + Ubuntu 24.04 部署

一条命令完成安装：**装依赖 → 发布页面 → 开机自启 → 开机全屏播放 → 定时开关机**。
之后改内容只需要 `git push`，板子每 5 分钟自动更新。

- 主要目标：**Raspberry Pi 4B + Ubuntu 24.04 LTS（arm64）**
- 也兼容：Debian 12、Ubuntu 22.04、openEuler / CentOS（脚本自动识别包管理器）

```
deploy/
├── install.sh            一键安装（全部自动，无需回答问题）
├── sync.sh               拉取/发布/回滚（定时器每 5 分钟调用）
├── local-kiosk.sh        开机全屏播放器的安装/启停/状态
├── maker-kiosk-run.sh    播放器启动器（浏览器参数、profile、互斥锁）
├── autostart.sh          开机自启总览：查看/启用/关闭所有 systemd 单元
├── power-schedule.sh     22:30 关机 / 07:00 RTC 唤醒
├── nginx-maker.conf      nginx 站点片段（Ubuntu / Debian）
└── nginx-server.conf     nginx 站点片段（openEuler / RHEL）
```

---

## 一、安装：三条命令

先在能上网的电脑上确认代码已推到 GitHub，然后在树莓派上执行：

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/SCU-Maker-Org/SCU_Maker_Site_Display_Animation_101.git ~/maker-src
sudo bash ~/maker-src/deploy/install.sh
```

安装脚本**完全自动，中间不会问任何问题**，按顺序执行 9 步：

| 步骤 | 自动完成的内容 |
| --- | --- |
| 1 | `apt-get install nginx git rsync curl ca-certificates` + 自动安装浏览器 |
| 2 | 创建 `/srv/maker/{repo,releases,logs}` |
| 3 | 安装 5 个脚本到 `/opt/maker/` |
| 4 | 写入 nginx 站点配置并 `nginx -t` 校验（失败自动回滚） |
| 5 | 首次从 GitHub 拉取并发布页面 |
| 6 | 安装 `maker-sync.timer`（每 5 分钟自动更新） |
| 7 | 放行 80 端口（ufw / firewalld 自动识别） |
| 8 | 安装 `maker-poweroff.timer` + `maker-rtc-alarm.service`（22:30 关机 / 07:00 唤醒） |
| 9 | 安装开机全屏播放器（桌面自启 + 自动登录 + 立刻启动一次） |

安装完成后终端会打印：

```
================ 安装完成 ================
访问地址 : http://192.168.x.x/
查看状态 : /opt/maker/sync.sh --status
手动更新 : sudo /opt/maker/sync.sh
退回上一版: sudo /opt/maker/sync.sh --rollback
播放器   : sudo /opt/maker/local-kiosk.sh status
开机自启 : sudo /opt/maker/autostart.sh status
定时开关机: sudo /opt/maker/power-schedule.sh status
==========================================
```

### 可选开关（环境变量，不加就是默认行为）

```bash
# 不装定时开关机
sudo WITH_POWER=0 bash ~/maker-src/deploy/install.sh

# 不装开机全屏播放器
sudo WITH_KIOSK=0 bash ~/maker-src/deploy/install.sh

# 改成每 1 分钟检查更新
sudo INTERVAL=1min bash ~/maker-src/deploy/install.sh

# 私有仓库
sudo REPO_URL=https://<token>@github.com/SCU-Maker-Org/SCU_Maker_Site_Display_Animation_101.git \
     bash ~/maker-src/deploy/install.sh
```

### 重启验收

```bash
sudo reboot
```

预期：**自动登录 → 桌面出现 → 立刻全屏出现展示页**，不需要任何点击。

---

## 二、安装后会自动启动的东西

| systemd 单元 / 入口 | 作用 |
| --- | --- |
| `nginx` | 监听 80，提供 `http://<IP>/`（局域网其它设备也能看） |
| `maker-sync.timer` | 开机 1 分钟后开始，每 5 分钟从 GitHub 检查并自动发布 |
| `~/.config/autostart/maker-kiosk.desktop` | 桌面就绪后全屏打开播放器 |
| `/etc/gdm3/custom.conf` 的自动登录 | 开机免登录直接进桌面 |
| `maker-poweroff.timer` | 每天 22:30 自动关机 |
| `maker-rtc-alarm.service` | 每次开机写入 07:00 的 RTC 硬件闹钟 |

一条命令查看全部状态：

```bash
sudo /opt/maker/autostart.sh status
```

输出示例：

```
组件                         开机自启      当前状态
---------------------------- --------     --------
nginx                        enabled      active
maker-sync.timer             enabled      active
maker-kiosk.service          （未安装）    -
maker-poweroff.timer         enabled      active
maker-rtc-alarm.service      enabled      active

桌面自启     : 已安装（/home/maker/.config/autostart/maker-kiosk.desktop）
自动登录     : AutomaticLoginEnable=true
```

开机自启统一开关：

```bash
sudo /opt/maker/autostart.sh enable                # 全部启用并启动
sudo /opt/maker/autostart.sh disable               # 全部关闭自启
sudo /opt/maker/autostart.sh enable --with-kiosk   # 连播放器一起安装
sudo /opt/maker/autostart.sh enable --no-nginx     # 只本机播放，不用 nginx
```

---

## 三、日常维护命令

| 命令 | 作用 |
| --- | --- |
| `sudo /opt/maker/sync.sh` | 立即检查并更新 |
| `sudo /opt/maker/sync.sh --status` | 当前提交 / 当前版本 / 可回滚版本 |
| `sudo /opt/maker/sync.sh --rollback` | 回退到上一版 |
| `sudo /opt/maker/sync.sh --force` | 强制重新发布当前 commit |
| `tail -f /srv/maker/logs/sync.log` | 更新日志 |
| `sudo /opt/maker/local-kiosk.sh status` | 播放器状态（页面 / 自启 / 进程 / 自动登录） |
| `sudo /opt/maker/local-kiosk.sh stop` | 关掉播放器（维护时） |
| `sudo /opt/maker/local-kiosk.sh start` | 重新打开播放器 |
| `sudo /opt/maker/local-kiosk.sh install` | 重新安装开机自启（`--systemd` 改为 systemd 方式） |
| `sudo /opt/maker/power-schedule.sh status` | 定时开关机与 RTC 闹钟状态 |
| `systemctl list-timers 'maker-*'` | 所有 maker 定时器下次触发时间 |

更新内容后播放器还是旧画面时：

```bash
sudo /opt/maker/local-kiosk.sh stop && sudo /opt/maker/local-kiosk.sh start
```

也可以让它每天自动刷新：

```bash
( sudo crontab -l 2>/dev/null; echo "0 4 * * * /opt/maker/local-kiosk.sh stop; sleep 2; /opt/maker/local-kiosk.sh start" ) | sudo crontab -
```

---

## 四、更新流程是怎么工作的

```
GitHub (main)
   │  git fetch --depth 1（只拉最新一次提交）
   ▼
/srv/maker/repo                       干净的 git 工作副本
   │  rsync（排除 .git/ tools/ deploy/ preview/）
   ▼
/srv/maker/releases/20261121-1924-a1b2c3d/
   │  校验必需文件 → 原子切换软链接
   ▼
/srv/maker/current  →  上面的版本目录        ← nginx 根目录 / 播放器的页面源
```

- **无更新**：比对 commit，相同就退出，不重复拷贝视频。
- **仓库有本地改动**：跳过并提示，不覆盖板子上的手动修改。
- **发布失败**：缺 `index.html`、`assets/动画_web.mp4` 等必需文件时，丢弃这一版，旧版继续服务。
- **保留最近 5 个版本**，随时 `--rollback`。

必需文件清单（缺任何一个都不会发布）：

```
index.html  css/style.css  js/{config,intro,poster,app}.js
SCU Maker's Logo.png  校徽+院徽（高清+抠图版）.png
动画.mp4  assets/动画_web.mp4  assets/动画_web_540.mp4  assets/动画_poster.jpg
```

---

## 五、播放器配置

配置文件 `/etc/maker-kiosk.conf`：

```bash
BROWSER=firefox        # firefox / firefox-esr / chromium / epiphany（写错会自动兜底）
LOWFX=1                # 1 = 加 ?lowfx=1（板子上明显更流畅）
VIEW=file              # file = file:///srv/maker/current/index.html
                       # http = http://127.0.0.1/
KIOSK_DELAY=0          # 桌面就绪后额外等待秒数
# KIOSK_USER=pi        # 默认自动探测桌面用户
```

改完生效：

```bash
sudo /opt/maker/local-kiosk.sh stop && sudo /opt/maker/local-kiosk.sh start
```

播放器特性：

- **全屏**：Chromium 用 `--kiosk`，Firefox 用 `--kiosk`（无地址栏、无标签栏、无弹窗）
- **自动播放**：`--autoplay-policy=no-user-gesture-required`
- **独立 profile + flock 互斥**：不会出现“Firefox is already running”
- **残留实例清理**：启动前清掉僵尸进程与 `lock` 文件
- **浏览器可用性检测**：自动跳过跑不起来的 snap 包装脚本
- **日志**：`/tmp/maker-kiosk.out`

---

## 六、定时开关机

默认已随安装启用：**22:30 关机 / 07:00 开机**（环境变量 `WITH_POWER=0` 可跳过）。

```bash
sudo /opt/maker/power-schedule.sh status    # 看定时器与 RTC 闹钟
sudo /opt/maker/power-schedule.sh test      # 只写一次 RTC 闹钟，不关机
sudo /opt/maker/power-schedule.sh uninstall # 卸载

# 改时间
sudo OFF_TIME=22:00 ON_HOUR=6 ON_MIN=30 bash ~/maker-src/deploy/power-schedule.sh install
```

### 树莓派必须先开 RTC

```bash
grep -q '^dtparam=rtc=on' /boot/firmware/config.txt \
  || echo 'dtparam=rtc=on' | sudo tee -a /boot/firmware/config.txt
echo "rtc-ds1307 0x51" | sudo tee /etc/modules-load.d/rtc.conf
sudo reboot
```

重启后验证：

```bash
ls /dev/rtc*
sudo /opt/maker/power-schedule.sh test
sudo rtcwake -m off -l -t "$(date -d '+10 minutes' +%s)"   # 10 分钟后应自动开机
```

> 树莓派 4B 没有备用电池时，**断电**后时间会归零；但 `poweroff` 后主板仍待机供电，
> RTC 闹钟可以正常唤醒。要彻底断电还能定时开机，需要外接 CR2032。

---

## 七、Ubuntu 24.04 与 22.04 的差异（脚本已适配）

| 项目 | Ubuntu 22.04 | Ubuntu 24.04 | 脚本处理 |
| --- | --- | --- | --- |
| Chromium | 无 deb 包，只剩 snap 过渡包 | 同样只有 snap 过渡包 | 自动跳过不可用的 snap 版 |
| Firefox | 默认 snap 版 | 默认 snap 版，`apt install firefox` 可用 | 安装时自动装，可用性检测后再选用 |
| 自动登录配置 | `/etc/gdm3/custom.conf` | 同左 | `local-kiosk.sh install` 自动写入并备份 |
| 桌面会话 | GNOME + Wayland | GNOME + Wayland | 用桌面自启，不依赖 `graphical.target` 时机 |
| 视频硬解 | V4L2 | 同左，Chromium 走 `--use-gl=egl` | 脚本已带 `--use-gl=egl`、`--disable-dev-shm-usage` |

> 若 24.04 上 kiosk 出现黑屏／弹窗，先切到 Xorg：登录界面右下角齿轮选
> “Ubuntu on Xorg”，或在 `/etc/gdm3/custom.conf` 里写 `WaylandEnable=false`。

---

## 八、排错速查

### 8.1 网页 404

```bash
ls -l /srv/maker/current/                 # 应有 index.html css js assets
sudo /opt/maker/sync.sh --force           # 强制重新发布
sudo nginx -T | grep -E 'root |listen '   # 应含 root /srv/maker/current
curl -I http://127.0.0.1/                 # 应 200
curl -s http://127.0.0.1/ | head -3       # 应看到 <!DOCTYPE html>
```

- `200` 但浏览器 404 → 强刷 `Ctrl+Shift+R`
- `403` → `sudo chmod 755 /srv /srv/maker && sudo chmod -R a+rX /srv/maker/releases`
- 仍不行 → `sudo tail -n 30 /var/log/nginx/error.log`

### 8.2 `"worker_processes" directive is not allowed here`

用的是旧配置。修复：

```bash
cd ~/maker-src && git pull
sudo bash deploy/install.sh
```

（安装脚本会清理旧配置、写入只含 `server{}` 的片段，`nginx -t` 失败自动回滚。）

### 8.3 开机停在登录界面

```bash
grep -E '^AutomaticLogin' /etc/gdm3/custom.conf      # 应有 =true 和用户名
sudo /opt/maker/local-kiosk.sh install               # 自动写入
```

### 8.4 `Firefox is already running, but is not responding`

```bash
sudo /opt/maker/local-kiosk.sh stop
pkill -f firefox; sleep 2; pkill -9 -f firefox
rm -f ~/.mozilla/maker-kiosk/{lock,.parentlock} ~/.mozilla/firefox/*.default*/lock
sudo /opt/maker/local-kiosk.sh start
cat /tmp/maker-kiosk.out
```

### 8.5 浏览器装不上（snap 报错 / 没有候选包）

看当前有什么：

```bash
for b in firefox firefox-esr chromium chromium-browser epiphany; do
  command -v "$b" >/dev/null 2>&1 && printf '%-18s %s\n' "$b" "$("$b" --version 2>&1 | head -1)"
done
```

装 deb 版 Firefox：

```bash
sudo apt update && sudo apt install -y firefox
sudo sed -i 's/^BROWSER=.*/BROWSER=firefox/' /etc/maker-kiosk.conf
sudo /opt/maker/local-kiosk.sh stop && sudo /opt/maker/local-kiosk.sh start
```

不要把 `snap install chromium` 当作方案——snapd 异常时它会“装好但跑不起来”。

### 8.6 视频放不出来

```bash
ffmpeg -v error -i /srv/maker/current/assets/动画_web.mp4 -f null -   # 无输出 = 文件正常
```

文件正常就换浏览器试：

```bash
sudo sed -i 's/^BROWSER=.*/BROWSER=firefox/' /etc/maker-kiosk.conf
sudo /opt/maker/local-kiosk.sh stop && sudo /opt/maker/local-kiosk.sh start
```

视频为何这样压制、怎样替换新视频，见仓库根目录 `README.md` 第七节。

### 8.7 局域网其它设备打不开

```bash
ip addr show | grep 'inet '        # 树莓派常有 wlan0 + eth0，确认用哪块网卡的 IP
sudo ss -lntp | grep :80           # 应监听 0.0.0.0:80
sudo ufw status                    # 若启用：sudo ufw allow 80/tcp
```

---

## 九、安装脚本做了什么（完整清单）

`install.sh` 的非交互执行内容：

```bash
# 1) 依赖
apt-get update -qq
apt-get install -y nginx git rsync curl ca-certificates
apt-get install -y --no-install-recommends firefox \
  || apt-get install -y --no-install-recommends firefox-esr

# 2) 目录
mkdir -p /srv/maker/{repo,releases,logs}

# 3) 脚本
install -m 755 deploy/{sync,power-schedule,local-kiosk,maker-kiosk-run,autostart}.sh /opt/maker/

# 4) nginx（Ubuntu/Debian 走 sites-available；RHEL 系走 conf.d）
install -m 644 deploy/nginx-maker.conf /etc/nginx/sites-available/maker.conf
ln -sfn /etc/nginx/sites-available/maker.conf /etc/nginx/sites-enabled/maker.conf
nginx -t && systemctl restart nginx

# 5) 首次发布
/opt/maker/sync.sh

# 6) 自动更新
systemctl enable --now maker-sync.timer

# 7) 防火墙
ufw allow 80/tcp   # 或 firewall-cmd --add-service=http

# 8) 定时开关机
bash deploy/power-schedule.sh install

# 9) 开机全屏
bash /opt/maker/local-kiosk.sh install
```

想改行为就用环境变量，不用改脚本：`WITH_POWER=0`、`WITH_KIOSK=0`、`INTERVAL=1min`、`REPO_URL=...`。
