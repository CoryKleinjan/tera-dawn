"""Weapon holds (tools/art/paperdoll/weapons.py holds()): every kind sits in his front fist at
one angle to his forearm on every frame (Cory 2026-10-12: weapons keep their place in his hand
in every picture)."""
import unittest

import helpers  # noqa: F401  (puts the tools folder on the path)
from paperdoll.weapons import EMPTY_HANDED, WEAPON_KINDS, holds, thumb_side

ARM = {"idle1": [56, 82, 105], "walk2": [80, 77, 30], "hit": [62, 75, -5], "fall": [47, 55, -160],
       "run2": [34, 70, 170], "levelup": [51, 33, -100]}
NAMES = list(ARM) + ["rope1"]


class HoldsTest(unittest.TestCase):
    def test_every_kind_is_in_the_front_fist_at_one_angle_to_the_forearm(self):
        spec = {"sword": {"offset": -80}, "bow": {"offset": -5}, "claw": {}}
        out = holds(ARM, spec, NAMES)
        for kind in WEAPON_KINDS:
            sizes = set()
            for n in NAMES:
                h = out[kind][n]
                if n not in ARM or n in EMPTY_HANDED:
                    self.assertIsNone(h, f"{kind} on {n}")
                    continue
                self.assertEqual(h[:2], ARM[n][:2], f"{kind} in his fist on {n}")
                sizes.add(round(abs((h[2] - ARM[n][2] + 180) % 360 - 180), 1))
            self.assertEqual(len(sizes), 1, f"{kind} keeps one angle to his forearm: {sizes}")

    def test_the_weapon_stays_on_the_thumb_side_when_his_arm_swings_up_or_back(self):
        self.assertEqual(thumb_side(105, -80), 25)    # arm hanging: the blade forward
        self.assertEqual(thumb_side(-5, -80), -85)    # arm out in front: the blade up
        self.assertEqual(thumb_side(-160, -80), -80)  # arm up behind him: still up, not tip-down
        self.assertEqual(thumb_side(170, -80), -110)  # arm swung back: still up

    def test_a_kind_cannot_set_its_own_angle_per_frame(self):
        for bad in ({"frames": {"idle1": 20}}, {"angle": 5}, {"like": "sword"}, {"along": "forearm"}):
            with self.assertRaises(ValueError):
                holds(ARM, {"wand": bad}, NAMES)


if __name__ == "__main__":
    unittest.main()
