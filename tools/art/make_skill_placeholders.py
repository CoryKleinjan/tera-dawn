#!/usr/bin/env python3
"""Draws placeholder skill icons into assets/sprites/skills/<id>.png (64x64): a rounded
gem-like badge in the skill's colour with a symbol from make_item_placeholders' shapes, plus
a few skill-only symbols. Real icons replace them; this never overwrites one that isn't a
placeholder.

    python3 tools/art/make_skill_placeholders.py          # only missing icons
    python3 tools/art/make_skill_placeholders.py --force  # redraw every placeholder
"""
import os
import sys

from PIL import Image, ImageDraw, PngImagePlugin

sys.path.insert(0, os.path.dirname(__file__))
import make_item_placeholders as items  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sprites", "skills")
S, SIZE, INK, TAG = items.S, items.SIZE, items.INK, items.TAG


def burst(p):
    pts = []
    import math
    for i in range(16):
        r = 24 if i % 2 == 0 else 11
        a = math.pi * 2 * i / 16
        pts.append((32 + r * math.cos(a), 32 + r * math.sin(a)))
    p.poly(pts, p.light)


def heart(p):
    p.ellipse((12, 14, 34, 36), p.light)
    p.ellipse((30, 14, 52, 36), p.light)
    p.poly([(14, 30), (50, 30), (32, 54)], p.light)


def boot(p):
    p.poly([(22, 10), (36, 10), (36, 38), (52, 42), (52, 52), (20, 52)], p.light)


def fist(p):
    p.poly([(16, 20), (46, 18), (50, 44), (20, 48)], p.light)
    for x in (20, 28, 36):
        p.line([(x + 4, 20), (x + 4, 30)], INK, 2)


def bolt(p):
    p.poly([(36, 6), (16, 36), (30, 36), (24, 58), (48, 26), (34, 26)], p.light)


def arrows(p):
    p.line([(12, 52), (50, 14)], p.light, 5)
    p.poly([(52, 10), (52, 24), (40, 14)], p.light)
    p.line([(20, 56), (54, 24)], p.light, 4)


def swirl(p):
    p.ellipse((14, 14, 50, 50), None, 3)
    p.ellipse((22, 22, 42, 42), p.light, 2.5)


def eye(p):
    p.poly([(8, 32), (32, 16), (56, 32), (32, 48)], p.light)
    p.ellipse((24, 24, 40, 40), INK)


SHAPES = dict(items.SHAPES)
SHAPES.update({f.__name__: f for f in [burst, heart, boot, fist, bolt, arrows, swirl, eye]})

# id -> (symbol, badge colour)
ICONS = {
    "pebble_toss": ("stone", "8fb3d9"),
    "second_wind": ("heart", "ff8fa3"),
    "quick_step": ("boot", "7fdc9a"),
    "power_strike": ("burst", "ff9a3c"),
    "iron_body": ("shield", "a9b4c2"),
    "toughness": ("heart", "e0574f"),
    "bow_shot": ("arrow", "c9a46a"),
    "star_throw": ("star", "a9b4c2"),
    "gun_shot": ("bullet", "e0b64a"),
    "double_shot": ("arrows", "7fc46a"),
    "arrow_blow": ("arrow", "e8a33c"),
    "focus": ("eye", "6fb7e0"),
    "critical_shot": ("burst", "e05a4f"),
    "energy_bolt": ("bolt", "9f8cff"),
    "arcane_claw": ("swirl", "ff7ac8"),
    "magic_armor": ("shield", "8fa8ff"),
    "mp_boost": ("drop", "4f9dff"),
    "lucky_seven": ("star", "b98cff"),
    "star_scatter": ("burst", "8f6bd9"),
    "haste": ("boot", "c58cff"),
    "nimble_body": ("eye", "9a7bd0"),
    "somersault_kick": ("swirl", "4fb7d9"),
    "flash_fist": ("fist", "e0b64a"),
    "quick_draw": ("gun", "5aa6c9"),
    "bullet_time": ("bolt", "f2d06b"),
}


def draw(skill_id, shape, col):
    big = Image.new("RGBA", (SIZE * S, SIZE * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    pen = items.Pen(d, col)
    d.rounded_rectangle((3 * S, 3 * S, 61 * S, 61 * S), radius=12 * S, fill=pen.dark, outline=INK, width=3 * S)
    d.rounded_rectangle((8 * S, 8 * S, 56 * S, 56 * S), radius=9 * S, fill=pen.base)
    SHAPES[shape](pen)
    img = big.resize((SIZE, SIZE), Image.LANCZOS)
    meta = PngImagePlugin.PngInfo()
    meta.add_text("generator", TAG)
    img.save(os.path.join(OUT, skill_id + ".png"), pnginfo=meta)
    print("wrote", skill_id)


def main():
    force = "--force" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    for skill_id, (shape, col) in ICONS.items():
        path = os.path.join(OUT, skill_id + ".png")
        if os.path.exists(path) and not (force and items.is_placeholder(path)):
            continue
        draw(skill_id, shape, col)


if __name__ == "__main__":
    main()
