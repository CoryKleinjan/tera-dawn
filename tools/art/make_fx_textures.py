#!/usr/bin/env python3
"""Generates the small procedural textures in assets/sprites/fx/: soft light dots
for particles and glows. Everything else in assets/sprites/ is cut from Cory's sheets by slice_sheets.py.

    python3 tools/art/make_fx_textures.py
"""
import math
import os

from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sprites", "fx")


def save(img, name):
    img.save(os.path.join(OUT, name))
    print("wrote", name, img.size)


def soft_dot(name, size, falloff=2.0):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / (size / 2)
            a = max(0.0, 1.0 - d) ** falloff
            img.putpixel((x, y), (255, 255, 255, int(a * 255)))
    save(img, name)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    soft_dot("soft_dot.png", 16)
    soft_dot("glow.png", 64, 1.6)
