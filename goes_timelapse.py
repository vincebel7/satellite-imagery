#!/usr/bin/env python3
"""
Build a time-lapse GIF from GOES-19 L-band (HRIT) false-color images.

Walks every subfolder of ROOT (e.g. 2026-07-18_10-30-19), finds
abi_rgb_ABI_False_Color.png in each, and stitches them into a GIF
in chronological order (folder names sort by UTC timestamp).

Usage:
    python goes_timelapse.py /path/to/parent_folder
    python goes_timelapse.py /path/to/parent_folder -o earth.gif --width 1200 --fps 6

Requires: pip install pillow
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

TARGET = "abi_rgb_ABI_False_Color.png"


def find_frames(root: Path):
    """Return (label, path) for each subfolder that contains the target image."""
    frames = []
    for folder in sorted(p for p in root.iterdir() if p.is_dir()):
        # rglob in case the image sits in a nested subfolder
        matches = sorted(folder.rglob(TARGET))
        if matches:
            frames.append((folder.name, matches[0]))
        else:
            print(f"  skip: no {TARGET} in {folder.name}")
    return frames


def load_frame(path: Path, width: int, label: str | None):
    img = Image.open(path).convert("RGB")
    if width and img.width > width:
        h = round(img.height * width / img.width)
        img = img.resize((width, h), Image.LANCZOS)

    if label:
        draw = ImageDraw.Draw(img)
        size = max(14, img.width // 40)
        try:
            font = ImageFont.truetype("DejaVuSans.ttf", size)
        except OSError:
            try:
                font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", size)
            except OSError:
                font = ImageFont.load_default()
        # "2026-07-18_10-30-19" -> "2026-07-18 10:30:19 UTC"
        date, _, t = label.partition("_")
        text = f"{date} {t.replace('-', ':')} UTC" if t else label
        draw.text((10, 10), text, fill="white", font=font,
                  stroke_width=2, stroke_fill="black")

    # GIFs are limited to 256 colors; adaptive palette per frame looks best
    return img.quantize(colors=256, method=Image.Quantize.MEDIANCUT,
                        dither=Image.Dither.FLOYDSTEINBERG)


def main():
    ap = argparse.ArgumentParser(description="GOES-19 false-color time-lapse GIF")
    ap.add_argument("root", type=Path, help="Parent folder holding the timestamped folders")
    ap.add_argument("-o", "--output", type=Path, default=Path("goes19_timelapse.gif"))
    ap.add_argument("--width", type=int, default=1000,
                    help="Resize frames to this width (0 = full res; full disk is large)")
    ap.add_argument("--fps", type=float, default=5, help="Frames per second")
    ap.add_argument("--hold", type=int, default=1000,
                    help="Extra ms to pause on the last frame before looping")
    ap.add_argument("--no-label", action="store_true", help="Don't stamp the timestamp")
    args = ap.parse_args()

    if not args.root.is_dir():
        sys.exit(f"Not a directory: {args.root}")

    frames = find_frames(args.root)
    if not frames:
        sys.exit(f"No {TARGET} files found under {args.root}")
    print(f"Found {len(frames)} frames")

    images = []
    for label, path in frames:
        print(f"  {label}")
        images.append(load_frame(path, args.width, None if args.no_label else label))

    frame_ms = int(1000 / args.fps)
    durations = [frame_ms] * len(images)
    durations[-1] += args.hold

    images[0].save(
        args.output,
        save_all=True,
        append_images=images[1:],
        duration=durations,
        loop=0,          # loop forever
        optimize=True,
        disposal=2,
    )
    print(f"Saved {args.output} ({args.output.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
