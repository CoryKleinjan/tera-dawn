"""paperdoll_layers' weapon maths (PR #53): Gemini draws swords, wands and staffs at a
slant, so their axis is measured and turned out before the rig angles are applied."""

import math
import unittest

import numpy as np

import helpers
import paperdoll_layers as pl


class DrawnAxis(unittest.TestCase):
    def test_a_flat_weapon_points_right(self):
        self.assertAlmostEqual(pl.drawn_axis(helpers.rod(0)), 0.0, delta=1.0)

    def test_an_upright_weapon_points_up(self):
        self.assertAlmostEqual(pl.drawn_axis(helpers.rod(90)), -90.0, delta=1.0)

    def test_a_slanted_weapon_is_taken_toward_the_right(self):
        # up and to the right, as the weapon sheets draw a sword
        self.assertAlmostEqual(pl.drawn_axis(helpers.rod(-45)), -45.0, delta=1.5)
        # the same line drawn the other way round is still read toward the right
        self.assertAlmostEqual(pl.drawn_axis(helpers.rod(135)), -45.0, delta=1.5)
        # an item drawn pointing right and dipping down keeps its tip on the right
        self.assertAlmostEqual(pl.drawn_axis(helpers.rod(45)), 45.0, delta=1.5)
        self.assertAlmostEqual(pl.drawn_axis(helpers.rod(-135)), 45.0, delta=1.5)


class Turning(unittest.TestCase):
    def test_turned_is_clockwise_on_screen(self):
        v = pl.turned([10, 0], 90)
        self.assertTrue(np.allclose(v, [0, 10]), "right turns to down (y grows downward)")
        self.assertTrue(np.allclose(pl.turned([10, 0], -90), [0, -10]))
        self.assertTrue(np.allclose(np.linalg.norm(pl.turned([3, 4], 33)), 5))

    def test_reach_along_the_axis(self):
        from PIL import Image
        img = Image.fromarray(helpers.rod(0, size=80, length=60))
        self.assertAlmostEqual(pl.reach(img, (40, 40), 0), 30, delta=1.5)
        self.assertAlmostEqual(pl.reach(img, (10, 40), 0), 60, delta=1.5)


class Length(unittest.TestCase):
    def test_a_slanted_sword_measures_its_true_length(self):
        piece = type("Piece", (), {})()
        piece.img = helpers.rod(-45, size=100, length=60)
        flat = type("Piece", (), {})()
        flat.img = helpers.rod(0, size=100, length=60)
        self.assertAlmostEqual(pl.length(piece, "sword"), pl.length(flat, "sword"), delta=3)
        # a kind not in AXIAL is measured across the picture as drawn
        self.assertAlmostEqual(pl.length(piece, "gun"), 60 * math.cos(math.radians(45)), delta=5)


if __name__ == "__main__":
    unittest.main()
