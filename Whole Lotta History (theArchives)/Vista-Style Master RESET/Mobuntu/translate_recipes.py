#!/usr/bin/env python3
"""
Mobuntu Recipe Translator
=========================
Converts arkadin91-style debos recipes to Mobuntu pipeline config.

Given a recipe directory (rootfs.yaml + image.yaml + overlays/ + files/),
this script:
  - Parses packages, overlays, scripts, firmware hooks, and bootimg params
  - Detects the source device from firmware paths and DTB references
  - Translates device-specific paths for the specified target device
  - Outputs overlay files, device conf additions, build.env additions,
    and a detailed report of what was done and what needs manual review

Usage:
  python3 translate_recipes.py \\
    --recipes-dir ./mobuntu-recipes-main \\
    --target-device beryllium \\
    --target-brand Xiaomi \\
    [--output-dir ./translated]

The output directory is a drop-in overlay set for Mobuntu's pipeline.
Merge overlays/ into your project's overlays/ and review the .additions
files to update build.env and your device conf.
"""

import os
import re
import sys
import shutil
import argparse
import textwrap
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("ERROR: PyYAML required.  Run: pip install pyyaml --break-system-packages")


# ---------------------------------------------------------------------------
# YAML / template helpers
# ---------------------------------------------------------------------------

def strip_go_templates(text: str) -> str:
    """Remove Go-template directives so PyYAML can parse debos files."""
    return re.sub(r'\{\{-?\s*.*?\s*-?\}\}', '', text)


def load_yaml(path: Path):
    """Load a debos YAML file, stripping Go templates first."""
    if not path.exists():
        return None
    try:
        with open(path) as f:
            return yaml.safe_load(strip_go_templates(f.read()))
    except Exception:
        return None


def extract_packages(doc) -> list:
    """Collect all package names from apt actions in a debos YAML doc."""
    pkgs = []
    if not doc:
        return pkgs
    for action in doc.get('actions') or []:
        if action.get('action') == 'apt':
            p = action.get('packages', [])
            if isinstance(p, list):
                pkgs.extend(str(x) for x in p)
            elif isinstance(p, str):
                pkgs.extend(x.strip() for x in p.split(',') if x.strip())
    return pkgs


# ---------------------------------------------------------------------------
# Shell script parser
# ---------------------------------------------------------------------------

def parse_shell(path: Path) -> dict:
    """Extract semantically interesting commands from a shell script."""
    out = {
        'mask_services':   [],
        'enable_services': [],
        'disable_services':[],
        'wget_urls':       [],
        'env_vars':        {},
        'raw_lines':       [],
    }
    if not path.exists():
        return out
    with open(path) as f:
        lines = f.readlines()
    for raw in lines:
        line = raw.strip()
        out['raw_lines'].append(line)
        if line.startswith('#') or not line:
            continue
        # systemctl <verb> <units...>
        for verb in ('mask', 'enable', 'disable', 'set-default'):
            m = re.match(rf'systemctl\s+{verb}\s+(.*)', line)
            if m and verb != 'set-default':
                out[f'{verb}_services'].extend(m.group(1).split())
        # wget URL
        m = re.search(r'wget\s+(?:\S+\s+)*"?(https?://\S+?)"?\s*$', line)
        if m:
            out['wget_urls'].append(m.group(1))
        # Simple VAR="value" assignments
        m = re.match(r'^(\w+)="([^"]*)"', line)
        if m:
            out['env_vars'][m.group(1)] = m.group(2)
    # Password from  echo "user:pass" | chpasswd
    for line in out['raw_lines']:
        m = re.search(r'echo\s+"(\w+):(\w+)"\s*\|\s*chpasswd', line)
        if m:
            out['env_vars']['_chpasswd_user'] = m.group(1)
            out['env_vars']['_chpasswd_pass'] = m.group(2)
    return out


# ---------------------------------------------------------------------------
# Overlay file parsers
# ---------------------------------------------------------------------------

def parse_firmware_hook(path: Path) -> list:
    """Extract the FW_LIST paths from a qcom-firmware initramfs hook."""
    if not path.exists():
        return []
    content = path.read_text()
    # Try quoted multi-line list: FW_LIST="... \n ..."
    m = re.search(r'FW_LIST="(.*?)"', content, re.DOTALL)
    if not m:
        # Unquoted: FW_LIST=foo \<newline>bar
        m = re.search(r'FW_LIST=(.*?)(?=\n\nadd_firmware|\nadd_firmware)', content, re.DOTALL)
    if not m:
        return []
    raw = m.group(1).replace('\\', ' ').replace('"', '')
    return [p.strip() for p in raw.split() if p.strip()]


def parse_bootimg_hook(path: Path) -> dict:
    """Extract boot parameters from a post-update.d/bootimg hook."""
    if not path.exists():
        return {}
    content = path.read_text()
    result = {}
    for var in ('KERNEL', 'DTB', 'RAMDISK', 'CMDLINE', 'ROOT'):
        m = re.search(rf'^{var}=(.+)$', content, re.MULTILINE)
        if m:
            result[var] = m.group(1).strip().strip('"').strip("'")
    # abootimg / mkbootimg parameters
    for param in ('kerneladdr', 'ramdiskaddr', 'secondaddr', 'tagsaddr', 'pagesize'):
        m = re.search(rf'[- ]{param}[= ](\S+)', content)
        if m:
            result[param] = m.group(1).rstrip(',')
    result['dtb_append'] = 'cat $KERNEL $DTB' in content or 'cat "$KERNEL" "$DTB"' in content
    return result


# ---------------------------------------------------------------------------
# Device detection & path translation
# ---------------------------------------------------------------------------

def detect_source_device(fw_paths: list, bootimg: dict) -> dict:
    """Infer source brand/codename from firmware paths or DTB filename."""
    for p in fw_paths:
        # qcom/sdm845/Brand/device/ pattern
        m = re.search(r'qcom/sdm845/([^/]+)/([^/]+)/', p)
        if m:
            return {'brand': m.group(1), 'codename': m.group(2)}
    # Fallback: DTB filename e.g. sdm845-oneplus-fajita.dtb
    dtb = bootimg.get('DTB', '')
    m = re.search(r'sdm845-(\w+)-(\w+)\.dtb', dtb)
    if m:
        return {'brand': m.group(1).capitalize(), 'codename': m.group(2)}
    return {'brand': 'unknown', 'codename': 'unknown'}


def translate_fw_paths(fw_paths, src, target_brand, target_device):
    """Remap firmware paths from source device to target device."""
    if src['brand'] == 'unknown':
        return fw_paths
    translated = []
    for p in fw_paths:
        new = re.sub(
            rf'qcom/sdm845/{re.escape(src["brand"])}/{re.escape(src["codename"])}/',
            f'qcom/sdm845/{target_brand}/{target_device}/',
            p
        )
        translated.append(new)
    return translated


def find_debs(recipes_dir: Path) -> dict:
    """Locate .deb files bundled in files/ and classify them."""
    debs = {}
    files_dir = recipes_dir / 'files'
    if not files_dir.exists():
        return debs
    for deb in sorted(files_dir.glob('*.deb')):
        lo = deb.name.lower()
        if 'linux-image' in lo:
            debs['kernel_deb'] = deb
            m = re.search(r'linux-image-([^_]+)', deb.name)
            if m:
                debs['kernel_version'] = m.group(1)
        elif 'linux-headers' in lo:
            debs['headers_deb'] = deb
        elif 'firmware' in lo:
            debs['firmware_deb'] = deb
    return debs


# ---------------------------------------------------------------------------
# Output generators
# ---------------------------------------------------------------------------

def gen_firmware_hook(fw_paths, target_brand, target_device) -> str:
    indent = '         '
    fw_list = (' \\\n' + indent).join(fw_paths)
    return f"""\
#!/bin/sh
# Mobuntu — qcom-firmware initramfs hook
# Auto-translated for {target_brand}/{target_device}
# Only boot-essential firmware is included; everything else is deferred
# to request_firmware() post-rootfs-mount.
# Regenerate: translate_recipes.py --target-device {target_device}
set -e

PREREQS=""
case $1 in
    prereqs) echo "${{PREREQS}}"; exit 0;;
esac

. /usr/share/initramfs-tools/hook-functions

FW_LIST="{fw_list}"

add_firmware ${{FW_LIST}}
"""


def gen_bootimg_hook(orig_path: Path, params: dict,
                     src, target_brand, target_device,
                     kernel_version: str) -> str:
    """Produce a translated bootimg hook for the target device."""
    content = orig_path.read_text()

    # Strip original shebang; we'll prepend our own
    content = re.sub(r'^#!/.*\n', '', content)

    # Translate DTB path
    content = re.sub(
        r'(DTB=.*?)sdm845-\S+\.dtb',
        rf'\g<1>sdm845-{target_brand.lower()}-{target_device}.dtb'
        + '  # TODO: verify exact DTB filename (e.g. -tianma, -ebbg)',
        content,
    )

    # Remove A/B slot_suffix — Poco F1 is not A/B
    content = re.sub(r'\s*slot_suffix=_[ab]', '', content)

    # Translate kernel / ramdisk version references
    if kernel_version and src['codename'] != 'unknown':
        # These are fine as-is if the kernel deb version matches; note it anyway
        pass

    header = f"""\
#!/bin/bash
# Auto-translated from arkadin91 recipes
# Source : {src['brand']}/{src['codename']}
# Target : {target_brand}/{target_device}
# Review : kernel path, DTB filename, cmdline, partition labels
"""
    return header + content


def gen_device_conf_additions(p: dict) -> str:
    lines = [
        '# --- Additions from translate_recipes.py ---',
        f'# Source: {p["src_brand"]}/{p["src_codename"]}',
        '',
    ]
    if p.get('kernel_version'):
        lines += [
            f'KERNEL_SERIES="{p["kernel_version"]}"',
            'KERNEL_METHOD="local-deb"',
            f'KERNEL_DEB="files/{p.get("kernel_deb_name", "linux-image.deb")}"',
        ]
    if p.get('masked_services'):
        lines += ['', f'DEVICE_MASKED_SERVICES="{" ".join(p["masked_services"])}"']
    if p.get('enabled_services'):
        lines += [f'DEVICE_SERVICES="{" ".join(p["enabled_services"])}"']
    return '\n'.join(lines)


def gen_build_env_additions(p: dict) -> str:
    lines = [
        '# --- Additions from translate_recipes.py ---',
        '# Merge into build.env as appropriate.',
        '',
    ]
    if p.get('suite'):
        lines.append(f'UBUNTU_RELEASE="{p["suite"]}"')
    if p.get('mirror'):
        lines.append(f'UBUNTU_MIRROR="{p["mirror"]}"')
    if p.get('kernel_version'):
        lines.append(f'KERNEL_SERIES="{p["kernel_version"]}"')
    if p.get('default_user'):
        lines.append(f'DEFAULT_USER="{p["default_user"]}"')
    if p.get('upstream_urls'):
        lines += ['', '# Upstream artifact URLs from install-firmware.sh']
        for k, v in p['upstream_urls'].items():
            lines.append(f'UPSTREAM_{k}="{v}"')
    return '\n'.join(lines)


def gen_report(p: dict) -> str:
    sep = '=' * 62
    lines = [
        sep,
        '  MOBUNTU RECIPE TRANSLATION REPORT',
        sep,
        '',
        f'  Recipes dir : {p["recipes_dir"]}',
        f'  Source      : {p["src_brand"]}/{p["src_codename"]}',
        f'  Target      : {p["target_brand"]}/{p["target_device"]}',
        '',
        '--- EXTRACTED ---',
        '',
        f'  Ubuntu release : {p.get("suite", "not found")}',
        f'  Kernel version : {p.get("kernel_version", "not found in files/")}',
        f'  Firmware deb   : {p.get("firmware_deb_name", "not found")}',
        '',
        f'  Base packages ({len(p.get("base_packages", []))}) — see de-packages.yaml',
        '',
        f'  Firmware in initrd ({len(p.get("fw_translated", []))}) [translated paths]:',
    ]
    for fw in p.get('fw_translated', []):
        orig = p.get('fw_orig_map', {}).get(fw, '')
        arrow = f'  <- {orig}' if orig and orig != fw else ''
        lines.append(f'    {fw}{arrow}')
    lines += [
        '',
        f'  Masked  : {" ".join(p.get("masked_services", [])) or "none"}',
        f'  Enabled : {" ".join(p.get("enabled_services", [])) or "none"}',
        f'  DTB append : {p.get("dtb_append", False)}',
        '',
        '--- FILES GENERATED ---',
        '',
    ]
    for f in p.get('generated', []):
        lines.append(f'  {f}')
    lines += [
        '',
        '--- MANUAL REVIEW REQUIRED ---',
        '',
        '  1. Verify translated firmware paths exist in your firmware bundle:',
        f'       firmware/xiaomi-{p["target_device"]}/firmware.tar.gz',
        f'       Expected: qcom/sdm845/{p["target_brand"]}/{p["target_device"]}/',
        '',
        '  2. Bootimg hook DTB filename — cannot be auto-detected:',
        f'       Likely: sdm845-xiaomi-{p["target_device"]}-tianma.dtb',
        f'       or    : sdm845-xiaomi-{p["target_device"]}-ebbg.dtb',
        '       Update: overlays/etc/initramfs/post-update.d/bootimg',
        '',
        '  3. hexagonrpcd is in the package list — project notes say it',
        '     was intentionally excluded. Decide whether to include it.',
        '',
        '  4. Device-specific udev rules were NOT copied:',
        '       81-libssc-oneplus-fajita.rules  (fajita-specific mount matrix)',
        f'       Create: 81-libssc-xiaomi-{p["target_device"]}.rules if needed',
        '',
        '  5. Kernel deb targets OnePlus hardware. Verify it boots beryllium',
        '     (likely yes — same SoC, DTB selection determines hardware).',
        '',
        sep,
    ]
    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

PASS_THROUGH_OVERLAYS = [
    'usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf',
    'etc/systemd/system/grow-rootfs.service',
    'usr/sbin/grow-rootfs.sh',
    'usr/lib/udev/rules.d/10-fastrpc.rules',
    'usr/lib/udev/rules.d/80-iio-sensor-proxy-libssc.rules',
    'usr/lib/udev/rules.d/80-iio-sensor-proxy.rules',
    'usr/lib/udev/rules.d/90-feedbackd-pmi8998.rules',
    'usr/share/glib-2.0/schemas/99_hidpi.gschema.override',
    'usr/share/dbus-1/system.d/net.hadess.SensorProxy.conf',
    'usr/share/polkit-1/actions/net.hadess.SensorProxy.policy',
    'etc/apt/sources.list.d/extrepo_mobian.sources',
    'etc/apt/sources.list.d/ubuntu.sources',
    'usr/lib/os-release',
    'etc/machine-info',
]

# These are device-specific and need a beryllium variant — skip, warn in report
SKIP_DEVICE_SPECIFIC = [
    '81-libssc-oneplus-fajita.rules',
]


def main():
    ap = argparse.ArgumentParser(
        description='Translate arkadin91-style debos recipes to Mobuntu config',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent('''\
            Examples:
              # Translate for Poco F1 (beryllium):
              python3 translate_recipes.py \\
                --recipes-dir ./mobuntu-recipes-main \\
                --target-device beryllium \\
                --target-brand Xiaomi

              # Translate for OnePlus 6T (fajita) — same device, no path changes:
              python3 translate_recipes.py \\
                --recipes-dir ./mobuntu-recipes-main \\
                --target-device fajita \\
                --target-brand OnePlus
        ''')
    )
    ap.add_argument('--recipes-dir',   required=True, type=Path,
                    help='Path to arkadin91-style recipe directory')
    ap.add_argument('--target-device', required=True,
                    help='Target device codename  (e.g. beryllium, fajita)')
    ap.add_argument('--target-brand',  default='Xiaomi',
                    help='Target device brand     (default: Xiaomi)')
    ap.add_argument('--output-dir',    type=Path, default=Path('./translated'),
                    help='Output directory        (default: ./translated)')
    args = ap.parse_args()

    rdir   = args.recipes_dir.resolve()
    outdir = args.output_dir.resolve()

    if not rdir.exists():
        sys.exit(f'ERROR: recipes dir not found: {rdir}')

    print(f'Translating : {rdir}')
    print(f'Target      : {args.target_brand}/{args.target_device}')
    print(f'Output      : {outdir}')
    outdir.mkdir(parents=True, exist_ok=True)

    # ---- Parse source recipes ----
    rootfs_doc = load_yaml(rdir / 'rootfs.yaml')
    image_doc  = load_yaml(rdir / 'image.yaml')

    suite  = ''
    mirror = ''
    if rootfs_doc:
        for action in rootfs_doc.get('actions') or []:
            if action.get('action') == 'debootstrap':
                suite  = action.get('suite', '')
                mirror = action.get('mirror', '')

    base_pkgs = extract_packages(rootfs_doc)

    de_pkgs = {}
    pkg_dir = rdir / 'packages'
    if pkg_dir.exists():
        for pf in sorted(pkg_dir.glob('packages-*.yaml')):
            de_name = re.sub(r'packages-(.+)\.yaml', r'\1', pf.name)
            de_pkgs[de_name] = extract_packages(load_yaml(pf))

    scripts_dir = rdir / 'scripts'
    final_sh    = parse_shell(scripts_dir / 'final.sh')
    setup_sh    = parse_shell(scripts_dir / 'setup-user.sh')
    install_sh  = parse_shell(scripts_dir / 'install-firmware.sh')

    # ---- Parse overlays ----
    ov_dir = rdir / 'overlays'
    fw_hook_path     = ov_dir / 'usr/share/initramfs-tools/hooks/qcom-firmware'
    bootimg_hook_path= ov_dir / 'etc/initramfs/post-update.d/bootimg'

    fw_paths_orig    = parse_firmware_hook(fw_hook_path)
    bootimg_params   = parse_bootimg_hook(bootimg_hook_path)
    src              = detect_source_device(fw_paths_orig, bootimg_params)
    fw_translated    = translate_fw_paths(fw_paths_orig, src,
                                          args.target_brand, args.target_device)

    # ---- Find .deb files ----
    debs = find_debs(rdir)

    # Kernel version from bootimg hook (most reliable)
    kernel_version = ''
    kpath = bootimg_params.get('KERNEL', '')
    m = re.search(r'vmlinuz-(.+)', kpath)
    if m:
        kernel_version = m.group(1)
    if not kernel_version:
        kernel_version = debs.get('kernel_version', '')

    # Default user / password
    default_user = (setup_sh['env_vars'].get('USERNAME')
                    or setup_sh['env_vars'].get('_chpasswd_user', 'mobuntu'))
    default_pass = setup_sh['env_vars'].get('_chpasswd_pass', '')

    # Build params dict for report / conf generation
    fw_orig_map = dict(zip(fw_translated, fw_paths_orig))
    p = dict(
        recipes_dir    = str(rdir),
        src_brand      = src['brand'],
        src_codename   = src['codename'],
        target_brand   = args.target_brand,
        target_device  = args.target_device,
        suite          = suite,
        mirror         = mirror,
        base_packages  = base_pkgs,
        fw_orig        = fw_paths_orig,
        fw_translated  = fw_translated,
        fw_orig_map    = fw_orig_map,
        dtb_append     = bootimg_params.get('dtb_append', False),
        masked_services  = final_sh['mask_services'],
        enabled_services = final_sh['enable_services'],
        wget_urls        = final_sh['wget_urls'],
        kernel_version   = kernel_version,
        kernel_deb_name  = debs.get('kernel_deb', Path('linux-image.deb')).name,
        firmware_deb_name= debs.get('firmware_deb', Path('firmware.deb')).name
                           if 'firmware_deb' in debs else 'not bundled',
        default_user     = default_user,
        default_pass     = default_pass,
        upstream_urls    = install_sh['env_vars'],
        generated        = [],
    )

    # ---- Generate output files ----

    def write(rel, content, executable=False):
        dst = outdir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(content)
        if executable:
            dst.chmod(0o755)
        p['generated'].append(str(rel))

    def copy_overlay(rel):
        src_file = ov_dir / rel
        if not src_file.exists():
            return
        name = src_file.name
        if any(skip in name for skip in SKIP_DEVICE_SPECIFIC):
            return
        dst = outdir / 'overlays' / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_file, dst)
        p['generated'].append(f'overlays/{rel}')

    # 1. Translated qcom-firmware hook
    if fw_paths_orig:
        write(
            'overlays/usr/share/initramfs-tools/hooks/qcom-firmware',
            gen_firmware_hook(fw_translated, args.target_brand, args.target_device),
            executable=True,
        )

    # 2. Translated bootimg post-update hook
    if bootimg_hook_path.exists():
        write(
            'overlays/etc/initramfs/post-update.d/bootimg',
            gen_bootimg_hook(
                bootimg_hook_path, bootimg_params, src,
                args.target_brand, args.target_device, kernel_version,
            ),
            executable=True,
        )

    # 3. Pass-through overlays (device-agnostic)
    for rel in PASS_THROUGH_OVERLAYS:
        copy_overlay(rel)

    # 4. device.conf.additions
    write('device.conf.additions', gen_device_conf_additions(p))

    # 5. build.env.additions
    write('build.env.additions', gen_build_env_additions(p))

    # 6. de-packages.yaml — all DE package groups
    de_yaml_lines = ['# Desktop environment package groups (from recipes)\n']
    for de_name, pkgs in de_pkgs.items():
        de_yaml_lines.append(f'{de_name}:')
        de_yaml_lines.extend(f'  - {pkg}' for pkg in sorted(set(pkgs)))
        de_yaml_lines.append('')
    write('de-packages.yaml', '\n'.join(de_yaml_lines))

    # 7. base-packages.txt — flat list for comparison with qcom.yaml
    all_base = sorted(set(base_pkgs))
    write('base-packages.txt', '\n'.join(all_base) + '\n')

    # 8. Report
    report = gen_report(p)
    write('translation-report.txt', report)

    print()
    print(report)


if __name__ == '__main__':
    main()
