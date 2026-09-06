# BeeconMini SEED AC5 / ImmortalWRT 固件编译方案

> 目标:在全新虚拟机上编译 `BeeconMini/immortalwrt` 25.12.0-rc2,产出 AC5 固件,
> 并满足「配网中心」插件的全部安装条件。
>
> 方案基于旧虚拟机(192.168.88.162)的实测环境整理,其编译产物已抢救备份至 `./rescue/`。

---

## 零、上次为什么不够用(血的教训)

旧虚拟机配置:4 核 i3-N305 / 7.8G 内存 / **97G 磁盘** / Ubuntu 24.04.4

编译完成后磁盘占用:

| 目录 | 占用 | 说明 |
|---|---|---|
| `build_dir` | **53G** | 大头,其中 target-aarch64 占 42G |
| `dl` | 4.8G | 上游源码包缓存 |
| `staging_dir` | 4.8G | 交叉工具链与暂存 |
| `bin` | 512M | 固件产物 |
| `feeds` + `package` | 434M | 软件源 |
| **合计** | **约 69G** | |

加上系统本身 ~10G,**97G 的盘最后只剩 3.2G**,几乎撑爆。
任何一次 `make clean && make` 重编、或者多编一个机型,都会直接失败。

---

## 一、新虚拟机配置建议

| 项目 | 最低 | **推荐** | 理由 |
|---|---|---|---|
| **磁盘** | 150G | **250G** | 详见上文;低于 150G 会重蹈覆辙 |
| CPU | 4 核 | **8 核以上** | 4 核首次编译数小时;`make -j$(nproc)` 直接受益 |
| 内存 | 8G | **16G** | 8G 够用,16G 可开更大并行度 |
| 系统 | Ubuntu Server **22.04 LTS** | 22.04 LTS | 官方推荐版本;24.04 能编但非官方验证 |
| 网络 | 能访问 GitHub | 能访问 GitHub | feeds 与 dl 都要拉境外源 |

磁盘三个注意点:

1. **不要用「动态分配 + 小上限」**。VMware/VirtualBox 的动态盘在编译中途撑满会直接搞坏文件系统,
   宁可直接给固定大小,或者给足上限。
2. **建议单独挂一块盘给 `/home`** 或直接在 `/home` 下建编译目录,系统盘和编译盘分开,
   以后系统崩了源码还在。
3. 若用 WSL2,默认虚拟磁盘上限 1TB 但会**只增不减**,注意 `wsl --shutdown` 后做磁盘回收。

---

## 二、编译步骤

以下步骤均可由配套脚本 `build_immortalwrt.sh` 一键完成,此处列出便于理解和手动干预。

### 1. 安装编译依赖

官方给出的完整依赖清单(来自《SEED AC系列开发说明V1.1》):

```bash
sudo apt update && sudo apt install -y \
  ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
  bzip2 ccache clang cmake cpio curl device-tree-compiler diffutils ecj fastjar \
  flex gawk gcc-multilib g++-multilib gettext genisoimage git gperf g++ gcc \
  grep help2man haveged intltool libc6-dev-i386 libc6-dev libelf-dev libfuse-dev \
  lib32gcc-s1 libgmp3-dev libmpc-dev libmpfr-dev libncurses5-dev libncurses-dev \
  libncursesw5-dev libpython3-dev libreadline-dev libssl-dev libtool libxml-parser-perl \
  libdevmapper-dev libglib2.0-dev libgnutls28-dev libyaml-dev libltdl-dev lib32z1-dev \
  lld llvm lrzsz make manpages-posix-dev msmtp nano ninja-build ocaml-nox \
  ocaml-findlib patch pkgconf python3 python3-docutils python3-ply python3-pyelftools \
  python3-pip python3-setuptools python3-distutils qemu-utils quilt re2c rsync scons \
  sharutils sphinx-common sphinxsearch subversion swig tar tcl texinfo uglifyjs unzip \
  upx-ucl vim wget xmlto xxd zlib1g-dev zstd
```

其中 **Ubuntu 24.04 需要注意**:`python3-distutils` 和 `sphinxsearch` 在新版仓库中已移除,
安装失败可以直接去掉这两个包(不影响编译)。

### 2. 拉取源码

```bash
git clone -b 25.12.0-rc2 --single-branch \
  https://github.com/BeeconMini/immortalwrt.git
cd immortalwrt
```

`--single-branch` 很重要,能省下大量 clone 时间和空间。

### 3. 恢复 dl 缓存(可选但强烈建议)

旧机器上的 **4.8G 上游源码包缓存已备份在 `./rescue/dl/`**,直接拷过去能省掉几个小时的
重复下载,也能规避境外源抽风:

```bash
mkdir -p ~/immortalwrt/dl
cp -r /path/to/rescue/dl/* ~/immortalwrt/dl/
```

### 4. 更新并安装 feeds

```bash
./scripts/feeds update -a
./scripts/feeds install -a
```

### 5. 恢复配置

旧机器上验证过、且**已满足配网中心全部依赖**的 `.config` 已备份在 `./rescue/config/.config`。
直接复用最省事:

```bash
cp /path/to/rescue/config/.config ~/immortalwrt/.config
make defconfig     # 补齐依赖、消除 .config 与源码版本差异
```

若想从零配置,则按官方路径在 `make menuconfig` 中依次选:
`MediaTek Ralink ARM` → `Filogic 8x0 (MT798x)` → `BeeconMini SEED AC系列产品`

### 6. 编译

```bash
make -j$(nproc) download   # 先把源码包下齐,便于单独排错
make -j$(nproc) V=s        # V=s 输出详细日志,便于定位失败
```

首次编译在 4 核机器上通常 **3~8 小时**,8 核可显著缩短。
**注意**:`make -j$(nproc)` 在并行度很高时偶发依赖顺序错误,若报错可降级为 `make -j1 V=s` 重跑。

### 7. 产物

```
bin/targets/mediatek/filogic/
├── immortalwrt-mediatek-filogic-beeconmini_seed-ac5-squashfs-sysupgrade.bin   # 刷机用这个
└── immortalwrt-mediatek-filogic-beeconmini_seed-ac5-initramfs-kernel.bin      # 救砖/首次刷入用
```

---

## 三、配置要点(配网中心的硬性条件)

配网中心安装指南明确要求,以下必须**在编译阶段就勾进固件**,装完再补会很麻烦:

| 配置项 | 状态 | 说明 |
|---|---|---|
| `CONFIG_USE_APK=y` | 必需 | 指南点名要「APK 包管理器」版本 |
| `luci-app-dockerman` | 必需 | 强制依赖 |
| `mwan3` / `luci-app-mwan3` | 必需 | 强制依赖 |
| `dockerd` / `docker` | 必需 | 强制依赖 |
| `kmod-nft-offload` / `kmod-nf-flow` | 建议 | 软件流量卸载,提升 NAT 性能 |
| USB 网卡相关 | 可选 | `usbutils` `kmod-usb-net-*` `usb-modeswitch` `usbmuxd` 等 |

旧配置(`.config`)中已全部满足,关键值:

```
CONFIG_TARGET_BOARD="mediatek"
CONFIG_TARGET_SUBTARGET="filogic"
CONFIG_TARGET_PROFILE="DEVICE_beeconmini_seed-ac5"
CONFIG_TARGET_mediatek_filogic_DEVICE_beeconmini_seed-ac5=y
CONFIG_LINUX_6_12=y
CONFIG_USE_APK=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_ROOTFS_PARTSIZE=160      # 注意:根分区 160MB
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_mwan3=y
CONFIG_PACKAGE_kmod-nft-offload=y
```

已勾选 24 个 LuCI 应用,含 passwall、ssr-plus、smartdns、lucky、store、turboacc、
argon-config、statistics、wechatpush 等。

**分支一定要对**:配网中心指南写死「仅适配 `BeeconMini/immortalwrt/tree/25.12.0-rc2`」。
`BeeconMini/lede` 那个仓库适配的是 SEED **AC5S**(不同机型),且配网中心未对其做适配。

---

## 四、配网中心插件安装(固件刷好之后)

1. 固件刷入设备,联网。
2. 系统 → 软件包,更新列表,搜索并安装 `luci-app-filebrowser-go`。
3. 服务 → FileBrowser,启用并打开 Web 界面(默认 `admin` / `admin`)。
4. 进入 root 目录,上传配网中心插件文件。
5. SSH 登录设备(默认 `root`,无密码),执行:
   ```bash
   sh beeconmini2-seed-ac5*
   ```
   安装到最后 **SSH 断开是正常现象**。
6. 安装完在 Web 后台查看,没出现就退出重新登录。
7. (可选)把 docker 目录迁到 eMMC 分区以提升容器部署速度:
   ```bash
   mount /dev/mmcblk0p5 /overlay/upper/opt/docker
   uci set dockerd.globals.data_root='/overlay/upper/opt/docker'
   uci commit dockerd
   /etc/init.d/dockerd restart
   ```

---

## 五、踩坑提醒

1. **不要用 root 编译**。用普通用户(如 `a`),否则会出现各种权限警告甚至失败。
2. **编译路径不要有中文或空格**。
3. **保证网络通畅**,feeds 和 dl 都依赖境外源,必要时准备代理。
4. **磁盘水位监控**:编译中 `build_dir` 会持续膨胀,建议开个 `watch df -h`。
5. `make download` 单独先跑,能提前暴露下载失败,避免编了几小时才挂。
6. 中断后重跑用 `make -j$(nproc)` 即可,OpenWrt 构建系统支持增量。
7. 想换配置时:改完 `.config` 后先 `make defconfig`,避免依赖缺失。

---

## 附:已备份的产物

| 文件 | 大小 | 说明 |
|---|---|---|
| `rescue/config/.config` | 328K | 已验证的完整编译配置,可直接复用 |
| `rescue/config/.config.old` | 328K | 上一版配置 |
| `rescue/config/feeds.conf.default` | 1K | feeds 源定义 |
| `rescue/firmware/*.bin` | 298M | 8/29 编译的 AC5 固件(sysupgrade 168M + initramfs 128M) |
| `rescue/dl/` | **1.1G** | 上游源码包缓存,**不完整**(原始 4.8G,传了约 23% 时旧机器关机) |

> 关于 `dl`:只抢救出 1.1G(46887 个文件),原始为 4.8G。仍然值得用 ——
> dl 目录里每个包都是独立文件,缺的会在 `make download` 阶段自动补齐,
> 已下载的部分能实打实省下对应的下载时间。脚本中的 `make download` 会做校验,
> 不会因个别文件不完整而出错。
