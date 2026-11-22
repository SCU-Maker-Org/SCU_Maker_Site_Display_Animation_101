#!/usr/bin/env bash
# =============================================================================
# SCU Maker 展台 —— 从 GitHub 定时拉取并发布
# -----------------------------------------------------------------------------
#  用途：在树莓派 4B（Ubuntu 24.04）等板子上由 systemd timer 定期调用
#  行为：拉取最新代码 → 同步到 /srv/maker/releases/<时间戳> → 原子切换 current
#        → 校验 index.html，失败自动回滚到上一版 → 清理旧版本
#
#  用法：
#     ./sync.sh                 # 正常更新
#     ./sync.sh --force         # 强制重新发布当前版本（修了发布脚本后用）
#     ./sync.sh --rollback      # 立即回滚到上一版
#     ./sync.sh --status        # 查看当前状态
#     BRANCH=dev ./sync.sh      # 临时拉取其它分支
#
#  退出码：0 成功（含“无更新”） / 1 失败（已自动回滚）
#  日志：/srv/maker/logs/sync.log
# =============================================================================
set -euo pipefail

# ------------------------------------------------------------------ 可改配置 --
REPO_URL="${REPO_URL:-https://github.com/SCU-Maker-Org/SCU_Maker_Site_Display_Animation_101.git}"
BRANCH="${BRANCH:-main}"

BASE_DIR="${BASE_DIR:-/srv/maker}"      # 总目录
REPO_DIR="$BASE_DIR/repo"               # 本地 git 克隆
REL_DIR="$BASE_DIR/releases"            # 每个版本一份
CUR_LINK="$BASE_DIR/current"            # 指向当前版本的软链接
LOG_DIR="$BASE_DIR/logs"
LOG_FILE="$LOG_DIR/sync.log"
LOCK_FILE="/tmp/maker-sync.lock"

KEEP_RELEASES="${KEEP_RELEASES:-5}"     # 保留最近几个版本（回滚用）

# 站点需要的文件（缺任何一个视为部署失败）
# 注意：左上角校徽/院徽、Logo 都是根目录的中文/带空格文件名，必须一起发布，
#      否则页面能打开但顶栏两张图会 404。
REQUIRED_FILES=(
  "index.html"
  "css/style.css"
  "js/config.js"
  "js/intro.js"
  "js/poster.js"
  "js/app.js"
  "SCU Maker's Logo.png"
  "校徽+院徽（高清+抠图版）.png"
  "动画.mp4"
  "assets/动画_web.mp4"
  "assets/动画_web_540.mp4"
  "assets/动画_poster.jpg"
)

# ---------------------------------------------------------------------- 工具 --
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE" >&2; }
die() { log "ERROR: $*"; exit 1; }

mkdir -p "$BASE_DIR" "$REL_DIR" "$LOG_DIR"

# 不允许两个同步同时跑
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "上一个同步任务还在运行，本次跳过"
  exit 0
fi

# ------------------------------------------------------------------ 准备仓库 --
prepare_repo() {
  if [ ! -d "$REPO_DIR/.git" ]; then
    log "首次克隆 $REPO_URL"
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$REPO_DIR" 1>&2
  fi

  cd "$REPO_DIR"

  # 本地有未提交改动（比如有人在香橙派上直接改 config.js）：不要覆盖，提示人工处理
  if [ -n "$(git status --porcelain)" ]; then
    log "本地仓库有未提交改动，跳过本次更新。请先处理：cd $REPO_DIR && git status"
    exit 0
  fi

  local before after
  before="$(git rev-parse HEAD)"
  git fetch --depth 1 origin "$BRANCH" 1>&2
  git reset --hard "origin/$BRANCH" 1>&2
  after="$(git rev-parse HEAD)"

  if [ "$before" = "$after" ]; then
    log "已是最新版本 ${after:0:7}，无需更新"
    exit 0
  fi
  log "发现新版本：${before:0:7} -> ${after:0:7}"
  echo "$after"
}

# -------------------------------------------------------------------- 发布 ----
publish() {
  local sha="$1"
  local stamp ts rel
  stamp="$(date '+%Y%m%d-%H%M%S')"
  ts="$stamp-${sha:0:7}"
  rel="$REL_DIR/$ts"

  mkdir -p "$rel"
  # 排除 .git / 开发用素材：只发布网站真正需要的文件
  # 注意：assets/ 里有两个 Web 视频（720p 主用 + 540p 兜底）与封面图，必须同步
  rsync -a --delete \
    --exclude '.git/' \
    --exclude 'tools/' \
    --exclude 'deploy/' \
    --exclude 'preview/' \
    --exclude 'assets/cat-*' \
    --exclude '*.py' \
    --exclude '*.deb' \
    "$REPO_DIR/" "$rel/"

  # 校验必需文件
  local f missing=0
  for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -s "$rel/$f" ]; then
      log "缺少必需文件：$f（版本 ${sha:0:7}）"
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    rm -rf "$rel"
    die "本次发布已中止，旧版本保持不变。请检查仓库是否完整（git ls-tree --name-only HEAD）"
  fi

  # 原子切换 current（先 chmod，再切链接，避免 nginx 短暂读不到）
  chmod 755 /srv 2>/dev/null || true
  chmod -R a+rX "$rel"
  # SELinux 只在启用时处理（Ubuntu 默认没有，自动跳过）
  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" != "Disabled" ]; then
    restorecon -R "$rel" 2>/dev/null || true
  fi
  ln -sfn "$rel" "$CUR_LINK"
  echo "$ts" > "$BASE_DIR/CURRENT_VERSION"
  log "已发布 $ts（$(du -sh "$rel" | cut -f1)）"

  # 清理旧版本，保留最近 N 个
  local current old
  current="$(readlink -f "$CUR_LINK")"
  ls -1dt "$REL_DIR"/*/ 2>/dev/null | tail -n +$((KEEP_RELEASES + 1)) | while read -r old; do
    old="$(readlink -f "$old")"
    [ "$old" = "$current" ] && continue
    log "清理旧版本 $(basename "$old")"
    rm -rf "$old"
  done
}

# -------------------------------------------------------------------- 回滚 ----
rollback() {
  local current prev
  current="$(readlink -f "$CUR_LINK" || true)"
  prev="$(ls -1dt "$REL_DIR"/*/ 2>/dev/null | while read -r d; do
            [ "$(readlink -f "$d")" = "$current" ] && continue
            echo "$d"; break
          done)"
  [ -n "${prev:-}" ] || die "没有可回滚的旧版本"
  ln -sfn "$(readlink -f "$prev")" "$CUR_LINK"
  echo "$(basename "$prev")" > "$BASE_DIR/CURRENT_VERSION"
  log "已回滚到 $(basename "$prev")"
}

# -------------------------------------------------------------------- 状态 ----
status() {
  echo "仓库      : $REPO_DIR"
  [ -d "$REPO_DIR/.git" ] && echo "当前提交  : $(git -C "$REPO_DIR" rev-parse --short HEAD) ($(git -C "$REPO_DIR" log -1 --format='%cd' --date=format:'%F %T'))"
  echo "发布目录  : $(readlink -f "$CUR_LINK" 2>/dev/null || echo '（尚未发布）')"
  echo "可用版本  :"
  local any=""
  while read -r d; do
    [ -n "$d" ] || continue
    echo "  - $(basename "$d")"
    any="1"
  done < <(ls -1dt "$REL_DIR"/*/ 2>/dev/null | head -n "$KEEP_RELEASES")
  [ -n "$any" ] || echo "  （无）"
}

# --------------------------------------------------------------------- 主逻辑 --
case "${1:---update}" in
  --rollback) rollback ;;
  --status)   status ;;
  --force)
    # 强制用当前 HEAD 重新发布（例如修了发布脚本、或上次发布不完整）
    if [ -d "$REPO_DIR/.git" ]; then
      sha="$(git -C "$REPO_DIR" rev-parse HEAD)"
      log "强制重新发布 ${sha:0:7}"
      publish "$sha"
    else
      die "仓库尚未克隆，先运行 /opt/maker/sync.sh 一次"
    fi
    ;;
  --update|"")
    sha="$(prepare_repo | tail -n 1)"
    if [ -n "${sha:-}" ] && [ ${#sha} -eq 40 ]; then
      publish "$sha"
    fi
    ;;
  *) echo "用法：$0 [--update|--force|--rollback|--status]"; exit 2 ;;
esac

exit 0
