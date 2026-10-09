#!/usr/bin/env python3
"""Draws simple placeholder icons for every item in data/items/ that has no art yet, into
assets/sprites/items/<id>.png (64x64). Real icons cut from an item sheet by slice_sheets.py
replace them; this never overwrites an icon that isn't a placeholder.

    python3 tools/art/make_item_placeholders.py          # only missing icons
    python3 tools/art/make_item_placeholders.py --force  # redraw every placeholder
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "..", "assets", "sprites", "items")
S = 4  # supersampling
SIZE = 64
INK = (43, 24, 58, 255)
# Placeholders are tagged so a later run knows it may redraw them.
TAG = "tera-dawn-placeholder"

# id -> (shape, main colour)
ICONS = {
    "training_sword": ("sword", "b9b2a6"),
    "dawn_blade": ("sword", "ffd166"),
    "ember_cleaver": ("cleaver", "ff7a59"),
    "leaf_cap": ("cap", "7ccf6a"),
    "ember_helm": ("helm", "8a6f7d"),
    "linen_tunic": ("shirt", "e9dcc0"),
    "trail_pants": ("pants", "7d8fb3"),
    "leather_boots": ("boots", "a5714a"),
    "work_gloves": ("gloves", "c99a62"),
    "petal_cape": ("cape", "ff9ec4"),
    "dewdrop_earrings": ("earrings", "8fd8ff"),
    "sun_pendant": ("pendant", "ffcf4a"),
    "moss_ring": ("ring", "6fbf73"),
    "cinder_ring": ("ring", "ff6a3d"),
    "oak_shield": ("shield", "b07a45"),
    "red_potion": ("potion", "ff4f6a"),
    "orange_potion": ("potion", "ff9a3c"),
    "white_potion": ("potion", "f4f0ff"),
    "blue_potion": ("potion", "4f9dff"),
    "dewling_droplet": ("drop", "7fd3ff"),
    "moss_tuft": ("tuft", "6dbb5a"),
    "petal_wing": ("wing", "ffa7cf"),
    "sproutcap_cap": ("mushroom", "e8644f"),
    "pebble_core": ("stone", "9c8f86"),
    "cinder_horn": ("horn", "ff7a3d"),
    "boar_tusk": ("tusk", "f3e6c8"),
    "ashshell_fragment": ("shard", "8f8a99"),
    "chief_mane": ("flame", "ff7a2e"),
    "petal_nectar": ("potion", "ffc2e0"),
    "bronze_sword": ("sword", "d9925a"),
    "willow_bow": ("bow", "b58a4c"),
    "apprentice_wand": ("wand", "c9a7ff"),
    "iron_claw": ("claw", "a9b4c2"),
    "brass_knuckle": ("knuckle", "e0b64a"),
    "driftwood_pistol": ("gun", "8a6a4a"),
    "feather_arrow": ("arrow", "e9dcc0"),
    "iron_star": ("star", "a9b4c2"),
    "lead_bullet": ("bullet", "9c8f86"),
    "return_scroll": ("scroll", "ffe7a8"),
    "dawnrise_scroll": ("scroll", "ffd166"),
}


def rgb(h, k=1.0):
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    if k >= 1.0:
        return tuple(int(c + (255 - c) * (k - 1.0)) for c in (r, g, b)) + (255,)
    return tuple(int(c * k) for c in (r, g, b)) + (255,)


def pts(p):
    return [(x * S, y * S) for x, y in p]


class Pen:
    def __init__(self, d, col):
        self.d = d
        self.base = rgb(col)
        self.light = rgb(col, 1.45)
        self.dark = rgb(col, 0.62)

    def poly(self, p, fill=None):
        self.d.polygon(pts(p), fill=fill or self.base, outline=INK, width=int(2.5 * S))

    def ellipse(self, box, fill=None, width=2.5):
        x0, y0, x1, y1 = box
        self.d.ellipse((x0 * S, y0 * S, x1 * S, y1 * S), fill=fill or self.base, outline=INK, width=int(width * S))

    def line(self, p, fill, width):
        self.d.line(pts(p), fill=fill, width=int(width * S), joint="curve")


def sword(p):
    p.poly([(44, 8), (54, 10), (56, 20), (26, 46), (18, 38)], p.base)
    p.poly([(46, 12), (52, 13), (24, 41), (22, 39)], p.light)
    p.poly([(12, 38), (18, 32), (32, 46), (26, 52)], p.dark if p.base[0] > 200 else rgb("6b4a2b"))
    p.poly([(8, 50), (16, 42), (22, 48), (14, 56)], rgb("6b4a2b"))
    p.ellipse((5, 52, 12, 59), rgb("ffd166"))


def cleaver(p):
    p.poly([(26, 6), (54, 8), (56, 30), (34, 40), (24, 30)], p.base)
    p.poly([(30, 10), (50, 11), (50, 20), (32, 26)], p.light)
    p.poly([(26, 34), (32, 40), (14, 58), (8, 52)], rgb("4a3326"))


def cap(p):
    p.poly([(10, 40), (14, 24), (26, 14), (40, 14), (52, 26), (54, 40)], p.base)
    p.poly([(6, 40), (58, 40), (54, 48), (10, 48)], p.dark)
    p.poly([(20, 22), (30, 16), (36, 18), (26, 28)], p.light)
    p.line([(32, 14), (36, 6)], rgb("4f8a3d"), 3)


def helm(p):
    p.poly([(12, 50), (12, 26), (22, 12), (42, 12), (52, 26), (52, 50), (40, 50), (40, 36), (24, 36), (24, 50)], p.base)
    p.poly([(28, 8), (36, 8), (38, 30), (26, 30)], rgb("ff7a59"))
    p.poly([(16, 26), (22, 16), (26, 16), (20, 30)], p.light)


def shirt(p):
    p.poly([(20, 10), (26, 14), (38, 14), (44, 10), (58, 20), (52, 30), (46, 26), (46, 56), (18, 56), (18, 26), (12, 30), (6, 20)], p.base)
    p.poly([(26, 14), (32, 22), (38, 14)], p.dark)
    p.line([(32, 24), (32, 54)], p.dark, 2)


def pants(p):
    p.poly([(16, 8), (48, 8), (52, 56), (36, 56), (32, 26), (28, 56), (12, 56)], p.base)
    p.poly([(16, 8), (48, 8), (48, 14), (16, 14)], p.dark)
    p.poly([(18, 18), (24, 18), (20, 50), (16, 50)], p.light)


def boots(p):
    for dx in (0, 18):
        p.poly([(10 + dx, 12), (24 + dx, 12), (24 + dx, 44), (34 + dx, 46), (34 + dx, 54), (8 + dx, 54)], p.base)
        p.poly([(10 + dx, 12), (24 + dx, 12), (24 + dx, 18), (10 + dx, 18)], p.dark)


def gloves(p):
    p.poly([(14, 56), (14, 30), (10, 22), (14, 18), (20, 26), (20, 10), (26, 8), (28, 22), (30, 6), (36, 6), (36, 22), (40, 10), (46, 12), (44, 30), (44, 56)], p.base)
    p.poly([(14, 46), (44, 46), (44, 56), (14, 56)], p.dark)


def cape(p):
    p.poly([(22, 8), (42, 8), (54, 54), (32, 48), (10, 54)], p.base)
    p.poly([(22, 8), (42, 8), (40, 16), (24, 16)], p.dark)
    p.poly([(26, 18), (30, 18), (22, 46), (18, 46)], p.light)


def earrings(p):
    for cx in (20, 44):
        p.line([(cx, 8), (cx, 22)], rgb("ffd166"), 3)
        p.poly([(cx, 20), (cx + 9, 36), (cx, 50), (cx - 9, 36)], p.base)
        p.poly([(cx - 2, 28), (cx + 2, 28), (cx, 40)], p.light)


def pendant(p):
    p.line([(10, 6), (32, 28), (54, 6)], rgb("c9a14a"), 3)
    p.ellipse((18, 24, 46, 52))
    p.ellipse((25, 31, 39, 45), p.light, 1.5)


def ring(p):
    p.ellipse((12, 20, 52, 58), (0, 0, 0, 0), 9)
    p.d.ellipse((14 * S, 22 * S, 50 * S, 56 * S), outline=rgb("ffd166"), width=5 * S)
    p.poly([(32, 6), (42, 18), (32, 28), (22, 18)], p.base)
    p.poly([(30, 12), (34, 12), (32, 20)], p.light)


def shield(p):
    p.poly([(10, 10), (54, 10), (54, 30), (32, 58), (10, 30)], p.base)
    p.poly([(14, 14), (50, 14), (50, 18), (14, 18)], p.light)
    p.line([(32, 12), (32, 54)], rgb("8a8a96"), 4)
    p.line([(12, 28), (52, 28)], rgb("8a8a96"), 4)


def potion(p):
    p.ellipse((12, 22, 52, 60), rgb("e6f2ff"))
    p.ellipse((15, 32, 49, 58), p.base, 0)
    p.poly([(24, 8), (40, 8), (40, 24), (24, 24)], rgb("e6f2ff"))
    p.poly([(22, 4), (42, 4), (42, 10), (22, 10)], rgb("a5714a"))
    p.ellipse((20, 30, 28, 40), (255, 255, 255, 200), 0)


def drop(p):
    p.poly([(32, 6), (46, 30), (48, 40), (42, 52), (32, 56), (22, 52), (16, 40), (18, 30)], p.base)
    p.ellipse((22, 34, 30, 44), p.light, 0)


def tuft(p):
    p.ellipse((10, 26, 54, 56))
    for x in (18, 30, 42):
        p.ellipse((x - 9, 18, x + 9, 38), p.light if x == 30 else p.base)


def wing(p):
    p.poly([(8, 50), (16, 22), (34, 8), (56, 10), (48, 26), (54, 34), (40, 40), (42, 48)], p.base)
    p.line([(10, 48), (40, 18)], p.dark, 2)
    p.line([(10, 48), (44, 34)], p.dark, 2)


def mushroom(p):
    p.poly([(6, 40), (12, 22), (26, 10), (38, 10), (52, 22), (58, 40)], p.base)
    p.ellipse((18, 18, 28, 28), rgb("fff3e4"), 0)
    p.ellipse((36, 22, 44, 30), rgb("fff3e4"), 0)
    p.poly([(22, 40), (42, 40), (40, 56), (24, 56)], rgb("f3e6c8"))


def stone(p):
    p.poly([(14, 22), (28, 10), (48, 14), (56, 34), (46, 54), (20, 54), (8, 38)], p.base)
    p.poly([(20, 22), (28, 16), (36, 18), (24, 30)], p.light)
    p.ellipse((26, 30, 38, 42), rgb("ffb347"), 1.5)


def horn(p):
    p.poly([(14, 56), (22, 34), (34, 18), (50, 6), (44, 22), (36, 40), (30, 56)], p.base)
    p.poly([(44, 10), (50, 6), (46, 16)], rgb("ffd166"))


def tusk(p):
    p.poly([(10, 54), (14, 36), (26, 20), (44, 10), (56, 10), (40, 22), (28, 38), (22, 56)], p.base)
    p.poly([(10, 54), (22, 56), (20, 48), (12, 46)], p.dark)


def shard(p):
    p.poly([(12, 30), (30, 8), (54, 22), (48, 50), (22, 56)], p.base)
    p.line([(30, 8), (34, 32), (22, 56)], p.dark, 2)
    p.line([(34, 32), (54, 22)], p.dark, 2)


def flame(p):
    p.poly([(32, 4), (44, 20), (52, 36), (46, 54), (32, 60), (18, 54), (12, 36), (22, 24), (26, 32)], p.base)
    p.poly([(32, 24), (40, 38), (36, 52), (28, 52), (24, 40)], rgb("ffd166"))


def bow(p):
    p.line([(18, 6), (34, 14), (44, 32), (34, 50), (18, 58)], p.base, 6)
    p.line([(19, 7), (19, 57)], rgb("f3e6c8"), 1.5)
    p.poly([(26, 28), (30, 28), (30, 36), (26, 36)], rgb("6b4a2b"))


def wand(p):
    p.line([(12, 54), (40, 22)], rgb("8a5a35"), 5)
    p.ellipse((36, 8, 54, 26), p.base)
    p.ellipse((41, 12, 47, 18), p.light, 1)


def staff(p):
    p.line([(14, 58), (40, 14)], rgb("7a4f2e"), 6)
    p.poly([(36, 6), (50, 8), (52, 22), (40, 24), (34, 16)], p.base)
    p.ellipse((40, 11, 46, 17), p.light, 1)


def claw(p):
    p.poly([(14, 30), (40, 26), (44, 46), (18, 50)], rgb("6b4a2b"))
    for x in (20, 30, 40):
        p.poly([(x, 28), (x + 6, 26), (x + 12, 6), (x + 6, 8)], p.base)


def dagger(p):
    p.poly([(40, 6), (48, 10), (30, 38), (24, 34)], p.base)
    p.poly([(18, 34), (32, 44), (30, 48), (16, 38)], rgb("ffd166"))
    p.poly([(20, 42), (26, 46), (14, 58), (8, 54)], rgb("4a3326"))


def knuckle(p):
    p.poly([(12, 22), (52, 22), (54, 40), (10, 40)], p.base)
    for x in (16, 26, 36, 46):
        p.ellipse((x - 4, 14, x + 6, 26), p.light)
    p.poly([(18, 40), (46, 40), (40, 52), (24, 52)], p.dark)


def gun(p):
    p.poly([(8, 18), (54, 18), (54, 30), (8, 30)], p.base)
    p.poly([(14, 28), (28, 28), (24, 54), (10, 54)], rgb("6b4a2b"))
    p.poly([(48, 12), (54, 12), (54, 18), (48, 18)], p.dark)


def star(p):
    import math
    pts_ = []
    for i in range(8):
        r = 26 if i % 2 == 0 else 9
        a = math.pi / 4 * i
        pts_.append((32 + r * math.cos(a), 32 + r * math.sin(a)))
    p.poly(pts_, p.base)
    p.ellipse((28, 28, 36, 36), p.dark, 1.5)


def arrow(p):
    p.line([(10, 54), (46, 18)], rgb("c99a62"), 4)
    p.poly([(40, 12), (54, 8), (50, 22)], p.base)
    p.poly([(8, 46), (16, 52), (12, 58), (4, 50)], rgb("f3e6c8"))


def bullet(p):
    p.poly([(20, 20), (38, 20), (38, 50), (20, 50)], p.base)
    p.ellipse((20, 8, 38, 30), p.light)


def scroll(p):
    p.poly([(14, 14), (50, 14), (50, 50), (14, 50)], rgb("f3e6c8"))
    p.ellipse((8, 10, 20, 54), rgb("e0cfa6"))
    p.ellipse((44, 10, 56, 54), rgb("e0cfa6"))
    p.ellipse((26, 26, 38, 38), p.base)


def book(p):
    p.poly([(12, 10), (48, 8), (52, 52), (14, 56)], p.base)
    p.poly([(16, 12), (22, 12), (24, 52), (18, 54)], p.dark)
    p.ellipse((30, 24, 42, 36), p.light, 1.5)


def gem(p):
    p.poly([(32, 8), (52, 26), (32, 56), (12, 26)], p.base)
    p.poly([(32, 8), (40, 26), (32, 56), (24, 26)], p.light)


def key(p):
    p.ellipse((10, 10, 30, 30), p.base)
    p.line([(26, 26), (52, 52)], p.base, 6)
    p.line([(44, 44), (50, 38)], p.base, 5)


SHAPES = {f.__name__: f for f in [sword, cleaver, cap, helm, shirt, pants, boots, gloves, cape,
                                    earrings, pendant, ring, shield, potion, drop, tuft, wing,
                                    mushroom, stone, horn, tusk, shard, flame, bow, wand, staff,
                                    claw, dagger, knuckle, gun, star, arrow, bullet, scroll, book,
                                    gem, key]}


def is_placeholder(path):
    try:
        return Image.open(path).info.get("generator") == TAG
    except OSError:
        return False


def draw(item_id, shape, col):
    big = Image.new("RGBA", (SIZE * S, SIZE * S), (0, 0, 0, 0))
    SHAPES[shape](Pen(ImageDraw.Draw(big), col))
    img = big.resize((SIZE, SIZE), Image.LANCZOS)
    from PIL import PngImagePlugin
    meta = PngImagePlugin.PngInfo()
    meta.add_text("generator", TAG)
    img.save(os.path.join(OUT, item_id + ".png"), pnginfo=meta)
    print("wrote", item_id)


def main():
    force = "--force" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    for item_id, (shape, col) in ICONS.items():
        path = os.path.join(OUT, item_id + ".png")
        if os.path.exists(path) and not (force and is_placeholder(path)):
            continue
        draw(item_id, shape, col)


if __name__ == "__main__":
    main()
