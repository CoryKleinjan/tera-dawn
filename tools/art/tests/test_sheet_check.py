"""sheet_check: grading a Gemini sheet before it goes near the game (grid, empty cells,
frame sizes, magenta left in the art, a colour that must or mustn't be in cells)."""

import os
import tempfile
import unittest

import numpy as np
from PIL import Image

import helpers
import sheet_check as sc


def statuses(result):
    return {c["check"]: c["status"] for c in result["checks"]}


class Cells(unittest.TestCase):
    def test_even_cells_cover_the_sheet_row_by_row(self):
        cells = sc.even_cells((100, 90, 3), 2, 3)
        self.assertEqual(len(cells), 6)
        self.assertEqual(cells[0], (0, 50, 0, 30))
        self.assertEqual(cells[2], (0, 50, 60, 90))
        self.assertEqual(cells[3], (50, 100, 0, 30))

    def test_divider_count_and_grid_counts(self):
        rgb = helpers.sheet(4, 8)
        bg = np.array(helpers.MAGENTA)
        self.assertEqual(sc.divider_count(rgb, bg, 0), 4)
        self.assertEqual(sc.divider_count(rgb, bg, 1), 8)
        self.assertIn((4, (8,)), sc.grid_counts(rgb, bg))

    def test_summary_takes_the_worst_status(self):
        self.assertEqual(sc.summarise("x", [{"status": "pass"}, {"status": "warn"}])["status"], "warn")
        self.assertEqual(sc.summarise("x", [{"status": "warn"}, {"status": "fail"}])["status"], "fail")
        self.assertEqual(sc.summarise("x", [])["status"], "pass")


class FlatBottom(unittest.TestCase):
    def test_a_box_standing_flat_passes(self):
        mask = np.zeros((100, 100), bool)
        mask[20:90, 30:70] = True
        self.assertTrue(sc.flat_bottom(mask))

    def test_a_table_on_two_legs_passes(self):
        mask = np.zeros((100, 100), bool)
        mask[20:40, 20:80] = True
        mask[40:90, 22:28] = mask[40:90, 72:78] = True
        self.assertTrue(sc.flat_bottom(mask))

    def test_a_3_4_base_with_a_slanted_bottom_warns(self):
        mask = np.zeros((100, 100), bool)
        mask[20:80, 30:70] = True
        for y in range(80, 90):  # the base's bottom edge runs off at an angle
            mask[y, 30 + (y - 80) * 4:70] = True
        self.assertFalse(sc.flat_bottom(mask))


class Check(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.dir.cleanup()

    def _save(self, rgb, name="sheet.png"):
        path = os.path.join(self.dir.name, name)
        Image.fromarray(rgb.astype(np.uint8)).save(path)
        return path

    def test_a_good_sheet_passes(self):
        result = sc.check(self._save(helpers.sheet(2, 4)), cells=[2, 4], kind="anim")
        self.assertEqual(result["status"], "pass", result)

    def test_a_grey_background_fails(self):
        rgb = helpers.sheet(2, 2)
        rgb[(rgb == helpers.MAGENTA).all(2)] = (128, 128, 128)
        self.assertEqual(statuses(sc.check(self._save(rgb), cells=[2, 2]))["background"], "fail")

    def test_a_scene_without_cells_only_warns_about_its_background(self):
        rgb = np.full((60, 80, 3), (90, 160, 220))
        result = sc.check(self._save(rgb))
        self.assertEqual(result["status"], "warn")
        self.assertEqual(list(statuses(result)), ["background"])

    def test_stands_flags_a_slanted_bottom(self):
        rgb = np.full((100, 100, 3), helpers.MAGENTA)
        for y in range(20, 90):
            rgb[y, 30 + max(0, y - 80) * 4:70] = (120, 80, 40)
        result = statuses(sc.check(self._save(rgb), stands=True))
        self.assertEqual(result["flat bottom"], "warn")
        self.assertNotIn("flat bottom", statuses(sc.check(self._save(rgb))))

    def test_the_wrong_grid_warns(self):
        result = statuses(sc.check(self._save(helpers.sheet(2, 3)), cells=[2, 4]))
        self.assertEqual(result["grid"], "warn")

    def test_empty_cells_are_named(self):
        result = sc.check(self._save(helpers.sheet(2, 4, skip=(3, 6))), cells=[2, 4])
        empty = [c for c in result["checks"] if c["check"] == "empty cells"][0]
        self.assertEqual(empty["status"], "warn")
        self.assertEqual(empty["detail"], "cells 3, 6")

    def test_an_odd_sized_frame_fails_an_animation(self):
        rgb = helpers.sheet(1, 4, cell=80)
        rgb[40:72, 8:72] = (40, 120, 200)  # frame 1 much bigger than the rest
        result = statuses(sc.check(self._save(rgb), cells=[1, 4], kind="anim"))
        self.assertEqual(result["frame sizes"], "fail")

    def test_magenta_painted_on_the_art_fails(self):
        rgb = helpers.sheet(1, 2, cell=80, sprite_size=30)
        for x0 in (30, 110):
            rgb[50:60, x0:x0 + 20] = (230, 50, 220)  # pink-purple paint inside each sprite
        result = statuses(sc.check(self._save(rgb), cells=[1, 2]))
        self.assertEqual(result["magenta in sprites"], "fail")

    def test_gaps_in_the_art_dont_count_as_magenta(self):
        rgb = helpers.sheet(1, 2, cell=80, sprite_size=30)
        for x0 in (30, 110):
            rgb[50:60, x0:x0 + 20] = helpers.MAGENTA  # a hole showing the background
        result = statuses(sc.check(self._save(rgb), cells=[1, 2]))
        self.assertEqual(result["magenta in sprites"], "pass")

    def test_a_tinted_cell_background_doesnt_count_as_magenta(self):
        rgb = helpers.sheet(1, 3, cell=80, sprite_size=30)
        cell = rgb[2:78, 162:238]
        cell[(cell == helpers.MAGENTA).all(2)] = (225, 40, 225)  # Gemini tinted this cell
        result = statuses(sc.check(self._save(rgb), cells=[1, 3]))
        self.assertEqual(result["magenta in sprites"], "pass")

    def test_must_have_finds_missing_and_extra_colour(self):
        rgb = helpers.sheet(1, 3)
        green = (0, 200, 0)
        rgb[40:44, 10:20] = green  # cell 1 has the green rod
        rgb[40:44, 140:150] = green  # cell 3 has it too, but shouldn't
        must = {"rgb": list(green), "in": [1, 2], "not_in": [3]}
        result = sc.check(self._save(rgb), cells=[1, 3], must_have=must)
        row = [c for c in result["checks"] if c["check"] == "must have"][0]
        self.assertEqual(row["status"], "fail")
        self.assertIn("missing in cells 2", row["detail"])
        self.assertIn("should not be in cells 3", row["detail"])


if __name__ == "__main__":
    unittest.main()
