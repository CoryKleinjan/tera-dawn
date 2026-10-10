"""paperdoll_layers' held hair: walking and running wear one drawn pose's hair through the
whole cycle, so it doesn't redraw itself every step."""

import unittest

import helpers  # noqa: F401  (puts the tools folder on the path)
import paperdoll_layers as pl


class HeldHair(unittest.TestCase):
    def test_every_frame_of_a_cycle_wears_one_pose(self):
        for style in pl.HAIRSTYLES:
            for cycle, (_, frames) in pl.HELD_HAIR.items():
                poses = {pl.held_hair_pose(style, n) for n in frames}
                self.assertEqual(len(poses), 1, f"{style} {cycle}: {poses}")
                self.assertIn(poses.pop(), frames, f"{style} {cycle} holds a pose of its own cycle")

    def test_a_style_can_hold_another_pose(self):
        self.assertEqual(pl.held_hair_pose("bun", "walk3"), "walk2")
        self.assertEqual(pl.held_hair_pose("tousled", "walk3"), "walk1")

    def test_other_poses_keep_their_own_hair(self):
        for n in ("idle1", "jump", "slash2", "rope1"):
            self.assertEqual(pl.held_hair_pose("long", n), n)


if __name__ == "__main__":
    unittest.main()
