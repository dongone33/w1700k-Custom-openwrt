#!/bin/bash

set -e

echo "=============================================="
echo "Running custom commands"

# Snapshot branding is display-only; keep version.mk and machine version fields.
sed -i 's/%D %V, %C/%D %C/' package/base-files/files/etc/banner
sed -i 's/%D %V %C/%D %C/' package/base-files/files/etc/openwrt_release
sed -i -e 's/PRETTY_NAME="%D %V"/PRETTY_NAME="%D %C"/' \
       -e 's/OPENWRT_RELEASE="%D %V %C"/OPENWRT_RELEASE="%D %C"/' \
       package/base-files/files/usr/lib/os-release

# -------------------------------------------------
# Fetch W1700K LuCI apps from user's packages repo
# -------------------------------------------------
# luci-app-wifi7 / luci-app-airoha-npu /
# luci-app-airoha-flowsense / luci-app-airoha-fancontrol
# are maintained in yahuisme/packages with native LuCI UI,
# built-in 100% i18n, and strict platform safety checks.
PKG_REPO=$(mktemp -d)
trap 'rm -rf "$PKG_REPO"' EXIT

if ! git clone --depth=1 https://github.com/yahuisme/packages.git "$PKG_REPO"; then
    echo "ERROR: Failed to clone user packages repo!"
    exit 1
fi
PKG_SHA=$(git -C "$PKG_REPO" rev-parse HEAD)
printf 'yahuisme/packages\t%s\t%s\n' "$(git -C "$PKG_REPO" remote get-url origin)" "$PKG_SHA" > .custom-revisions.tsv
echo "yahuisme/packages: $PKG_SHA"
cp -r "$PKG_REPO/luci-app-wifi7" "$PKG_REPO/luci-app-airoha-npu" \
      "$PKG_REPO/luci-app-airoha-flowsense" \
      "$PKG_REPO/luci-app-airoha-fancontrol" package/

# Required patches share the applications' exact packages checkout.
PATCH_DIR="$PKG_REPO/w1700k-patches"
for file in \
    tree/target/linux/airoha/patches-6.18/745-net-pcs-airoha-extend-manual-rx-calib-to-E2-silicon.patch \
    tree/target/linux/airoha/patches-6.18/746-net-dsa-mt7530-pre-deassert-phy-reset-gpios-before-mdio-scan.patch \
    tree/target/linux/airoha/patches-6.18/940-pmdomain-airoha-cpu-pll-fallback.patch \
    tree/package/kernel/mt76/patches/911-mt76-mt7996-refresh-power-limits-on-txpower-changes.patch \
    tree/package/network/utils/iwinfo/patches/999-fix-txpower-list.patch; do
    [ -s "$PATCH_DIR/$file" ] || { echo "ERROR: Required patch missing: $file" >&2; exit 1; }
done
# Preserve buildroot ownership when copying the patch overlay.
cp -a --no-preserve=ownership "$PATCH_DIR/tree/." .
patch -p1 --fuzz=0 < "$PATCH_DIR/patches/002-w1700k-cpufreq-resources.patch"
# wifi-scripts installs directly from source; its Build/Prepare is empty.
patch -p1 --fuzz=0 < "$PATCH_DIR/patches/920-wifi-non-mlo-ap-txpower.patch"

# -------------------------------------------------
# Existing W1700K custom files
# -------------------------------------------------

mkdir -p feeds/luci/modules/luci-mod-status/patches
cp -f "$PATCH_DIR/patches/998-single-wiphy.patch" \
    feeds/luci/modules/luci-mod-status/patches/998-single-wiphy.patch

# Preserve the user's status LED colors, not donor platform enhancements.
DTS=target/linux/airoha/dts/an7581-w1700k-ubi.dts
sed -i -e 's/led-boot = &led_status_red;/led-boot = \&led_status_green;/' \
       -e 's/led-failsafe = &led_status_blue;/led-failsafe = \&led_status_red;/' \
       -e 's/led-running = &led_status_green;/led-running = \&led_status_white;/' "$DTS"
for alias in 'boot green' 'failsafe red' 'running white'; do
    read -r state color <<< "$alias"
    grep -q "led-$state = &led_status_$color;" "$DTS" || { echo "ERROR: LED alias mismatch: $state" >&2; exit 1; }
done

# -------------------------------------------------
# Install latest Aurora LuCI theme
# -------------------------------------------------

for pkg in luci-theme-aurora luci-app-aurora-config; do
    echo "Installing $pkg..."
    rm -rf "package/$pkg"
    if ! git clone --depth=1 "https://github.com/eamonxg/$pkg.git" "package/$pkg"; then
        echo "ERROR: Failed to download $pkg!"
        exit 1
    fi
    if [ ! -f "package/$pkg/Makefile" ]; then
        echo "ERROR: $pkg was downloaded, but Makefile is missing!"
        exit 1
    fi
    PKG_SHA=$(git -C "package/$pkg" rev-parse HEAD)
    printf '%s\t%s\t%s\n' "$pkg" "$(git -C "package/$pkg" remote get-url origin)" "$PKG_SHA" >> .custom-revisions.tsv
    echo "$pkg: $PKG_SHA"
done

# 修改 Aurora 菜单式样（默认侧边栏 + 小圆角）
TPL_DIR="package/luci-app-aurora-config/root/usr/share/aurora"
if [ ! -f "$TPL_DIR/default.template" ]; then
    echo "ERROR: Aurora default template missing: $TPL_DIR/default.template" >&2
    exit 1
fi
sed -i \
    -e "s/nav_type '.*'/nav_type 'sidebar'/g" \
    -e "s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" \
    "$TPL_DIR"/*.template
for template in "$TPL_DIR"/*.template; do
    for setting in "nav_type 'sidebar'" "struct_radius_base '0[.]125rem'"; do
        if ! grep -Eq "^[[:space:]]*option ${setting}[[:space:]]*$" "$template"; then
            echo "ERROR: Aurora preset did not apply: $template ($setting)" >&2
            exit 1
        fi
    done
done
echo "theme-aurora nav preset applied!"


# The temperature & fan overview widget ships as 15_temperature.js inside
# luci-mod-status. Core modules translate via luci-base's "base" domain, so
# append its strings to the upstream base.po for the Chinese UI.
BASE_PO="feeds/luci/modules/luci-base/po/zh_Hans/base.po"
if [ -f "$BASE_PO" ] && [ -f "$DK_PROFILE/po/zh_Hans/base-custom.po" ]; then
    cat "$DK_PROFILE/po/zh_Hans/base-custom.po" >> "$BASE_PO"
fi

echo "Airoha LuCI configuration completed."

# Refresh the feeds-install index so make defconfig discovers the
# newly imported applications and themes.
rm -rf tmp/info 2>/dev/null || true
rm -f tmp/.packageinfo 2>/dev/null || true


# -------------------------------------------------
# Shared regdb customization follows the official 500 patch.
# -------------------------------------------------
mkdir -p package/firmware/wireless-regdb/patches

cp -f "$PATCH_DIR/patches/610-w1700k-power-30.patch" package/firmware/wireless-regdb/patches/
echo "regdb patch: 610-w1700k-power-30.patch"

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


echo "=============================================="
echo "Custom commands completed"
