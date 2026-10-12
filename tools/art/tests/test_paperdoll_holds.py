"""Weapon holds (tools/art/paperdoll/weapons.py holds()): every kind sits in his front fist at
one angle to his forearm on every frame (Cory 2026-10-12: weapons keep their place in his hand
in every picture)."""
import unittest

import helpers  # noqa: F401  (puts the tools folder on the path)
from paperdoll.weapons import APPROVED, EMPTY_HANDED, WEAPON_KINDS, grip_angle, holds

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

    def test_the_weapon_keeps_its_angle_and_turns_over_only_where_the_rig_mirrors_it(self):
        self.assertEqual(grip_angle(105, -85), 20)          # arm hanging: the staff's head forward
        self.assertEqual(grip_angle(-150, -85), 125)        # arm swung back: same angle to it
        self.assertEqual(grip_angle(-160, -85, True), -75)  # flung up behind his head: head up
        arm = dict(ARM, fall=[47, 55, -160, True])
        self.assertEqual(holds(arm, {"staff": {"offset": -85}}, NAMES)["staff"]["fall"], [47, 55, -75])

    def test_a_kind_cannot_set_its_own_angle_per_frame(self):
        for bad in ({"frames": {"idle1": 20}}, {"angle": 5}, {"like": "sword"}, {"along": "forearm"}):
            with self.assertRaises(ValueError):
                holds(ARM, {"wand": bad}, NAMES)

    def test_only_the_frames_cory_approved_leave_the_grip(self):
        arm = dict(ARM, sit=[88.5, 86.5, 20])
        out = holds(arm, {"bow": {"offset": -5, "approved": {"sit": 65}}}, NAMES + ["sit"])
        self.assertEqual(out["bow"]["sit"], [88.5, 86.5, 65])
        self.assertEqual(APPROVED, {"bow": {"sit"}})
        for bad in ({"bow": {"approved": {"idle1": 40}}}, {"sword": {"approved": {"sit": 65}}}):
            with self.assertRaises(ValueError):
                holds(arm, bad, NAMES + ["sit"])


if __name__ == "__main__":
    unittest.main()
