#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright (c) 2019 The ungoogled-chromium Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
"""
Aerium branding sweep for the Linux (AppImage) build. Ported from the
Windows repo's build.py:_apply_branding() - same BRANDING-file rewrite and
grd/grdp/xtb string sweep, since both are pure Python string operations on
files shared unchanged across every Chromium platform. The Windows-only
piece (chrome/install_static/chromium_install_modes.h - shortcut names,
ProgIDs, registry paths) is skipped: that install-mode-constants file is a
Windows-specific source, it doesn't exist in a Linux checkout.
"""

import sys
from pathlib import Path

_ROOT_DIR = Path(__file__).resolve().parent.parent
_SRC_DIR = _ROOT_DIR / 'build' / 'src'

_BRAND_NAME = 'Aerium'
_COMPANY_NAME = 'Dioide'


def apply_branding():
    source_tree = _SRC_DIR
    print(f'Applying {_BRAND_NAME} branding...')

    # BRANDING: product, installer, company and copyright
    branding_path = source_tree / 'chrome' / 'app' / 'theme' / 'chromium' / 'BRANDING'
    branding_lines = []
    for line in branding_path.read_text(encoding='utf-8').splitlines():
        if line.startswith('PRODUCT_'):
            line = line.replace('Chromium', _BRAND_NAME)
        elif line.startswith('COMPANY_FULLNAME=') or line.startswith('COMPANY_SHORTNAME='):
            line = line.split('=', 1)[0] + '=' + _COMPANY_NAME
        elif line.startswith('COPYRIGHT='):
            line = ('COPYRIGHT=Copyright @LASTCHANGE_YEAR@ {}. '
                    'All rights reserved.'.format(_COMPANY_NAME))
        branding_lines.append(line)
    branding_path.write_text('\n'.join(branding_lines) + '\n', encoding='utf-8')

    # Product name in every UI string source (.grd/.grdp and all .xtb
    # locales) - identical sweep to the Windows repo's build.py, see there
    # for the fallback-to-English caveat on changed message IDs.
    string_roots = ('chrome', 'components', 'extensions', 'ui', 'content')
    string_suffixes = ('.grd', '.grdp', '.xtb')
    replaced_count = 0
    for root in string_roots:
        root_path = source_tree / root
        if not root_path.exists():
            continue
        for path in root_path.rglob('*'):
            if path.suffix not in string_suffixes or not path.is_file():
                continue
            try:
                text = path.read_text(encoding='utf-8')
            except (UnicodeDecodeError, OSError):
                continue
            if 'Chromium' not in text and 'ungoogled-chromium' not in text:
                continue
            new_text = text.replace('The Chromium Authors', _COMPANY_NAME)
            new_text = new_text.replace('Chromium', _BRAND_NAME)
            new_text = new_text.replace(
                'ungoogled-chromium', '{} by {}'.format(_BRAND_NAME, _COMPANY_NAME))
            if new_text != text:
                path.write_text(new_text, encoding='utf-8')
                replaced_count += 1
    print(f'Renamed product in {replaced_count} string files')

    # Logo assets - same source tree paths Windows overwrites in-place;
    # ninja copies these into out/Default/ as part of the normal build, so
    # package.sh's fixed file list (product_logo_48.png etc.) picks up the
    # Aerium-branded versions automatically with no packaging changes needed
    # beyond which sizes that list includes.
    brand_dir = _ROOT_DIR / 'brand'
    theme_dir = source_tree / 'chrome' / 'app' / 'theme' / 'chromium'
    theme_dir.mkdir(parents=True, exist_ok=True)
    (theme_dir / 'product_logo.svg').write_bytes((brand_dir / 'product_logo.svg').read_bytes())
    for png_path in brand_dir.glob('product_logo_*.png'):
        (theme_dir / png_path.name).write_bytes(png_path.read_bytes())

    # In-app logos packed into the theme_resources_*.pak files. These are
    # "chrome_scaled_image" structures in chrome/app/theme/theme_resources.grd
    # and are NOT read from chrome/app/theme/chromium/ - grit's
    # ChromeScaledImage gatherer prefixes the path declared in the grd with the
    # output context directory, so the bytes actually packed come from
    #   chrome/app/theme/default_<scale>_percent/<path declared in the grd>
    # and the copies made into chrome/app/theme/chromium/ above are never read
    # for these resources (upstream does not even ship a 32px file there).
    #
    # Mind the declared paths - they are not all the same shape, and two of
    # them differ from the Windows repo's:
    #   IDR_PRODUCT_LOGO_32        chromium/product_logo_32.png
    #     chrome://theme/current-channel-logo, i.e. the About page
    #     (chrome://settings/help) logo.
    #   IDR_PRODUCT_LOGO_16        chromium/linux/product_logo_16.png
    #     The is_linux branch of the grd puts this one under linux/, unlike
    #     every other platform. Used for the task manager's browser row
    #     (browser_process_task.cc) and the window/tab icon fallback
    #     (tab_icon_view.cc).
    #   IDR_PRODUCT_LOGO_NAME_22 / _WHITE
    #                              chromium/product_logo_name_22{,_white}.png
    #     The wordmark, drawn in the payment request dialog header - the plain
    #     one on light backgrounds, the white one in dark mode
    #     (payment_request_views_util.cc). These have no roundel-sized
    #     equivalent, so they live in brand/inapp/ mirroring the Windows repo.
    #
    # The 300% pak has no chromium/ assets upstream at all and falls back to
    # the 100% ones via fallback_to_low_resolution; likewise upstream ships no
    # 2x under chromium/linux/, but we have a real 32x32 for it so there is no
    # reason to let it upscale the 16x16.
    scaled_images = {
        'default_100_percent': {
            'chromium/product_logo_32.png': 'product_logo_32.png',  # 32x32
            'chromium/linux/product_logo_16.png': 'product_logo_16.png',  # 16x16
            'chromium/product_logo_name_22.png':
                'inapp/default_100_percent/product_logo_name_22.png',  # 88x22
            'chromium/product_logo_name_22_white.png':
                'inapp/default_100_percent/product_logo_name_22_white.png',  # 88x22
        },
        'default_200_percent': {
            'chromium/product_logo_32.png': 'product_logo_64.png',  # 64x64
            'chromium/linux/product_logo_16.png': 'product_logo_32.png',  # 32x32
            'chromium/product_logo_name_22.png':
                'inapp/default_200_percent/product_logo_name_22.png',  # 181x44
            'chromium/product_logo_name_22_white.png':
                'inapp/default_200_percent/product_logo_name_22_white.png',  # 181x44
        },
    }
    for scale_dir, entries in scaled_images.items():
        scale_root = source_tree / 'chrome' / 'app' / 'theme' / scale_dir
        for grd_rel_path, brand_rel_path in entries.items():
            scale_dst = scale_root / grd_rel_path
            scale_dst.parent.mkdir(parents=True, exist_ok=True)
            scale_dst.write_bytes((brand_dir / brand_rel_path).read_bytes())

    webui_logo_dst = source_tree / 'ui' / 'webui' / 'resources' / 'images' / 'chrome_logo_dark.svg'
    if webui_logo_dst.parent.exists():
        webui_logo_dst.write_bytes((brand_dir / 'chrome_logo_dark.svg').read_bytes())


if __name__ == '__main__':
    apply_branding()
    sys.exit(0)
