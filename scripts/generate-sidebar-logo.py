#!/usr/bin/env python3
"""Generate DWM-Titus sidebar version badges for Anaconda installer.

Creates 160x64 PNG badges with:
  - 'DWM-Titus' in 20pt NotoSans-Bold (rgba(235, 235, 240, 240))
  - 'v<version>' in 16pt NotoSans-Regular (rgba(235, 235, 240, 240))
"""

import argparse
import os
import re
import subprocess
from PIL import Image, ImageDraw, ImageFont

DEFAULT_FILL = (235, 235, 240, 240)
WIDTH, HEIGHT = 160, 64


def load_font(style: str, size: int):
    """Resolve Fedora's static or variable Noto font through Fontconfig."""
    match = subprocess.run(
        ['fc-match', '-f', '%{file}\n%{index}\n', f'Noto Sans:style={style}'],
        check=True, capture_output=True, text=True,
    ).stdout.splitlines()
    return ImageFont.truetype(match[0], size, index=int(match[1]))


def parse_version(value: str) -> str:
    """Validate the release label and remove its optional v prefix."""
    if not re.fullmatch(r'v?[0-9]+\.[0-9]+\.[0-9]+', value):
        raise argparse.ArgumentTypeError('version must be X.Y.Z or vX.Y.Z')
    return value.removeprefix('v')


def render_logo(version: str, fill=DEFAULT_FILL) -> Image.Image:
    """Render a 160x64 sidebar logo badge with DWM-Titus and version text.

    Args:
        version: Release version string (e.g. '0.7.0' or 'v0.7.0').
        fill: RGBA tuple defining the text color.

    Returns:
        Image.Image: The rendered badge image in RGBA format.
    """
    version = version.lstrip('v')
    img = Image.new('RGBA', (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    font_main = load_font('Bold', 20)
    font_sub = load_font('Regular', 16)

    text_main = 'DWM-Titus'
    text_sub = f'v{version}'

    bbox_m = draw.textbbox((0, 0), text_main, font=font_main)
    w_m = bbox_m[2] - bbox_m[0]

    bbox_s = draw.textbbox((0, 0), text_sub, font=font_sub)
    w_s = bbox_s[2] - bbox_s[0]

    draw.text(((WIDTH - w_m) // 2, 6), text_main, font=font_main, fill=fill)
    draw.text(((WIDTH - w_s) // 2, 33), text_sub, font=font_sub, fill=fill)

    return img


def generate_series(out_dir: str):
    """Generate a batch of sidebar logo badges from 0.7.0 through 0.10.0.

    Args:
        out_dir: Output directory where the PNG badges are saved.
    """
    os.makedirs(out_dir, exist_ok=True)
    versions = []
    for minor in range(7, 10):
        for patch in range(0, 10):
            versions.append(f'0.{minor}.{patch}')
    versions.append('0.10.0')

    for v in versions:
        img = render_logo(v)
        filename = f'sidebar-logo-v{v}.png'
        img.save(os.path.join(out_dir, filename), 'PNG')
    print(f'Generated {len(versions)} logos in {out_dir}')


def main():
    """Parse command-line arguments and execute sidebar logo badge generation."""
    parser = argparse.ArgumentParser(description='Generate DWM-Titus sidebar version badges')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--version', type=parse_version, help='Generate logo for specific version (e.g. 0.7.0)')
    parser.add_argument('--output', help='Output PNG path')
    mode.add_argument('--series', action='store_true', help='Generate full series from 0.7.0 to 0.10.0')
    parser.add_argument('--out-dir', help='Output directory for series (default: branding/sidebar-logos)')
    args = parser.parse_args()

    if args.series and args.output is not None:
        parser.error('--output requires --version; use --out-dir with --series')
    if args.version and args.out_dir is not None:
        parser.error('--out-dir requires --series; use --output with --version')

    if args.series:
        generate_series(args.out_dir if args.out_dir is not None else 'branding/sidebar-logos')
    elif args.version:
        img = render_logo(args.version)
        out = args.output or f'sidebar-logo-v{args.version.lstrip("v")}.png'
        img.save(out, 'PNG')
        print(f'Saved {out}')
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
