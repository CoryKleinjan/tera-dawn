"""Sprites keep the smooth edge of the painting (Cory, 2026-10-11): cut with on/off alpha, the
dark outline round them shows as a stair-stepped, pixelated line in the game."""
import glob
import os
import sys
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import slice_sheets  # noqa: E402

ROOT = slice_sheets.ROOT
# folders cut at double detail with smooth edges (TDStage.ART_DENSITY lists them for the game)
SMOOTH = ["npcs", "monsters", "pets", "items", "skills"]


class SmoothEdgeTest(unittest.TestCase):
    def test_sprites_have_soft_edges(self):
        hard = []
        for folder in SMOOTH:
            for path in glob.glob(os.path.join(ROOT, "assets", "sprites", folder, "*.png")):
                a = np.asarray(Image.open(path).convert("RGBA"))[..., 3]
                solid = a == 255
                rim = solid & slice_sheets.dilate(a == 0, 1, outside=True)  # solid pixels touching clear ones
                if rim.sum() > 0.5 * ((a > 0) & (a < 255)).sum():  # most of the edge isn't faded
                    hard.append(os.path.relpath(path, ROOT))
        self.assertEqual(hard, [], "these sprites have on/off edges; re-cut them with slice_sheets.py")

    def test_cells_are_cut_smooth_at_double_detail_by_default(self):
        self.assertEqual(slice_sheets.DEFAULTS["alpha"], "smooth")
        self.assertEqual(slice_sheets.DEFAULTS["detail"], 2)

    def test_dilate_does_not_wrap_round_the_edges(self):
        m = np.zeros((5, 8), bool)
        m[2, 7] = True
        grown = slice_sheets.dilate(m, 1)
        self.assertTrue(grown[1:4, 6:8].all())
        self.assertFalse(grown[:, 0].any())


if __name__ == "__main__":
    unittest.main()
