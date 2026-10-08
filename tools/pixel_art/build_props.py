#!/usr/bin/env python3
"""Build the tree, bush and rock sprites from the hand-drawn grids in props.txt.

The grids use one set of letters (K outline, a-e light to dark, r-u bark) and
each map's palette below colours them, so the meadow and Ember Hollow share the
same drawings. Trees are drawn at about half the old placeholder size, with the
thick outlines and cel shading of the characters; stage.gd scales them up.

Run from anywhere: python3 tools/pixel_art/build_props.py
"""
import os

from PIL import Image

from render import grid_img, load_all

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "sprites")
GRIDS = load_all(os.path.join(HERE, "props.txt"))

BARK = {"r": "c88a58", "s": "9a6440", "t": "6e4228", "u": "4a2c1c"}
LEAF = {"K": "142018", "a": "d8ff9c", "b": "96e46a", "c": "62c052", "d": "3e9445", "e": "2a6a3a"}
BLOSSOM = {"K": "4a1e34", "a": "fff4f8", "b": "ffb0cc", "c": "ee80aa", "d": "c45482", "e": "8a3058"}
EMBER_LEAF = {"K": "2a1018", "a": "ffb07a", "b": "e0705a", "c": "b0483e", "d": "8a3036", "e": "5c1e2a"}
EMBER_BARK = {"K": "1e1016", "r": "7a4a56", "s": "5a3440", "t": "42242e", "u": "2a141e"}
STONE = {"K": "2c2440", "a": "eee8f6", "b": "c4b8da", "c": "9a8cb8", "d": "6e6092", "e": "4a3e6a"}
EMBER_STONE = {"K": "1a0e16", "a": "9a6a76", "b": "7a5466", "c": "5a3a4c", "d": "42283a", "e": "2a1828"}


def img(name, *pals, rows=None):
    pal = {".": None}
    for p in pals:
        pal.update(p)
    return grid_img(rows or GRIDS[name], pal)


def save(im, name):
    im.save(os.path.join(OUT, name))
    print("wrote", name, im.size)


def tree(leaf, name):
    crown = img("crown", leaf)
    rows = GRIDS["trunk"]
    trunk = img(None, {"K": leaf["K"]}, BARK, rows=rows[:4] + rows[4:20] + rows[4:])
    w, h = crown.width, crown.height - 14 + trunk.height
    f = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    f.alpha_composite(trunk, (w // 2 - 14, h - trunk.height))
    f.alpha_composite(crown, (0, 0))
    save(f, name)


def main():
    tree(LEAF, "tree_dawn.png")
    tree(BLOSSOM, "tree_dawn_pink.png")
    dead = GRIDS["deadtree"]
    save(img(None, EMBER_BARK, rows=dead[:24] + dead[24:37] * 3 + dead[37:]), "tree_ember.png")  # a taller trunk
    save(img("bush", LEAF), "bush_dawn.png")
    save(img("bush", EMBER_LEAF), "bush_ember.png")
    save(img("rock", STONE), "rock_dawn.png")
    save(img("rock", EMBER_STONE), "rock_ember.png")


if __name__ == "__main__":
    main()
