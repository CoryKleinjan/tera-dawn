"""Every sprite the art tools wrote to assets/sprites: no magenta rim around the art. Unlike
the other art tool tests this reads the real game sprites, since what it guards is their
output: a cut that keeps the background's colour on its edge shows in the game as a thin
magenta line (see slice_sheets.defringe)."""

import glob
import os
import unittest

import numpy as np
from PIL import Image

import helpers  # noqa: F401  (puts the tools folder on the import path)

ROOT = os.path.normpath(os.path.join(helpers.TOOLS, "..", ".."))
SPRITES = os.path.join(ROOT, "assets", "sprites")
# Share of a sprite's edge pixels that may be magenta with no pink or purple art beside them
# (dark plum outlines and purple art that reaches the edge stay well under it; a fringed cut
# runs from about 20% to over half).
MAX_SHARE = 0.15
MIN_PIXELS = 30  # a few odd pixels on a small sprite aren't a line


def _shifted(m, dy, dx):
    out = np.zeros_like(m)
    h, w = m.shape
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = \
        m[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def magenta_rim(px):
    """(magenta rim pixels, edge pixels) of an RGBA array: solid pixels next to a clear one that
    lean magenta, with no pinkish art within two pixels inside to explain them."""
    px = px.astype(int)
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    solid = px[..., 3] > 127
    lean = np.minimum(r, b) - g
    near_clear = ~solid
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        near_clear = near_clear | _shifted(~solid, dy, dx)
    edge = solid & near_clear
    pink_art = solid & ~edge & (lean > 20)
    beside = np.zeros_like(solid)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            beside |= _shifted(pink_art, dy, dx)
    rim = edge & (lean > 40) & (np.abs(r - b) < 80) & ~beside
    return int(rim.sum()), int(edge.sum())


class SpriteEdges(unittest.TestCase):
    def test_the_rim_check_finds_a_magenta_rim(self):
        px = np.zeros((12, 12, 4), np.uint8)
        px[2:10, 2:10] = (200, 160, 90, 255)
        px[2:10, 2] = px[2:10, 9] = px[2, 2:10] = px[9, 2:10] = (110, 20, 95, 255)
        rim, edge = magenta_rim(px)
        self.assertEqual(rim, edge)
        px[2:10, 2] = px[2:10, 9] = px[2, 2:10] = px[9, 2:10] = (30, 20, 25, 255)
        self.assertEqual(magenta_rim(px)[0], 0)

    def test_no_sprite_has_a_magenta_rim(self):
        bad = []
        for path in sorted(glob.glob(os.path.join(SPRITES, "**", "*.png"), recursive=True)):
            with Image.open(path) as im:
                px = np.asarray(im.convert("RGBA"))
            rim, edge = magenta_rim(px)
            if rim >= MIN_PIXELS and rim > MAX_SHARE * edge:
                bad.append("%s: %d of %d edge pixels" % (os.path.relpath(path, ROOT), rim, edge))
        self.assertFalse(bad, "magenta rim (re-cut with tools/art/slice_sheets.py):\n" + "\n".join(bad))


if __name__ == "__main__":
    unittest.main()
