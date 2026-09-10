#!/usr/bin/env python3
"""修复上游 lang/node/node/Makefile 把 HOST 侧 node 二进制硬编码为 linux-x64 的问题。

背景(失败 run 34431019225 / 34433074508 的根因):
  immortalwrt/packages 的 lang/node/node/Makefile 里

      NODEJS_BIN:=node-v$(PKG_VERSION)-linux-x64.tar.gz

  是无条件的。在 ubuntu-24.04-arm(aarch64) runner 上, Host/Install 会把 x86-64 的
  node 解包到 staging_dir/hostpkg/bin/node; 该二进制在 arm64 上无法 exec
  (execve -> ENOEXEC), POSIX shell 于是退化成"把它当脚本解释", 报:

      staging_dir/hostpkg/bin/node: 1: Syntax error: ")" unexpected

  导致 host 侧 npm 全部失效(node 官方 tarball 的 bin/npm 是指向 npm-cli.js 的
  符号链接, shebang 走 PATH 上的 hostpkg/bin/node), 于是依赖 npm 的包编译失败。
  实际触发点: net/smartdns 的 smartdns-ui 子包(前端 webui 用 npm 构建):

      cp: cannot stat '.../smartdns-webui/out': No such file or directory
      ERROR: package/feeds/packages/smartdns failed to build.

修复:
  仅当宿主为 arm64 时, 把 NODEJS_BIN 指向 linux-arm64 tarball。
  Makefile 中的 NODEJS_BIN_SUM 是 x64 tarball 的 sha256, 不能复用, 故把
  Download/nodebin 的 HASH 置为 "skip" —— OpenWrt scripts/download.pl 对
  "skip" 完全跳过哈希校验(源码取自 nodejs.org 官方 release 目录)。
"""
import platform
import pathlib
import sys

TARGET = sys.argv[1] if len(sys.argv) > 1 else "feeds/packages/lang/node/node/Makefile"

OLD_BIN = "NODEJS_BIN:=node-v$(PKG_VERSION)-linux-x64.tar.gz"
NEW_BIN = "NODEJS_BIN:=node-v$(PKG_VERSION)-linux-arm64.tar.gz"
OLD_HASH = "HASH:=$(NODEJS_BIN_SUM)"
NEW_HASH = "HASH:=skip"


def main():
    machine = platform.machine().lower()
    if machine not in ("aarch64", "arm64"):
        print(f"[fix-host-node-arch] 宿主架构 {machine} 非 arm64, 无需修改")
        return 0

    path = pathlib.Path(TARGET)
    if not path.is_file():
        print(f"::error::[fix-host-node-arch] 找不到 {TARGET}")
        return 1

    text = path.read_text(encoding="utf-8", errors="replace")
    original = text

    if OLD_BIN in text:
        text = text.replace(OLD_BIN, NEW_BIN)
    if OLD_HASH in text:
        text = text.replace(OLD_HASH, NEW_HASH)

    if text == original:
        print("::error::[fix-host-node-arch] 未匹配到需修改内容(上游结构可能已变化)")
        return 1

    path.write_text(text, encoding="utf-8")

    if NEW_BIN not in text:
        print("::error::[fix-host-node-arch] NODEJS_BIN 未成功改为 arm64")
        return 1
    if "linux-x64.tar.gz" in text:
        print("::error::[fix-host-node-arch] 仍残留 linux-x64 引用")
        return 1
    if NEW_HASH not in text:
        print("::error::[fix-host-node-arch] HASH 未成功置为 skip")
        return 1

    print("[fix-host-node-arch] 已将 host node 二进制改为 linux-arm64 且 HASH=skip")
    return 0


if __name__ == "__main__":
    sys.exit(main())
