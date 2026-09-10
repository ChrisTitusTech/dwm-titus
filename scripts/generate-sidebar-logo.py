#!/usr/bin/env python3
"""Generate DWM-Titus sidebar version badges for Anaconda installer.

Creates 160x64 PNG badges with:
  - 'DWM-Titus' in 20pt NotoSans-Bold (rgba(235, 235, 240, 240))
  - 'v<version>' in 16pt NotoSans-Regular (rgba(235, 235, 240, 240))
"""

import argparse
import os
from PIL import Image, ImageDraw, ImageFont

FONT_BOLD = '/usr/share/fonts/noto/NotoSans-Bold.ttf'
FONT_REGULAR = '/usr/share/fonts/noto/NotoSans-Regular.ttf'
DEFAULT_FILL = (235, 235, 240, 240)
WIDTH, HEIGHT = 160, 64


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

    font_main = ImageFont.truetype(FONT_BOLD, 20)
    font_sub = ImageFont.truetype(FONT_REGULAR, 16)

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
    parser.add_argument('--version', help='Generate logo for specific version (e.g. 0.7.0)')
    parser.add_argument('--output', help='Output PNG path')
    parser.add_argument('--series', action='store_true', help='Generate full series from 0.7.0 to 0.10.0')
    parser.add_argument('--out-dir', default='branding/sidebar-logos', help='Output directory for series')
    args = parser.parse_args()

    if args.series:
        generate_series(args.out_dir)
    elif args.version:
        img = render_logo(args.version)
        out = args.output or f'sidebar-logo-v{args.version.lstrip("v")}.png'
        img.save(out, 'PNG')
        print(f'Saved {out}')
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
