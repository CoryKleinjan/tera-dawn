"""paperdoll_layers' held hair: each family of poses (at rest, on the move, climbing) wears
one drawn pose's hair, so it doesn't redraw itself or snap between shapes from frame to frame."""

import unittest

import numpy as np
from PIL import Image

import helpers  # noqa: F401  (puts the tools folder on the path)
import paperdoll_layers as pl


class HeldHair(unittest.TestCase):
    def test_every_frame_of_a_family_wears_one_pose(self):
        for style in pl.HAIRSTYLES:
            for family, (_, frames) in pl.HELD_HAIR.items():
                poses = {pl.held_hair_pose(style, n) for n in frames}
                self.assertEqual(len(poses), 1, f"{style} {family}: {poses}")
                self.assertIn(poses.pop(), frames, f"{style} {family} holds a pose of its own")

    def test_a_pose_is_in_one_family_at_most(self):
        seen = [n for _, frames in pl.HELD_HAIR.values() for n in frames]
        self.assertEqual(len(seen), len(set(seen)))

    def test_a_style_can_hold_another_pose(self):
        old = dict(pl.HELD_HAIR_STYLE)
        try:
            pl.HELD_HAIR_STYLE["bun"] = {"rest": "idle2"}
            self.assertEqual(pl.held_hair_pose("bun", "walk3"), "idle2")
            self.assertEqual(pl.held_hair_pose("tousled", "walk3"), "idle1")
        finally:
            pl.HELD_HAIR_STYLE.clear()
            pl.HELD_HAIR_STYLE.update(old)

    def test_lying_poses_keep_their_own_hair(self):
        for n in ("faint1", "faint2"):
            self.assertEqual(pl.held_hair_pose("long", n), n)


def disc(size, centre, radius, grey=120):
    yy, xx = np.mgrid[0:size, 0:size]
    arr = np.zeros((size, size, 4), np.uint8)
    on = np.hypot(xx - centre[0], yy - centre[1]) <= radius
    arr[on] = (grey, grey, grey, 255)
    return arr


class Tone(unittest.TestCase):
    def test_toned_moves_the_middle_grey(self):
        img = Image.fromarray(disc(40, (20, 20), 10, grey=200))
        self.assertAlmostEqual(pl.hair_grey(pl.toned(img, 100)), 100, delta=1)


class PulledIn(unittest.TestCase):
    FI = {"head": (50.0, 50.0), "r": 20.0}

    def test_a_tail_just_off_the_head_is_moved_to_touch_it(self):
        arr = disc(100, (78, 50), 4)  # 4 px (0.2 r) off the head's edge
        out = np.asarray(pl.pulled_in(Image.fromarray(arr), self.FI))[..., 3] > 0
        ys, xs = np.nonzero(out)
        self.assertEqual(out.sum(), (arr[..., 3] > 0).sum(), "the piece keeps its size")
        self.assertLessEqual(np.hypot(xs - 50, ys - 50).min(), 20.5)

    def test_hair_on_the_head_or_far_off_it_stays(self):
        arr = disc(100, (60, 50), 15)
        arr[disc(100, (5, 5), 3)[..., 3] > 0] = (120, 120, 120, 255)  # a speck far away
        out = np.asarray(pl.pulled_in(Image.fromarray(arr), self.FI))
        self.assertTrue((out == arr).all())


class Joined(unittest.TestCase):
    FI = {"head": (50.0, 50.0), "r": 20.0, "tilt": 0.0}

    def pieces(self, arr):
        return pl.ss.label(arr[..., 3] > 0)[1]

    def test_a_pigtail_drawn_apart_is_moved_to_touch_the_hair(self):
        arr = disc(100, (50, 50), 15)
        arr[disc(100, (72, 50), 4)[..., 3] > 0] = (120, 120, 120, 255)  # 3 px off the hair
        out = np.asarray(pl.joined(Image.fromarray(arr), self.FI))
        self.assertEqual(self.pieces(out), 1)

    def test_a_speck_or_a_far_bit_of_outline_goes(self):
        arr = disc(100, (50, 50), 15)
        arr[disc(100, (90, 90), 3)[..., 3] > 0] = (120, 120, 120, 255)  # far and small
        arr[2:5, 2:5] = (120, 120, 120, 255)  # a speck
        out = np.asarray(pl.joined(Image.fromarray(arr), self.FI))
        self.assertEqual(self.pieces(out), 1)
        self.assertEqual((out[..., 3] > 0).sum(), (disc(100, (50, 50), 15)[..., 3] > 0).sum())

    def test_a_moved_piece_stays_behind_the_face(self):
        arr = disc(100, (50, 50), 15)
        arr[disc(100, (75, 50), 4)[..., 3] > 0] = (120, 120, 120, 255)
        face = np.zeros((100, 100), bool)
        face[:, 64:] = True
        out = np.asarray(pl.joined(Image.fromarray(arr), self.FI, 0.8, face))
        self.assertFalse((out[..., 3] > 0)[face & ~(disc(100, (50, 50), 15)[..., 3] > 0)].any())


class AboveFringe(unittest.TestCase):
    def test_no_scalp_below_the_fringe(self):
        hair = np.zeros((10, 4), bool)
        hair[2:5, 1] = True  # a fringe ending on row 4 in column 1; no hair in column 3
        ok = pl.above_fringe(hair)
        self.assertTrue(ok[:5, 1].all())
        self.assertFalse(ok[5:, 1].any())
        self.assertFalse(ok[:, 3].any())


if __name__ == "__main__":
    unittest.main()
