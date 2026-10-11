#!/usr/bin/env python3
"""Draws placeholder projectile sprites into assets/sprites/projectiles/ (arrows, stars,
bullets, magic bolts), pointing right. Real art replaces them; this never overwrites a file
that isn't a placeholder.

    python3 tools/art/make_projectile_placeholders.py [--force]
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, PngImagePlugin

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sprites", "projectiles")
TAG = "tera-dawn-placeholder"
INK = (43, 24, 58, 255)


def arrow(d, w, h):
    d.line([(2, h // 2), (w - 8, h // 2)], fill=(181, 138, 76, 255), width=2)
    d.polygon([(w - 9, h // 2 - 4), (w - 1, h // 2), (w - 9, h // 2 + 4)], fill=(200, 210, 225, 255), outline=INK)
    d.polygon([(0, h // 2 - 4), (6, h // 2), (0, h // 2 + 4), (3, h // 2)], fill=(240, 240, 250, 255))


def star(d, w, h):
    pts = []
    for i in range(8):
        r = 7.5 if i % 2 == 0 else 3
        a = math.pi * 2 * i / 8
        pts.append((w / 2 + r * math.cos(a), h / 2 + r * math.sin(a)))
    d.polygon(pts, fill=(200, 210, 225, 255), outline=INK)
    d.ellipse((w / 2 - 1.5, h / 2 - 1.5, w / 2 + 1.5, h / 2 + 1.5), fill=INK)


def bullet(d, w, h):
    d.rounded_rectangle((1, 1, w - 2, h - 2), radius=3, fill=(224, 182, 74, 255), outline=INK)


def orb(col):
    def draw(d, w, h):
        d.ellipse((2, 2, w - 3, h - 3), fill=col)
        d.ellipse((w / 2 - 3, h / 2 - 3, w / 2 + 3, h / 2 + 3), fill=(255, 255, 255, 255))
    return draw


def pebble(d, w, h):
    d.ellipse((1, 1, w - 2, h - 2), fill=(143, 179, 217, 255), outline=INK)


SPRITES = {
    "arrow": (32, 10, arrow, False),
    "star": (17, 17, star, False),
    "bullet": (10, 7, bullet, False),
    "energy_bolt": (22, 22, orb((150, 130, 255, 255)), True),
    "arcane_claw": (22, 22, orb((255, 120, 200, 255)), True),
    "pebble": (9, 9, pebble, False),
    # monster shots
    "mob_seed": (11, 11, orb((150, 110, 60, 255)), False),
    "mob_bolt": (18, 18, orb((180, 120, 255, 255)), True),
    "mob_ember": (18, 18, orb((255, 130, 60, 255)), True),
    "mob_bubble": (16, 16, orb((120, 220, 255, 255)), True),
    "mob_wisp": (16, 16, orb((255, 220, 110, 255)), True),
    "mob_shadow": (20, 20, orb((110, 80, 200, 255)), True),
}


def is_placeholder(path):
    try:
        return Image.open(path).info.get("generator") == TAG
    except OSError:
        return False


def main():
    force = "--force" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    for name, (w, h, fn, soft) in SPRITES.items():
        path = os.path.join(OUT, name + ".png")
        if os.path.exists(path) and not (force and is_placeholder(path)):
            continue
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        fn(ImageDraw.Draw(img), w, h)
        if soft:
            img = img.filter(ImageFilter.GaussianBlur(1.2))
        meta = PngImagePlugin.PngInfo()
        meta.add_text("generator", TAG)
        img.save(path, pnginfo=meta)
        print("wrote", name)


if __name__ == "__main__":
    main()
