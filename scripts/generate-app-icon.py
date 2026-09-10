#!/usr/bin/env python3
"""Generate the macOS AppIcon.iconset without third-party dependencies."""

from __future__ import annotations

import argparse
import binascii
import struct
import zlib
from pathlib import Path


def chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)
    )


def write_png(path: Path, width: int, height: int, pixels: bytes) -> None:
    stride = width * 4
    raw = b"".join(b"\x00" + pixels[y * stride : (y + 1) * stride] for y in range(height))
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def rounded_rect_contains(x: float, y: float, size: int, inset: float, radius: float) -> bool:
    left = inset
    right = size - inset
    top = inset
    bottom = size - inset

    if left + radius <= x <= right - radius and top <= y <= bottom:
        return True
    if top + radius <= y <= bottom - radius and left <= x <= right:
        return True

    cx = left + radius if x < left + radius else right - radius
    cy = top + radius if y < top + radius else bottom - radius
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius**2


def make_icon(size: int) -> bytes:
    pixels = bytearray(size * size * 4)
    inset = size * 0.055
    radius = size * 0.22

    for y in range(size):
        for x in range(size):
            px = x + 0.5
            py = y + 0.5
            offset = (y * size + x) * 4

            if not rounded_rect_contains(px, py, size, inset, radius):
                pixels[offset : offset + 4] = bytes((0, 0, 0, 0))
                continue

            t = y / max(size - 1, 1)
            r = int(25 + 19 * t)
            g = int(28 + 23 * t)
            b = int(39 + 37 * t)
            pixels[offset : offset + 4] = bytes((r, g, b, 255))

    # Three stacked runtime bars suggest selectable tool/version layers.
    bars = [
        (0.20, 0.26, 0.80, 0.36, (105, 178, 255, 255)),
        (0.20, 0.45, 0.68, 0.55, (124, 228, 176, 255)),
        (0.20, 0.64, 0.74, 0.74, (255, 197, 103, 255)),
    ]
    for x0, y0, x1, y1, color in bars:
        left = int(size * x0)
        right = int(size * x1)
        top = int(size * y0)
        bottom = int(size * y1)
        bar_radius = max(1, int(size * 0.03))
        for y in range(top, bottom):
            for x in range(left, right):
                if rounded_rect_contains(
                    x + 0.5 - left,
                    y + 0.5 - top,
                    max(right - left, bottom - top),
                    0,
                    bar_radius,
                ):
                    offset = (y * size + x) * 4
                    pixels[offset : offset + 4] = bytes(color)

    return bytes(pixels)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path, help="Destination AppIcon.iconset directory")
    args = parser.parse_args()

    output = args.output
    output.mkdir(parents=True, exist_ok=True)

    files = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    for filename, size in files.items():
        write_png(output / filename, size, size, make_icon(size))


if __name__ == "__main__":
    main()
