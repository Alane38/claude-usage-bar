#!/usr/bin/env python3
"""Génère app/ClaudeUsageBar.icns : jauge d'usage orange autour de l'étincelle de la barre de menu.
Dépendance : Pillow. Usage : python3 scripts/make_icon.py"""
import math
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SIZE = 2048  # dessin en 2x puis réduit : bords lisses
ACCENT = (232, 133, 95)
TRACK = (255, 255, 255, 36)
SPARK = [(8, 1), (9, 6), (13, 3), (10, 7), (15, 8), (10, 9), (13, 13), (9, 10),
         (8, 15), (7, 10), (3, 13), (6, 9), (1, 8), (6, 7), (3, 3), (7, 6)]


def background() -> Image.Image:
    gradient = Image.new("RGBA", (SIZE, SIZE))
    pixels = gradient.load()
    for y in range(SIZE):
        shade = int(44 - 28 * y / SIZE)
        for x in range(SIZE):
            pixels[x, y] = (shade, shade, shade + 3, 255)
    mask = Image.new("L", (SIZE, SIZE), 0)
    margin = int(SIZE * 0.05)
    ImageDraw.Draw(mask).rounded_rectangle(
        (margin, margin, SIZE - margin, SIZE - margin), radius=int(SIZE * 0.225), fill=255)
    gradient.putalpha(mask)
    return gradient


def arc_with_round_caps(draw: ImageDraw.ImageDraw, box, start, end, width, color):
    draw.arc(box, start, end, fill=color, width=width)
    center = SIZE / 2
    radius = (box[2] - box[0]) / 2 - width / 2
    for angle in (start, end):
        x = center + radius * math.cos(math.radians(angle))
        y = center + radius * math.sin(math.radians(angle))
        draw.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=color)


def draw_icon() -> Image.Image:
    icon = background()
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    ring_width = int(SIZE * 0.075)
    pad = int(SIZE * 0.215)
    box = (pad, pad, SIZE - pad, SIZE - pad)
    sweep_start, sweep_total = 135, 270
    arc_with_round_caps(draw, box, sweep_start, sweep_start + sweep_total, ring_width, TRACK)
    arc_with_round_caps(draw, box, sweep_start, sweep_start + sweep_total * 0.65, ring_width, ACCENT + (255,))

    scale = SIZE * 0.024
    points = [(SIZE / 2 + (x - 8) * scale, SIZE / 2 + (y - 8) * scale) for x, y in SPARK]
    draw.polygon(points, fill=ACCENT + (255,))

    icon.alpha_composite(layer)
    return icon


def write_icns(image: Image.Image, destination: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "icon.iconset"
        iconset.mkdir()
        for base in (16, 32, 128, 256, 512):
            for factor in (1, 2):
                pixels = base * factor
                name = f"icon_{base}x{base}{'@2x' if factor == 2 else ''}.png"
                image.resize((pixels, pixels), Image.LANCZOS).save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(destination)], check=True)


if __name__ == "__main__":
    final = draw_icon()
    write_icns(final, ROOT / "app" / "ClaudeUsageBar.icns")
    final.resize((512, 512), Image.LANCZOS).save(ROOT / "app" / "icon-preview.png")
    print("OK : app/ClaudeUsageBar.icns")
