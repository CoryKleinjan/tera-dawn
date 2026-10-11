"""grip_guide.measure: the grip-hands edit's rods tell where the fist is (the gap the fingers
make in the rod) and which way the blade points (the rod's long end)."""

import unittest

import numpy as np
from PIL import Image, ImageDraw

import grip_guide as gg


def rod(pommel, gap_start, gap_end, tip):
    im = Image.new("L", (200, 200))
    draw = ImageDraw.Draw(im)
    draw.line([pommel, gap_start], fill=255, width=5)
    draw.line([gap_end, tip], fill=255, width=5)
    return np.asarray(im) > 0


class Measure(unittest.TestCase):
    def test_the_grip_is_in_the_gap_and_the_blade_up_the_long_end(self):
        (x, y), angle = gg.measure(rod((50, 150), (70, 130), (85, 115), (150, 50)))
        self.assertAlmostEqual(x, 77.5, delta=2)
        self.assertAlmostEqual(y, 122.5, delta=2)
        self.assertAlmostEqual(angle, -45, delta=2)

    def test_the_long_end_decides_the_blade_whichever_way_it_was_drawn(self):
        _, angle = gg.measure(rod((150, 100), (135, 100), (120, 100), (40, 100)))
        self.assertAlmostEqual(abs(angle), 180, delta=2)

    def test_a_rod_with_no_fist_in_it_is_not_read(self):
        self.assertIsNone(gg.measure(rod((40, 100), (100, 100), (101, 100), (160, 100))))


if __name__ == "__main__":
    unittest.main()
