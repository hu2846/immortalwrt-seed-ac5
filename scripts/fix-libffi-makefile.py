#!/usr/bin/env python3
"""Fix immortalwrt/packages libs/libffi/Makefile.

上游 InstallDev 里复制 fficonfig.h 的写法
    $(CP) \
        $(PKG_BUILD_DIR)/$(GNU_TARGET_NAME)*/fficonfig.h \
        $(1)/usr/include/
其 glob 在 libffi 3.4.7 的构建目录布局下匹配不到文件, 导致 libffi 编译失败
(历史 run 34222663260 / 34339104005 均栽在这)。本脚本将其改为
    $(CP) \
        $$(shell find $(PKG_BUILD_DIR) -name fficonfig.h -print -quit) \
        $(1)/usr/include/
即无论 fficonfig.h 落在构建目录哪个位置都能兜底复制。

注意: 不能把这改动做成 feeds/.../libffi/patches/*.patch —— 那会被 OpenWrt
在 libffi 源码树里应用(而目标其实是 feed 的 Makefile), 且会破坏 host prepare
(历史 run 34358095685 的教训: 畸形补丁令 patch 直接报错)。

用法: python3 fix-libffi-makefile.py <path/to/libs/libffi/Makefile>
找不到目标片段时报错退出(防止上游改动后本修复静默失效)。
"""
import sys


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: fix-libffi-makefile.py <libffi/Makefile>')
    path = sys.argv[1]
    with open(path, encoding='utf-8') as f:
        s = f.read()

    old = (
        '\t$(CP) \\\n'
        '\t\t$(PKG_BUILD_DIR)/$(GNU_TARGET_NAME)*/fficonfig.h \\\n'
        '\t\t$(1)/usr/include/\n'
    )
    new = (
        '\t$(CP) \\\n'
        '\t\t$$(shell find $(PKG_BUILD_DIR) -name fficonfig.h -print -quit) \\\n'
        '\t\t$(1)/usr/include/\n'
    )
    if old not in s:
        sys.exit('ERROR: libffi Makefile 中未找到待修复的 fficonfig.h glob 片段, '
                 '上游可能已变更, 请人工检查: ' + path)
    s = s.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(s)
    print('libffi Makefile 已修复: fficonfig.h 改用 find 兜底复制')


if __name__ == '__main__':
    main()
