# ImmortalWRT Firmware for BeeconMini SEED AC5

基于 [BeeconMini/immortalwrt](https://github.com/BeeconMini/immortalwrt) 的 `25.12.0-rc2` 分支,
为 SEED AC5 路由器定制的固件,集成配网中心、科学上网、Docker 等常用插件。

## 固件信息

| 项目 | 值 |
|---|---|
| 架构 | MediaTek Filogic 830 (MT7981) |
| 型号 | BeeconMini SEED AC5 |
| 默认 IP | **192.168.88.1** |
| 默认用户名 | root |
| 默认密码 | 无密码 |
| 包管理器 | APK (opkg 兼容) |

## 预装插件

### LuCI 应用

| 包名 | 中文名 | 说明 |
|---|---|---|
| `luci-app-argon-config` | Argon 主题配置 | 美化界面主题 |
| `luci-app-autoreboot` | 定时重启 | 定时自动重启路由器 |
| `luci-app-cpufreq` | CPU 频率管理 | 调整 CPU 频率策略 |
| `luci-app-cpulimit` | CPU 限制 | 限制进程 CPU 占用 |
| `luci-app-dockerman` | Docker 管理 | 容器管理界面(配网中心强制依赖) |
| `luci-app-firewall` | 防火墙 | 防火墙与端口转发 |
| `luci-app-homeproxy` | HomeProxy | 基于 sing-box 的代理 |
| `luci-app-lucky` | Lucky | DDNS/SSL/WOL 综合工具 |
| `luci-app-lxc` | LXC 容器 | Linux 容器管理 |
| `luci-app-mwan3` | 多线负载均衡 | 多 WAN 口负载均衡(配网中心强制依赖) |
| `luci-app-nikki` | Nikki | sing-box 代理前端 |
| `luci-app-package-manager` | 包管理器 | 在线安装 IPK/APK |
| `luci-app-socat` | Socat | 端口转发工具 |
| `luci-app-statistics` | 统计 | 网络流量/系统状态统计 |
| `luci-app-store` | 应用商店 | IPK/APK 在线商店 |
| `luci-app-unblockneteasemusic` | 解锁网易云音乐 | 解锁网易云灰色歌曲 |
| `luci-app-upnp` | UPnP | 自动端口映射 |
| `luci-app-usb-printer` | USB 打印机共享 | 通过网络共享 USB 打印机 |
| `luci-app-wechatpush` | 微信推送 | 路由器状态推送至微信 |
| `luci-app-wol` | 网络唤醒 | 远程唤醒局域网设备 |
| `luci-app-clashoo` | Clash OO | Clash 代理前端 |
| `luci-app-diskman` | 磁盘管理 | 磁盘分区与管理 |
| `luci-app-filebrowser` | 文件管理 | Web 文件管理器 |

### 网络加速

- 软件流量卸载: `kmod-nft-offload` + `kmod-nf-flow` (已启用)
- 硬件 NAT: 由 MT7981 内核驱动自动支持

## 编译环境

| 项目 | 要求 |
|---|---|
| 操作系统 | **Ubuntu 22.04 LTS**(推荐) |
| CPU | 4 核以上,建议 8 核 |
| 内存 | 8G 以上,建议 16G |
| 磁盘 | **至少 150G**,建议 250G |
| 网络 | 需能访问 GitHub 和境外源 |

磁盘建议单独挂载,避免系统盘被编译产物撑爆(完整编译约占用 70G)。

### 编译依赖

完整依赖列表(约 300+ 个包):

```bash
sudo apt update
sudo apt install -y build-essential ccache clang cmake curl \
  ecj fastjar file g++ gawk gettext git \
  libelf-dev libncurses5-dev libncursesw5-dev libssl-dev \
  python3 python3-docutils python3-setuptools rsync swig time \
  unzip wget zlib1g-dev qemu-utils \
  bzip2 autoconf automake bison flex gperf libtool \
  lld llvm ninja-build pkgconf texinfo zstd
```

### 编译步骤

```bash
# 1. 拉取源码
git clone -b 25.12.0-rc2 --single-branch https://github.com/BeeconMini/immortalwrt.git
cd immortalwrt

# 2. 应用配置
cp /path/to/this/repo/.config .config
cp /path/to/this/repo/feeds.conf.default feeds.conf.default

# 3. 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig

# 4. 编译
make -j$(nproc) download    # 先下载源码包
make -j$(nproc) V=s         # 开始编译(首次约 3-8 小时)
```

编译产物位于 `bin/targets/mediatek/filogic/`。

## 如何修改配置

### 方法 1: 在 GitHub 上直接编辑 `.config`

1. 打开 [.config](https://github.com/hu2846/immortalwrt-seed-ac5/blob/master/.config)
2. 点击右上角 ✏️ 编辑按钮
3. 找到要修改的配置项:
   - `CONFIG_PACKAGE_包名=y` 表示编译进固件
   - `# CONFIG_PACKAGE_包名 is not set` 表示不编译
4. 例如取消 `luci-app-lucky`:
   - 把 `CONFIG_PACKAGE_luci-app-lucky=y` 改为 `# CONFIG_PACKAGE_luci-app-lucky is not set`
5. 添加新包: 在文件末尾另起一行加上 `CONFIG_PACKAGE_包名=y`
6. 点击 **Commit changes**, 自动触发编译

### 方法 2: 本地编译

```bash
git clone -b 25.12.0-rc2 --single-branch https://github.com/BeeconMini/immortalwrt.git
cd immortalwrt
cp /path/to/this/repo/.config .config
cp /path/to/this/repo/feeds.conf.default feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make -j$(nproc) V=s
```

## 如何触发编译

| 方式 | 操作 |
|---|---|
| 手动触发 | 打开 Actions 页面 → Run workflow |
| 修改配置 | 编辑 `.config` 并 commit 到 master 分支 |
| 定时检查 | 每天 UTC 0 点自动检查上游更新 |

编译完成后,固件会自动发布到 **Releases** 页面和 Actions 的 Artifacts 中。

## 配网中心安装

固件刷入后,按以下步骤安装配网中心插件:

1. 系统 → 软件包,更新列表,安装 `luci-app-filebrowser-go`
2. 服务 → FileBrowser,启用并打开 Web 界面(默认 admin/admin)
3. 进入 root 目录,上传配网中心插件文件
4. SSH 登录设备(默认 root,无密码),执行:
   ```bash
   sh beeconmini2-seed-ac5*
   ```
5. 安装到最后 SSH 断开是正常现象
6. 在 Web 后台查看,没出现就退出重新登录

## 许可证

基于 ImmortalWRT 项目,遵循 GPL-2.0 许可。