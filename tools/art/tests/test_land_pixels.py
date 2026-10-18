"""Land art at one pixel size: the slicer's art_px / grow scale, the platform piece joins in
platform_pieces.py, and land_pixels.py's audit of every place the game draws land art."""

import os
import unittest

import numpy as np
from PIL import Image

import helpers  # noqa: F401  (puts the tools folder on the import path)
import land_pixels
import platform_pieces
import slice_sheets as ss


class ArtScale(unittest.TestCase):
    def opts(self, **kw):
        return dict(ss.DEFAULTS, **kw)

    def test_puts_density_texels_on_every_art_pixel(self):
        self.assertAlmostEqual(ss.art_scale(self.opts(art_px=4.0)), 0.5)
        self.assertAlmostEqual(ss.art_scale(self.opts(art_px=4.0, density=1)), 0.25)

    def test_grow_sizes_a_piece_within_bounds(self):
        self.assertAlmostEqual(ss.art_scale(self.opts(art_px=4.0, grow=1.2)), 0.6)
        with self.assertRaises(SystemExit):
            ss.art_scale(self.opts(art_px=4.0, grow=2.0))


class PlatformPieces(unittest.TestCase):
    def test_surface_is_the_first_half_solid_row(self):
        a = np.zeros((10, 8, 4), np.uint8)
        a[2, :2, 3] = 255  # a grass tip
        a[4:, :, 3] = 255
        self.assertEqual(platform_pieces.surface_row(a), 4)

    def test_thinning_keeps_the_top_and_the_bottom(self):
        a = np.zeros((100, 6, 4), np.uint8)
        a[..., 3] = 255
        a[:10, :, 0] = 200   # the surface
        a[-10:, :, 1] = 200  # the underside
        out = platform_pieces.join_bands(a, a, 40)
        self.assertEqual(out.shape[0], 40)
        self.assertTrue((out[:10, :, 0] == 200).all())
        self.assertTrue((out[-10:, :, 1] == 200).all())

    def test_pieces_keep_their_sheet_rows(self):
        tops = [np.zeros((10, 4, 4), np.uint8) for _ in platform_pieces.TOPS]
        sheet_y = {"cap_left": 12.4, "middle_a": 18.0, "middle_b": 20.0, "cap_right": 13.0}
        self.assertEqual(platform_pieces.offsets(tops, sheet_y, {}), [0, 6, 8, 1])
        self.assertEqual(platform_pieces.offsets(tops, sheet_y, {"cap_right": -2}), [1, 7, 9, 0])

    def test_a_terrace_end_goes_where_it_matches_its_cap(self):
        rng = np.random.default_rng(1)
        cap = rng.integers(0, 256, (40, 20, 4)).astype(np.uint8)
        cap[..., 3] = 255
        end = cap[5:]  # the same picture, cut 5 rows lower
        self.assertEqual(platform_pieces.best_row(end, cap, slice(10, 20), 30), 5)


def top_line(a, side, cols=12, run=7, deep=5):
    """Where the top edge is at a piece's left or right end: the median over `cols` columns of
    the first row solid `run` texels across and `deep` rows down (so grass blades, flowers and
    the thin caps of mushrooms standing on the ledge don't count)."""
    solid = a[..., 3] > 127
    wide = np.stack([np.convolve(r.astype(int), np.ones(run, int), "same") >= run for r in solid])
    for k in range(1, deep):
        wide[:-k] &= wide[k:]
    edge = wide[:, -cols - run // 2:-(run // 2)] if side == "right" else wide[:, run // 2:cols + run // 2]
    return float(np.median([np.nonzero(c)[0][0] for c in edge.T if c.any()]))


class CapJoins(unittest.TestCase):
    def test_every_biomes_caps_meet_its_middles(self):
        # a cap out of step with the middle beside it shows as a step in the platform's top edge
        root = os.path.join(platform_pieces.ROOT, "assets", "sprites", "platforms")
        for biome in sorted(os.listdir(root)):
            load = lambda n: np.asarray(Image.open(os.path.join(root, biome, n + ".png")).convert("RGBA"))
            left, a, b, right = [load(n) for n in platform_pieces.TOPS]
            for name, step in [("left cap", top_line(a, "left") - top_line(left, "right")),
                               ("right cap", top_line(right, "left") - top_line(b, "right"))]:
                with self.subTest(biome=biome, cap=name):
                    self.assertLessEqual(abs(step), MAX_CAP_STEP)


## Texels a cap's top edge may sit off the middle's (painted shapes differ a little; Dawnharbor's
## caps were 6-7 off before they kept their sheet rows).
MAX_CAP_STEP = 4.5


class Audit(unittest.TestCase):
    def test_every_use_of_land_art_shows_near_the_shared_pixel_size(self):
        rows = land_pixels.table()
        self.assertGreater(len(rows), 0)
        self.assertEqual(land_pixels.off(rows), [])

    def test_flags_a_use_outside_the_allowed_range(self):
        rows = [("a", "x.png", 1.0, 1.1), ("b", "y.png", 0.5, 0.6), ("c", "z.png", 1.0, 1.5)]
        self.assertEqual([r[0] for r in land_pixels.off(rows)], ["b", "c"])


if __name__ == "__main__":
    unittest.main()
