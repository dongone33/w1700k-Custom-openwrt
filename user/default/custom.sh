#!/bin/bash

set -e

echo "=============================================="
echo "Running custom commands"

# -------------------------------------------------
# Existing W1700K custom files
# -------------------------------------------------

mkdir -p feeds/luci/modules/luci-mod-status/patches

cp -f $DK_PROFILE/patches/998-single-wiphy.patch \
    feeds/luci/modules/luci-mod-status/patches/998-single-wiphy.patch

if [ ! -d package/luci-app-wifi7 ]; then
    echo "ERROR: luci-app-wifi7 missing" >&2
    exit 1
fi
if [ ! -f $DK_PROFILE/patches/998-wifi7-i18n.patch ]; then
    echo "ERROR: 998-wifi7-i18n.patch missing" >&2
    exit 1
fi
patch -d package/luci-app-wifi7 -p1 --ignore-whitespace < $DK_PROFILE/patches/998-wifi7-i18n.patch

if [ ! -d package/luci-app-w1700k-fancontrol ]; then
    echo "ERROR: luci-app-w1700k-fancontrol missing" >&2
    exit 1
fi
if [ ! -f $DK_PROFILE/patches/998-fancontrol-i18n.patch ]; then
    echo "ERROR: 998-fancontrol-i18n.patch missing" >&2
    exit 1
fi
patch -d package/luci-app-w1700k-fancontrol -p1 --ignore-whitespace < $DK_PROFILE/patches/998-fancontrol-i18n.patch

if [ ! -d package/luci-app-airoha-npu ]; then
    echo "ERROR: luci-app-airoha-npu missing" >&2
    exit 1
fi
if [ ! -f $DK_PROFILE/patches/998-npu-i18n.patch ]; then
    echo "ERROR: 998-npu-i18n.patch missing" >&2
    exit 1
fi
patch -d package/luci-app-airoha-npu -p1 --ignore-whitespace < $DK_PROFILE/patches/998-npu-i18n.patch

if [ ! -d package/luci-app-airoha-flowsense ]; then
    echo "ERROR: luci-app-airoha-flowsense missing" >&2
    exit 1
fi
if [ ! -f $DK_PROFILE/patches/998-flowsense-i18n.patch ]; then
    echo "ERROR: 998-flowsense-i18n.patch missing" >&2
    exit 1
fi
patch -d package/luci-app-airoha-flowsense -p1 --ignore-whitespace < $DK_PROFILE/patches/998-flowsense-i18n.patch


# -------------------------------------------------
# Install latest Aurora LuCI theme
# -------------------------------------------------

echo "Installing latest Aurora LuCI theme..."

rm -rf package/luci-theme-aurora

if ! git clone \
    --depth=1 \
    https://github.com/eamonxg/luci-theme-aurora.git \
    package/luci-theme-aurora
then
    echo "ERROR: Failed to download Aurora theme!"
    exit 1
fi

if [ ! -f package/luci-theme-aurora/Makefile ]; then
    echo "ERROR: Aurora theme was downloaded, but Makefile is missing!"
    exit 1
fi

echo "Aurora theme installed successfully."


# -------------------------------------------------
# Install Aurora theme configuration app
# -------------------------------------------------

echo "Installing Aurora theme configuration app..."

rm -rf package/luci-app-aurora-config

if ! git clone \
    --depth=1 \
    https://github.com/eamonxg/luci-app-aurora-config.git \
    package/luci-app-aurora-config
then
    echo "ERROR: Failed to download Aurora theme configuration app!"
    exit 1
fi

if [ ! -f package/luci-app-aurora-config/Makefile ]; then
    echo "ERROR: Aurora theme configuration app was downloaded, but Makefile is missing!"
    exit 1
fi

echo "Aurora theme configuration app installed successfully."

# 修改 Aurora 菜单式样（默认侧边栏 + 小圆角）
TPL_DIR="package/luci-app-aurora-config/root/usr/share/aurora/"
if ls "$TPL_DIR"/*.template >/dev/null 2>&1; then
    sed -i "s/nav_type '.*'/nav_type 'sidebar'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" "$TPL_DIR"/*.template
    if grep -q "nav_type 'sidebar'" "$TPL_DIR"/*.template; then
        echo "theme-aurora nav preset applied!"
    else
        echo "theme-aurora nav preset failed; continuing!"
    fi
else
    echo "theme-aurora nav preset skipped (no templates); continuing!"
fi


# -------------------------------------------------
# Add Chinese translations for Airoha LuCI apps
# -------------------------------------------------

echo "Installing Chinese translations for Airoha LuCI apps..."

translation_targets=(
    "luci-app-airoha-flowsense|package/luci-app-airoha-flowsense"
    "luci-app-airoha-npu|package/luci-app-airoha-npu"
    "luci-app-w1700k-fancontrol|package/luci-app-w1700k-fancontrol"
    "luci-app-wifi7|package/luci-app-wifi7"
)

for translation_target in "${translation_targets[@]}"; do
    package_name="${translation_target%%|*}"
    target="${translation_target#*|}"
    translation="$DK_PROFILE/po/zh_Hans/${package_name}.po"

    if [ ! -d "$target" ]; then
        echo "ERROR: Translation target package is missing: $target"
        exit 1
    fi
    if [ ! -f "$translation" ]; then
        echo "ERROR: Translation file is missing: $translation"
        exit 1
    fi

    mkdir -p "$target/po/zh_Hans"
    cp -f "$translation" "$target/po/zh_Hans/${package_name}.po"
done

# The temperature & fan overview widget ships as 15_temperature.js inside
# luci-mod-status. Core modules translate via luci-base's "base" domain, so
# append its strings to the upstream base.po for the Chinese UI.
BASE_PO="feeds/luci/modules/luci-base/po/zh_Hans/base.po"
if [ -f "$BASE_PO" ] && [ -f $DK_PROFILE/po/zh_Hans/base-custom.po ]; then
    cat $DK_PROFILE/po/zh_Hans/base-custom.po >> "$BASE_PO"
fi

# The upstream menu titles omit the vendor prefix. Keep the user-facing
# application names explicit without changing application behavior.
if [ -f package/luci-app-airoha-npu/root/usr/share/luci/menu.d/luci-app-airoha-npu.json ]; then
    sed -i 's/"title": "SoC Status"/"title": "Airoha SoC 状态"/' \
        package/luci-app-airoha-npu/root/usr/share/luci/menu.d/luci-app-airoha-npu.json
fi
if [ -d package/luci-app-airoha-flowsense ]; then
    find package/luci-app-airoha-flowsense -type f \( -name '*.json' -o -name '*.js' \) -exec \
        sed -i -e 's/"title": "FlowSense"/"title": "Airoha 流量感知"/g' \
               -e 's/"title": "Airoha FlowSense"/"title": "Airoha 流量感知"/g' {} +
fi

# Move Airoha Fan Control from the System menu into the Status menu, between
# Airoha SoC Status (npu) and Airoha FlowSense. The dispatcher types menu
# order as int, so use consecutive integers: npu 15, fan 16, flowsense 17.
if [ -f package/luci-app-w1700k-fancontrol/root/usr/share/luci/menu.d/luci-app-w1700k-fancontrol.json ]; then
    sed -i -e 's#admin/system/fan#admin/status/fan#g' \
           -e 's#"order": 90#"order": 16#' \
        package/luci-app-w1700k-fancontrol/root/usr/share/luci/menu.d/luci-app-w1700k-fancontrol.json
fi
if [ -f package/luci-app-airoha-flowsense/root/usr/share/luci/menu.d/luci-app-airoha-flowsense.json ]; then
    sed -i 's#"order": 16#"order": 17#' \
        package/luci-app-airoha-flowsense/root/usr/share/luci/menu.d/luci-app-airoha-flowsense.json
fi

echo "Airoha LuCI translations installed successfully."

# The package index is generated during feeds install, before these
# translation files existed. Drop the cached index so make defconfig
# rescans and registers the new luci-i18n-*-zh-cn packages.
rm -rf tmp/info 2>/dev/null || true
rm -f tmp/.packageinfo 2>/dev/null || true


# -------------------------------------------------
# Wireless regdb power boost (quilt-applied, after fork 555)
# 556 CN 2.4G/5.2G + US 5.2G/5.5G to 30dBm
# -------------------------------------------------
mkdir -p package/firmware/wireless-regdb/patches

if [ -f "$DK_PROFILE/patches/610-w1700k-cn-us-power-30.patch" ]; then
    cp -f "$DK_PROFILE/patches/610-w1700k-cn-us-power-30.patch" package/firmware/wireless-regdb/patches/
    echo "regdb patch: 610-w1700k-cn-us-power-30.patch"
else
    echo "ERROR: regdb patch missing: 610-w1700k-cn-us-power-30.patch" >&2
    exit 1
fi


# -------------------------------------------------
# Install MosDNS (mosdns core + v2dat + luci-app-mosdns)
# -------------------------------------------------
echo "Installing latest MosDNS..."
rm -rf package/mosdns
if ! git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns.git package/mosdns; then
    echo "ERROR: Failed to download MosDNS!"; exit 1
fi
# 注意：v5 分支的仓库结构已重构，只剩 luci-app-mosdns/ 和 geo2txt/
# （geo2txt 取代了旧的 v2dat；mosdns 核心改由 feeds 提供）
for pkg in luci-app-mosdns geo2txt; do
    [ -f "package/mosdns/$pkg/Makefile" ] || { echo "ERROR: MosDNS component '$pkg' missing Makefile!"; exit 1; }
done

# luci-app-mosdns 依赖 +v2ray-geoip +v2ray-geosite，官方建议单独克隆更新版仓库
rm -rf feeds/packages/net/v2ray-geodata package/v2ray-geodata
if ! git clone --depth=1 https://github.com/sbwml/v2ray-geodata.git package/v2ray-geodata; then
    echo "ERROR: Failed to download v2ray-geodata!"; exit 1
fi
[ -f package/v2ray-geodata/Makefile ] || { echo "ERROR: v2ray-geodata missing Makefile!"; exit 1; }

echo "MosDNS installed successfully."


# -------------------------------------------------
# Install latest OpenClash
# -------------------------------------------------
echo "Installing latest OpenClash..."
rm -rf /tmp/openclash-src package/luci-app-openclash
if ! git clone --depth=1 https://github.com/vernesong/OpenClash.git /tmp/openclash-src; then
    echo "ERROR: Failed to download OpenClash!"; exit 1
fi
mv /tmp/openclash-src/luci-app-openclash package/luci-app-openclash
rm -rf /tmp/openclash-src
[ -f package/luci-app-openclash/Makefile ] || { echo "ERROR: OpenClash missing Makefile!"; exit 1; }
echo "OpenClash installed successfully."


# -------------------------------------------------
# Install luci-app-taskplan (计划任务)
# -------------------------------------------------
echo "Installing luci-app-taskplan..."
rm -rf /tmp/taskplan-src package/luci-app-taskplan
if ! git clone --depth=1 https://github.com/sirpdboy/luci-app-taskplan.git /tmp/taskplan-src; then
    echo "ERROR: Failed to download luci-app-taskplan!"; exit 1
fi
mv /tmp/taskplan-src/luci-app-taskplan package/luci-app-taskplan
rm -rf /tmp/taskplan-src
[ -f package/luci-app-taskplan/Makefile ] || { echo "ERROR: luci-app-taskplan missing Makefile!"; exit 1; }
echo "luci-app-taskplan installed successfully."


# -------------------------------------------------
# Install Turbo ACC (mufeng05 fork)
# (The device's own hardware acceleration -- e.g. HNAT -- already
#  handles flow acceleration, so turboacc's own "fastpath" engine
#  is shipped disabled by default -- see the config override below)
# -------------------------------------------------
echo "Installing Turbo ACC (mufeng05/turboacc)..."

# Remove any stale checkout to avoid the script's interactive overwrite prompt
rm -rf package/turboacc

if ! curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o /tmp/add_turboacc.sh; then
    echo "ERROR: Failed to download add_turboacc.sh!"; exit 1
fi

if ! bash /tmp/add_turboacc.sh; then
    echo "ERROR: Failed to install Turbo ACC (mufeng05)!"; exit 1
fi
rm -f /tmp/add_turboacc.sh

# -------------------------------------------------
# Fix: mufeng05/turboacc's add_turboacc.sh has no
# "--no-sfe" switch (unlike other turboacc forks) --
# it unconditionally drops shortcut-fe/fast-classifier
# into package/turboacc/shortcut-fe. Combined with this
# config's CONFIG_ALL_KMODS=y, that pulls
# kmod-fast-classifier into the build by default, and it
# fails to compile against this device's Airoha AN7581
# kernel tree ("package/turboacc/shortcut-fe/shortcut-fe
# failed to build").
# We don't need it anyway -- the Airoha NPU already does
# hardware flow offload, and we only want nft-fullcone --
# so just remove the package before it can be built.
# -------------------------------------------------
echo "Removing turboacc's shortcut-fe (not needed, incompatible with this kernel tree)..."
rm -rf package/turboacc/shortcut-fe

[ -f package/turboacc/luci-app-turboacc/Makefile ] || { echo "ERROR: luci-app-turboacc missing Makefile!"; exit 1; }
[ -d package/turboacc/fullconenat-nft ] || { echo "ERROR: fullconenat-nft (nftables fullcone) package not installed!"; exit 1; }
[ -d package/turboacc/fullconenat ] || { echo "ERROR: fullconenat (iptables fullcone) package not installed!"; exit 1; }

if ! ls target/linux/generic/hack-*/952-add-net-conntrack-events-support-multiple-registrant.patch >/dev/null 2>&1; then
    echo "ERROR: 952 kernel patch not placed -- unsupported kernel version!"; exit 1
fi
echo "Turbo ACC (mufeng05) installed successfully."

# -------------------------------------------------
# Fix: the mufeng05/turboacc libnftnl patch adds a
# new source file via Makefile.am but ships no
# PKG_FIXUP, so OpenWrt tries to build from the
# stale (un-regenerated) configure/Makefile.in and
# fails with "package/libs/libnftnl failed to build".
# Force autoreconf so the patched Makefile.am
# actually takes effect.
# -------------------------------------------------
libnftnl_makefile="package/libs/libnftnl/Makefile"
if [ ! -f "$libnftnl_makefile" ]; then
    echo "ERROR: $libnftnl_makefile not found!"; exit 1
fi
if ! grep -q '^PKG_FIXUP:=autoreconf' "$libnftnl_makefile"; then
    sed -i '/^include \$(INCLUDE_DIR)\/package\.mk/i PKG_FIXUP:=autoreconf' "$libnftnl_makefile"
fi
grep -q '^PKG_FIXUP:=autoreconf' "$libnftnl_makefile" || { echo "ERROR: failed to inject PKG_FIXUP:=autoreconf into libnftnl Makefile!"; exit 1; }
echo "libnftnl PKG_FIXUP:=autoreconf applied."

# -------------------------------------------------
# Ship Turbo ACC with its acceleration ("fastpath")
# engine disabled by default
# -------------------------------------------------
# mufeng05/turboacc consolidates all acceleration engines (native
# Flow Offloading, MediaTek/Airoha HNAT, Shortcut-FE, QCA-NSS-ECM...)
# behind a single "fastpath" option. On first boot, its uci-defaults
# script auto-detects available kernel modules and enables one of
# them -- which is exactly what fights with this device's own
# hardware acceleration and forces a manual restart after every boot.
#
# We pre-seed /etc/config/turboacc with "global.set=1" so that the
# on-device uci-defaults script sees the config as already
# initialized and skips its auto-detection entirely, shipping with
# fastpath="none" (the flow-offload/HNAT engine is OFF). Full-cone
# NAT support (the reason turboacc was added in the first place)
# stays enabled. Users can still turn fastpath on manually from
# LuCI > Network > Turbo ACC if they ever want to test it.
turboacc_default_config="package/turboacc/luci-app-turboacc/root/etc/config/turboacc"
if [ ! -f "$turboacc_default_config" ]; then
    echo "ERROR: default turboacc config not found at $turboacc_default_config!"; exit 1
fi

cat > "$turboacc_default_config" <<-'EOF'
config turboacc 'global'
	option set '1'

config turboacc 'config'
	option fastpath 'none'
	option fullcone '1'
	option tcpcca 'cubic'
EOF

echo "Turbo ACC fastpath (flow-offload/HNAT engine) set to disabled by default."

# -------------------------------------------------
# Enable Turbo ACC (nft-fullcone)
# -------------------------------------------------

echo "Enabling Turbo ACC..."

grep -qxF 'CONFIG_PACKAGE_luci-app-turboacc=y' .config || \
    echo 'CONFIG_PACKAGE_luci-app-turboacc=y' >> .config


# -------------------------------------------------
# Enable Chinese language
# -------------------------------------------------

echo "Enabling Chinese language..."

grep -qxF 'CONFIG_LUCI_LANG_zh_Hans=y' .config || \
    echo 'CONFIG_LUCI_LANG_zh_Hans=y' >> .config


# -------------------------------------------------
# Enable Aurora
# -------------------------------------------------

echo "Enabling Aurora theme..."

grep -qxF 'CONFIG_PACKAGE_luci-theme-aurora=y' .config || \
    echo 'CONFIG_PACKAGE_luci-theme-aurora=y' >> .config

grep -qxF 'CONFIG_PACKAGE_luci-app-aurora-config=y' .config || \
    echo 'CONFIG_PACKAGE_luci-app-aurora-config=y' >> .config


echo "=============================================="
echo "Custom commands completed"
