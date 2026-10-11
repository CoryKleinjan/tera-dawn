"""climb_pieces.py: rope and ladder pieces lined up so they join in the game. Synthetic
pieces drawn in code, plus a check on the real cut pieces the game draws."""

import json
import os
import unittest

import numpy as np
from PIL import Image

import helpers

import climb_pieces as cp

ROOT = os.path.normpath(os.path.join(helpers.TOOLS, "..", ".."))


def piece(h, w, strands, rungs=(), rung_h=3, knot=None):
    """An RGBA piece h x w: vertical strands [(x0, x1), ...] the full height, horizontal rungs
    at the given rows between the outer strands, and an optional knot box (x0, y0, x1, y1)."""
    a = np.zeros((h, w, 4), np.uint8)
    for x0, x1 in strands:
        a[:, x0:x1] = (120, 80, 40, 255)
    for y in rungs:
        a[y:y + rung_h, strands[0][0]:strands[-1][1]] = (120, 80, 40, 255)
    if knot:
        x0, y0, x1, y1 = knot
        a[y0:y1, x0:x1] = (120, 80, 40, 255)
    return a


def strand_centre(a, rows):
    cols = (a[rows, :, 3] > 127).any(0)
    xs = np.nonzero(cols)[0]
    return (xs[0] + xs[-1] + 1) / 2


class LineUp(unittest.TestCase):
    def test_rope_end_with_knot_to_one_side_is_put_on_the_line(self):
        middle = piece(30, 10, [(3, 7)])
        # the rope enters the bottom piece at x 4-8 of 24 (well left of centre), knot below
        bottom = piece(30, 24, [(4, 8)], knot=(2, 20, 22, 28))
        _, m, b = cp.line_up(None, middle, bottom)
        self.assertEqual(strand_centre(m, slice(0, 4)), m.shape[1] / 2)
        self.assertEqual(strand_centre(b, slice(0, 4)), b.shape[1] / 2)

    def test_leaning_middle_is_straightened_to_join_itself(self):
        a = np.zeros((40, 30, 4), np.uint8)
        for y in range(40):  # a strand drifting 6 pixels right from top to bottom
            x = 10 + round(6 * y / 39)
            a[y, x:x + 4] = (40, 140, 40, 255)
        _, m, _ = cp.line_up(None, a, None)
        self.assertEqual(strand_centre(m, slice(0, 1)), strand_centre(m, slice(-1, None)))
        self.assertEqual(strand_centre(m, slice(0, 1)), m.shape[1] / 2)

    def test_ladder_end_drops_rows_so_rungs_keep_their_spacing(self):
        rails = [(0, 3), (17, 20)]
        middle = piece(20, 20, rails, rungs=(8,))           # one rung every 20 rows
        bottom = piece(30, 20, rails, rungs=(2, 14))        # first rung too close to the top
        _, m, b = cp.line_up(None, middle, bottom)
        rung_rows = np.nonzero((b[..., 3] > 127).all(1))[0]
        # the bottom piece now starts as a middle would: its first rung 8 rows down
        self.assertEqual(rung_rows[0], 8)

    def test_ladder_top_ends_like_a_middle_ends(self):
        rails = [(0, 3), (17, 20)]
        middle = piece(20, 20, rails, rungs=(8,))
        top = piece(30, 20, rails, rungs=(4, 24))  # last rung 3 rows above the bottom
        t, _, _ = cp.line_up(top, middle, None)
        rung_rows = np.nonzero((t[..., 3] > 127).all(1))[0]
        # a middle ends 9 rows below its rung (rows 8-10 are the rung, 11-19 rails)
        self.assertEqual(len(t) - 1 - rung_rows[-1], 9)

    def test_rope_joins_the_rope_not_a_post_of_the_same_width_beside_it(self):
        middle = piece(30, 10, [(3, 7)])
        middle[..., :3] = (210, 170, 110)                   # tan rope
        top = np.zeros((30, 30, 4), np.uint8)
        top[:, 2:6] = (110, 60, 30, 255)                    # brown post, as wide as the rope
        top[18:, 20:24] = (210, 170, 110, 255)              # tan rope tail off the knot
        t, _, _ = cp.line_up(top, middle, None)
        tail = t.copy()
        tail[tail[..., 0] < 150, 3] = 0                     # just the tan rope
        self.assertEqual(strand_centre(tail, slice(-4, None)), t.shape[1] / 2)

    def test_lined_up_pieces_stay_put_when_lined_up_again(self):
        middle = piece(30, 10, [(3, 7)])
        bottom = piece(30, 24, [(4, 8)], knot=(2, 20, 22, 28))
        once = cp.line_up(None, middle, bottom)
        twice = cp.line_up(*once)
        for a, b in zip(once[1:], twice[1:]):
            self.assertEqual(a.shape, b.shape)
            self.assertTrue((a == b).all())


class GamePieces(unittest.TestCase):
    """The pieces the game draws join: each end piece carries on from its middle piece on the
    same centre line (within a pixel), and each middle piece joins itself."""

    def test_cut_climb_pieces_join(self):
        with open(os.path.join(ROOT, "art", "sheets", "ropes_props_b.json")) as f:
            man = json.load(f)
        out_dir = os.path.join(ROOT, man["out_dir"])
        load = lambda n: np.array(Image.open(os.path.join(out_dir, n + ".png")).convert("RGBA"))
        for style, parts in man["climb"].items():
            with self.subTest(style=style):
                pics = [load(parts[k]) if k in parts else None for k in ("top", "middle", "bottom")]
                again = cp.line_up(*pics)
                for k, a, b in zip(("top", "middle", "bottom"), pics, again):
                    if a is None:
                        continue
                    self.assertLessEqual(abs(a.shape[1] - b.shape[1]), 2, f"{k} isn't centred on the rope (re-run the slicer)")
                    self.assertLessEqual(a.shape[0] - b.shape[0], 1, f"{k} doesn't carry on from the middle (re-run the slicer)")


if __name__ == "__main__":
    unittest.main()
