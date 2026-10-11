"""slice_sheets: the image helpers every art tool shares (components, flood fill, grid
detection, magenta keying, colour conversion, seamless tiles)."""

import unittest

import numpy as np
from PIL import Image

import helpers
import slice_sheets as ss


class Components(unittest.TestCase):
    def test_label_counts_8_connected_pieces(self):
        m = np.zeros((10, 10), bool)
        m[1, 1] = m[2, 2] = True  # diagonal neighbours: one piece
        m[6:8, 6:8] = True
        lab, n = ss.label(m)
        self.assertEqual(n, 2)
        self.assertEqual(lab[1, 1], lab[2, 2])
        self.assertNotEqual(lab[1, 1], lab[6, 6])
        self.assertEqual(lab[0, 0], 0)

    def test_label_of_nothing(self):
        lab, n = ss.label(np.zeros((4, 4), bool))
        self.assertEqual(n, 0)
        self.assertFalse(lab.any())

    def test_flood_is_4_connected_from_the_seeds(self):
        m = np.zeros((5, 5), bool)
        m[0, 0:3] = True
        m[1, 3] = True  # only touches the row diagonally
        out = ss.flood(m, [(0, 0)])
        self.assertTrue(out[0, 0:3].all())
        self.assertFalse(out[1, 3])

    def test_flood_ignores_seeds_outside_the_mask(self):
        m = np.zeros((3, 3), bool)
        m[2, 2] = True
        self.assertFalse(ss.flood(m, [(0, 0)]).any())

    def test_dilate_grows_by_the_radius(self):
        m = np.zeros((9, 9), bool)
        m[4, 4] = True
        out = ss.dilate(m, 2)
        self.assertEqual(out.sum(), 25)
        self.assertTrue(out[2, 2] and out[6, 6])
        self.assertFalse(out[1, 4])


class Grid(unittest.TestCase):
    def test_background_is_the_most_common_colour(self):
        rgb = helpers.sheet(2, 2)
        bg = ss.background_color(rgb)
        self.assertLess(np.abs(bg - np.array(helpers.MAGENTA)).sum(), 12)

    def test_detect_grid_finds_rows_and_columns(self):
        rgb = helpers.sheet(3, 4)
        bands = ss.detect_grid(rgb, ss.background_color(rgb))
        self.assertEqual(len(bands), 3)
        self.assertEqual([len(cols) for _, _, cols in bands], [4, 4, 4])
        y0, y1, cols = bands[1]
        self.assertAlmostEqual(y0, 64, delta=2)
        self.assertAlmostEqual(y1, 128, delta=2)
        self.assertAlmostEqual(cols[2][0], 128, delta=2)

    def test_a_sheet_without_dividers_is_one_cell(self):
        rgb = np.zeros((100, 120, 3), np.int32)
        rgb[:] = helpers.MAGENTA
        bands = ss.detect_grid(rgb, ss.background_color(rgb))
        self.assertEqual(bands, [(0, 100, [(0, 120)])])

    def test_grid_from_manifest_shared_columns(self):
        bands = ss.grid_from_manifest({"rows": [0, 50, 100], "cols": [0, 40, 80]}, (100, 80, 3))
        self.assertEqual(bands, [(0, 50, [(0, 40), (40, 80)]), (50, 100, [(0, 40), (40, 80)])])

    def test_grid_from_manifest_columns_per_row(self):
        bands = ss.grid_from_manifest({"rows": [0, 50, 100], "cols": [[0, 80], [0, 40, 80]]}, (100, 80, 3))
        self.assertEqual(bands[0][2], [(0, 80)])
        self.assertEqual(bands[1][2], [(0, 40), (40, 80)])


class Keying(unittest.TestCase):
    def test_magenta_is_background_and_art_is_opaque(self):
        cell = np.zeros((2, 2, 3), float)
        cell[0, 0] = helpers.MAGENTA
        cell[0, 1] = (40, 120, 200)
        cell[1, 0] = (30, 30, 30)
        cell[1, 1] = (255, 0, 0)
        rgb, alpha = ss.key_magenta(cell, np.array(helpers.MAGENTA))
        self.assertAlmostEqual(alpha[0, 0], 0.0)
        self.assertAlmostEqual(alpha[0, 1], 1.0)
        self.assertAlmostEqual(alpha[1, 0], 1.0)
        self.assertAlmostEqual(alpha[1, 1], 1.0, msg="strong red is never background")
        self.assertTrue(np.allclose(rgb[0, 1], np.array((40, 120, 200)) / 255.0, atol=0.02))

    def test_key_dark_floods_the_background_from_the_border(self):
        cell = np.full((20, 20, 3), 10.0)
        cell[5:15, 5:15] = 200
        cell[9:11, 9:11] = 10  # a dark hole inside the sprite stays part of it
        _, alpha = ss.key_dark(cell, np.array([10, 10, 10]), shadow=False)
        self.assertEqual(alpha[0, 0], 0.0)
        self.assertEqual(alpha[7, 7], 1.0)
        self.assertEqual(alpha[10, 10], 1.0)

    def _outlined(self, fill):
        """A magenta cell with a filled square in a dark outline, and a ring of the outline
        blended a third into the magenta around it (how Gemini draws edges)."""
        cell = np.zeros((24, 24, 3), float)
        cell[:] = helpers.MAGENTA
        outline = np.array((40.0, 30.0, 25.0))
        cell[5:19, 5:19] = 0.65 * outline + 0.35 * np.array(helpers.MAGENTA)  # dark plum rim
        cell[6:18, 6:18] = outline
        cell[8:16, 8:16] = fill
        return cell

    def test_defringe_takes_the_magenta_out_of_a_dark_rim(self):
        bg = np.array(helpers.MAGENTA)
        rgb, alpha = ss.key_magenta(self._outlined((200, 160, 90)), bg)
        self.assertGreater(alpha[5, 12], 0.5, msg="the key alone keeps the dark magenta rim")
        rgb, alpha = ss.defringe(rgb, alpha, bg)
        rim = rgb[5, 12]
        self.assertLess(min(rim[0], rim[2]) - rim[1], 0.04, msg="the rim no longer leans magenta")
        self.assertAlmostEqual(alpha[5, 12], 0.65, delta=0.1, msg="it keeps the art's share as alpha")
        self.assertAlmostEqual(alpha[12, 12], 1.0)

    def test_defringe_keeps_purple_art(self):
        bg = np.array(helpers.MAGENTA)
        cell = np.zeros((24, 24, 3), float)
        cell[:] = helpers.MAGENTA
        cell[6:18, 6:18] = (150, 60, 170)  # a purple sprite up to the cut edge
        rgb, alpha = ss.key_magenta(cell, bg)
        out, out_alpha = ss.defringe(rgb, alpha, bg)
        self.assertTrue(np.allclose(out[6:18, 6:18], rgb[6:18, 6:18]))
        self.assertTrue(np.allclose(out_alpha, alpha))

    def test_defringe_drops_magenta_slivers_with_no_art_near(self):
        bg = np.array(helpers.MAGENTA)
        cell = np.zeros((24, 24, 3), float)
        cell[:] = helpers.MAGENTA
        cell[0] = (120, 30, 100)  # a divider line a crop caught
        rgb, alpha = ss.key_magenta(cell, bg)
        self.assertGreater(alpha[0, 12], 0.5)
        _, alpha = ss.defringe(rgb, alpha, bg)
        self.assertEqual(alpha[0, 12], 0.0)


class Colour(unittest.TestCase):
    def test_hsv_round_trip(self):
        rng = np.random.default_rng(1)
        rgb = rng.random((50, 3))
        back = ss.hsv_to_rgb(ss.rgb_to_hsv(rgb))
        self.assertTrue(np.allclose(back, rgb, atol=1e-6))

    def test_known_hues(self):
        hsv = ss.rgb_to_hsv(np.array([[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0], [0.5, 0.5, 0.5]]))
        self.assertTrue(np.allclose(hsv[:3, 0], [0, 1 / 3, 2 / 3]))
        self.assertEqual(hsv[3, 1], 0.0, "grey has no saturation")

    def test_leather_recolour_leaves_reds_greens_and_sky_blues_alone(self):
        rgb = np.array([[[0.9, 0.1, 0.1], [0.1, 0.8, 0.2], [0.2, 0.4, 0.9]]])
        self.assertTrue(np.allclose(ss.recolor_leather(rgb), rgb))

    def test_leather_recolour_leaves_deep_blues_alone(self):
        # pure and royal blue sit in the purple hue range, but have no more red than green
        rgb = np.array([[[0.0, 0.0, 1.0], [0.1, 0.2, 0.9]]])
        self.assertTrue(np.allclose(ss.recolor_leather(rgb), rgb))

    def test_leather_recolour_turns_purple_brown(self):
        out = ss.recolor_leather(np.array([[[0.5, 0.2, 0.6]]]))[0, 0]
        self.assertGreater(out[0], out[2], "more red than blue now")


class Resizing(unittest.TestCase):
    def test_shrink_keeps_colour_under_soft_edges(self):
        rgb = np.zeros((8, 8, 3))
        rgb[..., 1] = 1.0
        alpha = np.zeros((8, 8))
        alpha[:, :4] = 1.0
        out, a = ss.shrink(rgb, alpha, 0.25)
        self.assertEqual(a.shape, (2, 2))
        self.assertTrue(np.allclose(out[a > 0], [0, 1, 0], atol=0.01), "no dark fringe from the transparent side")

    def test_seamless_tile_wraps_without_a_seam(self):
        # a top-to-bottom ramp has a hard seam where its bottom meets its top when tiled
        ramp = np.repeat((np.arange(64) * 4)[:, None], 64, 1)
        img = Image.fromarray(np.stack([ramp] * 3, -1).astype(np.uint8))
        out = np.asarray(ss.make_seamless(img)).astype(int)
        self.assertEqual(out.shape, (64, 64, 3))
        self.assertGreater(abs(ramp[0, 0] - ramp[-1, 0]), 200, "the ramp's own seam")
        self.assertLessEqual(np.abs(out[0] - out[-1]).max(), 8, "the tile's top and bottom meet smoothly")
        self.assertLessEqual(np.abs(out[:, 0] - out[:, -1]).max(), 8, "and its sides")


class RoundTop(unittest.TestCase):
    def _button(self):
        """A disc a little taller than wide (as painted buttons come) on a 120-pixel cell: gold
        rim, dark middle, lit from the top."""
        yy, xx = np.mgrid[0:120, 0:120]
        d = np.hypot((yy - 60) * 50 / 52.0, xx - 60)
        alpha = np.clip(50.5 - d, 0, 1)
        rgb = np.zeros((120, 120, 3))
        rgb[d > 42] = [0.9, 0.7, 0.3]
        rgb[d <= 42] = [0.3, 0.2, 0.1]
        rgb[..., 0] += (120 - yy) / 600.0  # brighter towards the top
        return rgb, alpha

    def test_rebuilds_the_rim_a_label_hid(self):
        rgb, alpha = self._button()
        hid_rgb, hid_alpha = rgb.copy(), alpha.copy()
        hid_alpha[:20, :75] = 0  # the label box, past the middle
        hid_rgb[:20, :75] = 0
        out_rgb, out_alpha = ss.fix_round_top(hid_rgb, hid_alpha)
        self.assertLess(np.abs(out_alpha - alpha).max(), 0.3, "the round outline is back")
        hidden = alpha > 0.5
        hidden[20:] = False
        off = np.abs(out_rgb - rgb).max(2)[hidden]
        self.assertLess(off.mean(), 0.03, "rim and middle colours carry on, lit as the top is")
        self.assertTrue(out_alpha[9, 60] > 0.9 and out_alpha[12, 35] < 0.1, "the top is round, not flat")

    def test_clears_label_leftovers_beside_the_button(self):
        rgb, alpha = self._button()
        alpha[:20, :75] = 0
        alpha[2:5, 2:12] = 1  # a scrap of the label's box
        _, out = ss.fix_round_top(rgb, alpha)
        self.assertFalse((out[2:5, 2:12] > 0).any())


if __name__ == "__main__":
    unittest.main()
