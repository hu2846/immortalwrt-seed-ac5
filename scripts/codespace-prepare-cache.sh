#!/usr/bin/env bash
# ============================================================================
# SEED AC5 固件构建缓存预热脚本（在 GitHub Codespace 中运行）
#
# 作用: 在 Codespace 里完成一次 OpenWrt/ImmortalWrt 编译(4核32GB 也能跑, 见下方说明),
#       然后把 ccache / dl / staging_dir 打包装成 Release 资产传回仓库;
#       Actions 工作流会自动下载该资产作为"热缓存", 把冷构建变热构建。
#
# 用法:
#   bash scripts/codespace-prepare-cache.sh
#
# 常用环境变量:
#   WORK=/tmp/build        源码/编译工作目录(默认 /workspaces/build)。
#                          ★ Codespace 里 /workspaces 通常只有 32GB, 而 /tmp 往往挂在大盘上
#                            (本机实测 118GB), 全量编译峰值 60GB+, 建议 WORK=/tmp/build
#   TARBALL=...            打包产物路径(默认与 WORK 同分区)
#   GOAL=toolchain|full    toolchain=只编工具链(约40~60min, 适合 32GB 小盘先跑一轮); full=全量(默认)
#   TRIGGER_BUILD=1        打包上传完成后自动触发 Actions 热构建
#   SKIP_BUILD=1           不编译, 只打包现有缓存
#   JOBS=4                 并行度(默认 nproc)
#   DISK_FLOOR_GB=3        磁盘看门狗阈值: 可用空间低于该值自动停下编译, 保证还能打包上传
#   KEEP_BUILD_DIR=1       打包时保留 build_dir(默认删除以腾出空间)
#   CACHE_RELEASE=prebuilt-cache   缓存所在 Release tag
#
# 32GB 磁盘建议(两轮累积):
#   第一轮: GOAL=toolchain bash scripts/codespace-prepare-cache.sh
#   第二轮: GOAL=full TRIGGER_BUILD=1 bash scripts/codespace-prepare-cache.sh
# ============================================================================
set -uo pipefail

REPO_SLUG="${REPO_SLUG:-hu2846/immortalwrt-seed-ac5}"
SRC_REPO="${SRC_REPO:-https://github.com/BeeconMini/immortalwrt.git}"
SRC_BRANCH="${SRC_BRANCH:-25.12.0-rc2}"
CACHE_RELEASE="${CACHE_RELEASE:-prebuilt-cache}"
WORK="${WORK:-/workspaces/build}"
JOBS="${JOBS:-$(nproc)}"
GOAL="${GOAL:-full}"
SKIP_BUILD="${SKIP_BUILD:-0}"
DISK_FLOOR_GB="${DISK_FLOOR_GB:-3}"
KEEP_BUILD_DIR="${KEEP_BUILD_DIR:-0}"
TARBALL="${TARBALL:-$(dirname "$WORK")/prebuilt-cache.tar.zst}"
PART_SIZE="${PART_SIZE:-1900M}"

log() { echo -e "\n\033[1;36m==> $*\033[0m"; }
# 可用磁盘(GB): 跟随 WORK 所在分区(不存在时向上找已存在的父目录)
avail_gb() {
  local p="${1:-$WORK}"
  while [ ! -d "$p" ] && [ "$p" != "/" ]; do p="$(dirname "$p")"; done
  df -BG --output=avail "$p" 2>/dev/null | tail -1 | tr -dc '0-9'
}

log "环境检查"
echo "nproc=$(nproc) arch=$(uname -m) 目标=$GOAL"; free -h | head -2
echo "工作目录: $WORK (所在分区可用 $(avail_gb)GB)"
df -h /workspaces /tmp 2>/dev/null | grep -vE '^Filesystem' | head -4
echo "看门狗阈值 ${DISK_FLOOR_GB}GB"

log "安装编译依赖"
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential ccache clang cmake curl ecj fastjar file g++ gawk gettext git \
  libelf-dev libncurses-dev libssl-dev python3 python3-docutils python3-setuptools rsync swig time \
  unzip wget zlib1g-dev qemu-utils zstd procps >/dev/null

log "准备源码目录 $WORK"
mkdir -p "$WORK"; cd "$WORK"
[ -d source/.git ] || git clone -b "$SRC_BRANCH" --single-branch "$SRC_REPO" source
cd source

log "应用本仓库的 feeds / .config / files / 补丁脚本"
CONFIG_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp -f "$CONFIG_REPO_DIR/feeds.conf.default" feeds.conf.default
cp -f "$CONFIG_REPO_DIR/.config" .config
[ -d "$CONFIG_REPO_DIR/files" ] && cp -r "$CONFIG_REPO_DIR/files" ./
mkdir -p .ccache
export CCACHE_DIR="$WORK/source/.ccache" CCACHE_MAXSIZE=8G CCACHE_COMPRESS=true

# 复用已有的 feeds/dl/staging 时, 先更新 feeds 再收敛
./scripts/feeds update -a
./scripts/feeds install -a
python3 "$CONFIG_REPO_DIR/scripts/fix-libffi-makefile.py" feeds/packages/libs/libffi/Makefile || true
grep -qE '^CONFIG_CCACHE=y' .config || echo 'CONFIG_CCACHE=y' >> .config

log "配置收敛(与 Actions 工作流一致)"
PREV=-1
for i in 1 2 3 4 5 6 7 8; do
  grep -hE '^CONFIG_PACKAGE_[^ =]+=y' "$CONFIG_REPO_DIR/.config" | while IFS= read -r line; do
    sym="${line%%=*}"
    grep -qE "^${sym}=y$|^${sym}=m$" .config || echo "$line" >> .config
  done
  make defconfig >/dev/null 2>&1
  N=$(grep -cE '^CONFIG_PACKAGE_[a-z0-9._-]+=y' .config || true)
  echo "第 $i 轮后 PACKAGE=y: $N"
  [ "$N" = "$PREV" ] && { echo "配置已收敛"; break; }
  PREV=$N
done
grep -qE '^CONFIG_CCACHE=y' .config || echo 'CONFIG_CCACHE=y' >> .config

# ------------------------- 编译(带磁盘看门狗) -------------------------
run_build() {
  local target="$1" desc="$2"
  log "$desc (可用磁盘 $(avail_gb)GB)"
  make -j"$JOBS" V=s $target &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 20
    if [ "$(avail_gb)" -lt "$DISK_FLOOR_GB" ]; then
      echo -e "\n\033[1;33m⚠️ 可用磁盘 < ${DISK_FLOOR_GB}GB, 停止编译以保留打包空间\033[0m"
      pkill -TERM -P "$pid" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true
      pkill -f '^make ' 2>/dev/null || true
      sleep 5
      break
    fi
  done
  wait "$pid" 2>/dev/null
  echo "目标 [$target] 结束, 剩余磁盘 $(avail_gb)GB"
}

if [ "$SKIP_BUILD" != "1" ]; then
  # download 先行(有磁盘阈值保护)
  for i in 1 2 3; do
    make -j$((JOBS+1)) download V=s && break || { echo "download 重试 $i/3"; sleep 20; }
  done

  if [ "$GOAL" = "toolchain" ]; then
    run_build "tools/install" "编译 host 工具(tools/install)"
    run_build "toolchain/install" "编译交叉工具链(toolchain/install)"
  else
    run_build "" "完整编译 make -j$JOBS V=s"
  fi
  ccache -s || true
fi

# ------------------------- 打包上传 -------------------------
log "准备打包(默认删除 build_dir 腾空间)"
cd "$WORK/source"
PACK_LIST=(.ccache dl staging_dir)
if [ "$KEEP_BUILD_DIR" = "1" ] && [ -d build_dir ]; then
  PACK_LIST+=(build_dir)
else
  # 只保留体积小、对增量有用的 host 构建目录(若不太大)
  for d in build_dir/host build_dir/hostpkg; do
    if [ -d "$d" ] && [ "$(du -sBG "$d" | tr -dc '0-9')" -lt 4 ]; then PACK_LIST+=("$d"); fi
  done
  rm -rf build_dir
fi
echo "打包内容: ${PACK_LIST[*]}"; du -sh "${PACK_LIST[@]}" 2>/dev/null || true

rm -f "$TARBALL"
tar -I 'zstd -T0 -3' -cf "$TARBALL" "${PACK_LIST[@]}"
ls -lh "$TARBALL"

log "分片并上传到 Release: $CACHE_RELEASE"
rm -f "${TARBALL}".part-*
split -b "$PART_SIZE" -d -a 3 "$TARBALL" "${TARBALL}.part-"
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "${GH_TOKEN:-}" ]; then echo "❌ 未找到 GH_TOKEN/GITHUB_TOKEN"; exit 1; fi
if ! gh release view "$CACHE_RELEASE" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  gh release create "$CACHE_RELEASE" --repo "$REPO_SLUG" \
    --title "Prebuilt build cache" --notes "Codespace 预热的 ccache/dl/staging 缓存, 供 Actions 工作流恢复使用。" || true
fi
gh release upload "$CACHE_RELEASE" "${TARBALL}".part-* --repo "$REPO_SLUG" --clobber
echo "✅ 缓存已上传。可删除本地大文件: rm -f $TARBALL ${TARBALL}.part-*"

if [ "${TRIGGER_BUILD:-0}" = "1" ]; then
  log "触发 Actions 热构建"
  gh workflow run "Build ImmortalWRT for SEED AC5" --repo "$REPO_SLUG" --ref master
  sleep 8
  gh run list --repo "$REPO_SLUG" --workflow "Build ImmortalWRT for SEED AC5" --limit 3
else
  echo "下一步: 在 Actions 手动触发 'Build ImmortalWRT for SEED AC5'(或加 TRIGGER_BUILD=1 自动触发)"
fi
