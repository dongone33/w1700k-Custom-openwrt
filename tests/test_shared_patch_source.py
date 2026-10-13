"""Run the complete customization script using exact sources and local clone boundaries."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from patch_source import PATCHES

ROOT = Path(__file__).resolve().parents[1]
APPS = ('luci-app-wifi7', 'luci-app-airoha-npu', 'luci-app-airoha-flowsense', 'luci-app-airoha-fancontrol')


@unittest.skipUnless(os.environ.get('TXPOWER_SOURCE'), 'set TXPOWER_SOURCE to exact unpatched official source')
class SharedPatchSource(unittest.TestCase):
    def test_complete_customization_and_missing_payloads(self):
        source = Path(os.environ['TXPOWER_SOURCE'])
        payloads = [p.relative_to(PATCHES) for p in PATCHES.rglob('*.patch')]
        used = [p for p in payloads if p.parts[0] not in ('openwrt', 'immortalwrt') or p.parts[0] == 'openwrt']
        for missing in (None, *used):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as temporary:
                base = Path(temporary)
                donor = base / 'donor'
                shutil.copytree(PATCHES, donor / 'w1700k-patches')
                if missing:
                    (donor / 'w1700k-patches' / missing).unlink()
                for app in APPS:
                    shutil.copytree(PATCHES.parent / app, donor / app)
                work = base / 'source'
                for name in ('package/network/config/wifi-scripts/files-ucode/lib/netifd/wireless/mac80211.sh',
                             'package/network/config/wifi-scripts/files-ucode/usr/share/ucode/wifi/hostapd.uc',
                             'package/network/services/hostapd/files/hostapd.uc',
                             'target/linux/airoha/dts/an7581-w1700k-ubi.dts'):
                    destination = work / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source / name, destination)
                for name, text in {
                    'package/base-files/files/etc/banner': '%D %V, %C\n',
                    'package/base-files/files/etc/openwrt_release': '%D %V %C\n',
                    'package/base-files/files/usr/lib/os-release': 'PRETTY_NAME="%D %V"\nOPENWRT_RELEASE="%D %V %C"\n',
                    'feeds/luci/modules/luci-base/po/zh_Hans/base.po': '',
                }.items():
                    destination = work / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_text(text)
                # Source overlays use a directory copy: missing an individual
                # required patch must not silently omit that behavior.
                stub = '''git() {
 if [ "$1" = clone ]; then
  local dest="${@: -1}"
  if [[ "$*" = *yahuisme/packages.git* ]]; then
   printf 'packages\\n' >> "$CALLS"
   cp -a "$DONOR/." "$dest/"
  else
   mkdir -p "$dest/root/usr/share/aurora"
   touch "$dest/Makefile"
   printf "option nav_type 'mega-menu'\\noption struct_radius_base '0.5rem'\\n" > "$dest/root/usr/share/aurora/default.template"
  fi
 elif [[ "$*" = *rev-parse* ]]; then printf '%040d\\n' 123;
 else printf 'https://github.com/yahuisme/packages.git\\n'; fi
}
export -f git
'''
                result = subprocess.run(['bash', '-ec', stub + 'bash "$CUSTOM"'], cwd=work,
                    env=dict(os.environ, DONOR=str(donor), CALLS=str(base / 'calls'),
                             CUSTOM=str(ROOT / 'user/default/custom.sh'), DK_PROFILE=str(ROOT / 'user/default')),
                    text=True, capture_output=True)
                self.assertEqual(result.returncode == 0, missing is None, result.stdout + result.stderr)
                self.assertEqual((base / 'calls').read_text(), 'packages\n')
                if missing is None:
                    for original in (PATCHES / 'tree').rglob('*.patch'):
                        self.assertEqual(original.read_bytes(), (work / original.relative_to(PATCHES / 'tree')).read_bytes())
                    self.assertEqual((PATCHES / 'openwrt/610-w1700k-power-30.patch').read_bytes(),
                                     (work / 'package/firmware/wireless-regdb/patches/610-w1700k-power-30.patch').read_bytes())
                    self.assertEqual((PATCHES / 'patches/998-single-wiphy.patch').read_bytes(),
                                     (work / 'feeds/luci/modules/luci-mod-status/patches/998-single-wiphy.patch').read_bytes())
                    self.assertIn('per_interface_txpower', (work / 'package/network/config/wifi-scripts/files-ucode/lib/netifd/wireless/mac80211.sh').read_text())
                    self.assertIn('123'.zfill(40), (work / '.custom-revisions.tsv').read_text())
                else:
                    self.assertNotIn('Custom commands completed', result.stdout)


if __name__ == '__main__':
    unittest.main()
