#!/usr/bin/env bash
# ============================================================================
# SEED AC5 固件构建缓存预热脚本（在 GitHub Codespace 中运行）
#
# 作用: 在 Codespace(通常 4~8 核, 比 Actions 免费 x86 快) 里完成一次
#       OpenWrt/ImmortalWrt 编译, 然后把 ccache / dl / staging_dir 打包装成
#       Release 资产传回仓库; Actions 工作流会下载该资产作为"热缓存",
#       把冷构建(>6h 超时)变成热构建(1~2h 收尾)。
#
# 用法:
#   1) 在仓库 hu2846/immortalwrt-seed-ac5 上开启 Codespace(建议 8 核机型, 有 64GB 磁盘)
#   2) 终端执行:  bash scripts/codespace-prepare-cache.sh
#   3) 可选环境变量:
#        SKIP_BUILD=1   只打包现有缓存, 不执行编译
#        BUILD_ONLY=1   只编译不打包
#        JOBS=8         并行度(默认 nproc)
#        CACHE_RELEASE=prebuilt-cache   缓存存放的 Release tag
#
# 说明:
#   - 即使编译未完全成功, 脚本也会把已产生的缓存打包上传(可多轮累积)
#   - Release 单文件上限 2GB, 脚本会自动 split 分片; 工作流侧自动拼回
# ============================================================================
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-hu2846/immortalwrt-seed-ac5}"
SRC_REPO="${SRC_REPO:-https://github.com/BeeconMini/immortalwrt.git}"
SRC_BRANCH="${SRC_BRANCH:-25.12.0-rc2}"
CACHE_RELEASE="${CACHE_RELEASE:-prebuilt-cache}"
WORK="${WORK:-/workspaces/build}"
JOBS="${JOBS:-$(nproc)}"
SKIP_BUILD="${SKIP_BUILD:-0}"
BUILD_ONLY="${BUILD_ONLY:-0}"
TARBALL="${TARBALL:-/workspaces/prebuilt-cache.tar.zst}"
PART_SIZE="${PART_SIZE:-1900M}"

log() { echo -e "\n\033[1;36m==> $*\033[0m"; }

log "环境检查"
echo "nproc=$(nproc) arch=$(uname -m)"; free -h | head -2; df -h /workspaces | tail -1
if [ "$(df -BG --output=avail /workspaces | tail -1 | tr -dc '0-9')" -lt 40 ]; then
  echo "⚠️  可用磁盘不足 40GB。完整编译峰值需 60GB+。"
  echo "    请在 Codespace 选择 8 核机型(通常配 64GB 磁盘), 或设置 SKIP_BUILD=1 仅打包。"
fi

log "安装编译依赖"
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential ccache clang cmake curl ecj fastjar file g++ gawk gettext git \
  libelf-dev libncurses-dev libssl-dev python3 python3-docutils python3-setuptools rsync swig time \
  unzip wget zlib1g-dev qemu-utils zstd >/dev/null

log "准备源码目录 $WORK"
mkdir -p "$WORK"
cd "$WORK"
if [ ! -d source/.git ]; then
  git clone -b "$SRC_BRANCH" --single-branch "$SRC_REPO" source
fi
cd source

log "应用本仓库的 feeds / .config / files / 补丁脚本"
CONFIG_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp -f "$CONFIG_REPO_DIR/feeds.conf.default" feeds.conf.default
cp -f "$CONFIG_REPO_DIR/.config" .config
[ -d "$CONFIG_REPO_DIR/files" ] && cp -r "$CONFIG_REPO_DIR/files" ./
mkdir -p .ccache

log "feeds update / install"
./scripts/feeds update -a
./scripts/feeds install -a

log "修复 libffi(fficonfig.h 路径) 与启用 ccache"
python3 "$CONFIG_REPO_DIR/scripts/fix-libffi-makefile.py" feeds/packages/libs/libffi/Makefile || true
grep -qE '^CONFIG_CCACHE=y' .config || { grep -qE '^CONFIG_CCACHE=' .config && sed -i 's|^CONFIG_CCACHE=.*|CONFIG_CCACHE=y|' .config || echo 'CONFIG_CCACHE=y' >> .config; }

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

if [ "$SKIP_BUILD" != "1" ]; then
  log "make download (3 次重试)"
  for i in 1 2 3; do
    make -j$((JOBS+1)) download && break || { echo "重试 $i/3"; sleep 20; }
  done

  log "make -j$JOBS V=s 编译(可用 Ctrl+C 中断, 缓存仍会打包)"
  export CCACHE_DIR="$WORK/source/.ccache" CCACHE_MAXSIZE=8G CCACHE_COMPRESS=true
  set +e
  make -j"$JOBS" V=s
  BUILD_RC=$?
  set -e
  echo "编译退出码: $BUILD_RC (非 0 也可能只是个别包失败, 不影响缓存回收)"
  ccache -s || true
fi

if [ "$BUILD_ONLY" = "1" ]; then log "BUILD_ONLY=1, 结束"; exit 0; fi

log "打包缓存 (.ccache / dl / staging_dir)"
cd "$WORK/source"
rm -f "$TARBALL"
tar -I 'zstd -T0 -3' -cf "$TARBALL" .ccache dl staging_dir
ls -lh "$TARBALL"

log "分片(Release 单文件上限 2GB)并上传到 Release: $CACHE_RELEASE"
rm -f "${TARBALL}".part-*
split -b "$PART_SIZE" -d -a 3 "$TARBALL" "${TARBALL}.part-"
ls -lh "${TARBALL}".part-* | head

export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "${GH_TOKEN:-}" ]; then echo "❌ 未找到 GH_TOKEN/GITHUB_TOKEN"; exit 1; fi
if ! gh release view "$CACHE_RELEASE" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  gh release create "$CACHE_RELEASE" --repo "$REPO_SLUG" \
     --title "Prebuilt build cache" --notes "Codespace 预热的 ccache/dl/staging 缓存, 供 Actions 工作流恢复使用。" || true
fi
gh release upload "$CACHE_RELEASE" "${TARBALL}".part-* --repo "$REPO_SLUG" --clobber

log "完成 ✅ 缓存已上传为 Release '$CACHE_RELEASE' 的资产"
echo "下一步: 在 Actions 里手动触发一次 'Build ImmortalWRT for SEED AC5' 即可"
