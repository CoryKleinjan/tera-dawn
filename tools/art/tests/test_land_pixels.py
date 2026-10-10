"""Land art at one pixel size: the slicer's art_px / grow scale, the platform piece joins in
platform_pieces.py, and land_pixels.py's audit of every place the game draws land art."""

import unittest

import numpy as np

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
