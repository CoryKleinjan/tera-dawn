"""town_kit: the fixed town canvases, the town cards and the locked Gemini entries they make,
plus sheet_check's town checks on synthetic results (no real art, no Gemini call)."""

import json
import os
import tempfile
import unittest
from unittest import mock

import numpy as np
from PIL import Image

import helpers  # noqa: F401  (puts the tools folder on the path)
import sheet_check as sc
import town_kit as tk


def full_card(town="mossvale", buildings=5, props=6):
    return {
        "id": town, "name": town.title(), "role": "the test town", "mood": "quiet", "light": "dusk",
        "palette": "greens", "materials": "moss stone", "texture": "rough stone",
        "signature": "mossy green stone under turf roofs",
        "buildings": [{"id": "b%d" % i, "name": "B%d" % i, "canvas": "building_wide", "look": "a hut"}
                      for i in range(buildings)],
        "approved_refs": [], "backdrop": "hills", "backdrop_bottom": "far fields",
        "lamp": "a stone lamp", "props": ["crate"] * props, "raised": None,
        "townsfolk": [{"label": "A", "look": "x"}] * 3 + [{"label": "KEEPER", "look": "x"}],
        "npc_refs": [], "rooms": {"store": "shelves", "hall": "banners"},
    }


OTHER = {"id": "emberforge", "name": "Emberforge", "signature": "dark basalt and glowing forges"}


class Canvases(unittest.TestCase):
    def test_every_building_canvas_has_the_same_door_on_the_bottom_centre(self):
        for name in tk.BUILDING_CANVASES:
            w, h = tk.CANVASES[name][:2]
            x0, y0, x1, y1 = tk.door_box(name)
            self.assertEqual((x1 - x0, y1 - y0), (tk.DOOR_W, tk.DOOR_H), name)
            self.assertLessEqual(abs((x0 + x1) / 2 - w / 2), 1, name)
            self.assertEqual(h - y1, tk.GROUND_MARGIN, name)

    def test_the_door_is_painted_on_the_canvas(self):
        rgb = np.asarray(tk.draw_canvas("building_wide"))
        x0, y0, x1, y1 = tk.door_box("building_wide")
        self.assertEqual(tuple(rgb[y1 - 5, (x0 + x1) // 2]), tk.DOOR_COLOUR)
        self.assertEqual(tuple(rgb[5, 5]), tk.MAGENTA)

    def test_the_canvases_in_the_repo_match_the_code(self):
        for name in tk.CANVASES:
            path = os.path.join(tk.CANVAS_DIR, name + ".png")
            self.assertTrue(os.path.exists(path), "run town_kit.py canvases (%s)" % name)
            self.assertTrue((np.asarray(Image.open(path).convert("RGB")) ==
                             np.asarray(tk.draw_canvas(name))).all(), name)


class Cards(unittest.TestCase):
    def test_a_full_card_has_no_problems(self):
        self.assertEqual(tk.card_problems(full_card()), [])

    def test_missing_keys_and_wrong_counts_are_named(self):
        card = full_card(buildings=3, props=5)
        del card["lamp"]
        self.assertTrue(any("lamp" in p for p in tk.card_problems(card)))
        del card["buildings"][0]
        card["lamp"] = "x"
        problems = " ".join(tk.card_problems(card))
        self.assertIn("5 or 6 buildings", problems)
        self.assertIn("6 or 12 props", problems)

    def test_the_cards_in_the_repo_load(self):
        cards = tk.all_cards()
        self.assertIn("dawnharbor", cards)
        for town, card in cards.items():
            self.assertEqual(card["id"], town)
            for key in tk.EXISTING_KEYS:
                self.assertTrue(card.get(key), "%s: %s" % (town, key))
            if not card.get("built_before_kit"):
                self.assertEqual(tk.card_problems(card), [], town)

    def test_the_banned_line_names_other_towns_not_its_own(self):
        card = full_card()
        line = tk.banned_line(card, {"mossvale": card, "emberforge": OTHER})
        self.assertIn("basalt", line)
        self.assertNotIn("mossy", line)


class Entries(unittest.TestCase):
    def setUp(self):
        self.card = full_card()
        self.cards = {"mossvale": self.card, "emberforge": OTHER}

    def test_a_full_kit(self):
        entries = tk.kit_entries(self.card, self.cards)
        ids = [e["id"] for e in entries]
        self.assertEqual(len(ids), len(set(ids)))
        buildings = [e for e in entries if e["town_check"]["kind"] == "building"]
        self.assertEqual(len(buildings), 5)
        for e in entries:
            self.assertTrue(e["edit"]["base"], e["id"])
            if e["town_check"]["kind"] != "cells" or "props" in e["id"]:  # townsfolk wear no materials
                self.assertIn("basalt", e["edit"]["text"], e["id"])  # the other towns' materials are banned
            self.assertTrue(e["town_check"], e["id"])
        for e in buildings:
            self.assertTrue(e["stands"])
            self.assertEqual(e["town_check"]["door"], tk.door_box("building_wide"))
            self.assertNotIn(tk.STYLE_REF, [r for r in e["edit"]["refs"] if "people" in r])
        backdrop = [e for e in entries if e["town_check"]["kind"] == "backdrop"][0]
        self.assertEqual(backdrop["edit"]["refs"], [])  # Gemini copies figures from refs into backdrops

    def test_the_pilot_is_the_first_building_and_the_backdrop(self):
        entries = tk.kit_entries(self.card, self.cards, pilot=True)
        self.assertEqual([e["town_check"]["kind"] for e in entries], ["building", "backdrop"])

    def test_an_unready_card_makes_no_entries(self):
        with self.assertRaises(ValueError):
            tk.kit_entries(full_card(buildings=2), self.cards)

    def test_writing_never_replaces_an_entry(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "pass.json")
            with open(path, "w") as f:
                json.dump({"sheets": [{"id": "mossvale_city_b0", "keep": True}]}, f)
            entries = tk.kit_entries(self.card, self.cards, pilot=True)
            with mock.patch.object(tk, "PASS_FILE", path), mock.patch("builtins.print"):
                added = tk.write_entries(entries)
            sheets = json.load(open(path))["sheets"]
            self.assertEqual([e["id"] for e in added], [entries[1]["id"]])
            self.assertEqual(sheets[0], {"id": "mossvale_city_b0", "keep": True})


class Sizes(unittest.TestCase):
    def test_building_height_uses_the_kit_scale(self):
        rgb = np.zeros((800, 400, 4), np.uint8)
        rgb[100:446, 50:350] = (100, 60, 30, 255)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "b.png")
            Image.fromarray(rgb).save(path)
            self.assertEqual(tk.building_height(path), round(346 / tk.KIT_ART_PX * tk.TEXEL, 1))

    def test_last_word(self):
        self.assertEqual(tk.last_word("Old Dace"), "dace")
        self.assertEqual(tk.last_word(""), "")


class TownChecks(unittest.TestCase):
    """sheet_check's town kit checks on a building painted over the wide canvas."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.door = tk.door_box("building_wide")

    def tearDown(self):
        self.dir.cleanup()

    def building(self, shift=0, edge=False, stray=False):
        rgb = np.asarray(tk.draw_canvas("building_wide")).astype(np.int32).copy()
        x0, y0, x1, y1 = self.door
        rgb[y0:y1, x0:x1] = tk.MAGENTA  # Gemini paints over the mark
        rgb[700 + shift:y1 + shift, x0 - 150:x1 + 150] = (150, 110, 80)
        rgb[y0 + shift:y1 + shift, x0:x1] = (70, 40, 25)
        if edge:
            rgb[900:1000, 0:x0] = (150, 110, 80)
        if stray:
            rgb[40:80, 40:80] = (150, 110, 80)
        path = os.path.join(self.dir.name, "b.png")
        Image.fromarray(rgb.astype(np.uint8)).save(path)
        return statuses(sc.check(path, cells=[1, 1], stands=True,
                                 town={"kind": "building", "door": self.door}))

    def test_a_building_on_its_mark_passes(self):
        result = self.building()
        for name in ("door on its mark", "base on the ground line", "not cut off", "stray bits"):
            self.assertEqual(result[name], "pass", (name, result))

    def test_a_building_off_the_ground_line_fails(self):
        self.assertEqual(self.building(shift=-80)["base on the ground line"], "fail")

    def test_art_at_the_edge_fails_and_stray_bits_warn(self):
        self.assertEqual(self.building(edge=True)["not cut off"], "fail")
        self.assertEqual(self.building(stray=True)["stray bits"], "warn")

    def test_a_busy_backdrop_foreground_warns(self):
        rng = np.random.default_rng(1)
        rgb = np.full((600, 1400, 3), 150)
        rgb[450:] = rng.integers(0, 255, (150, 1400, 3))
        path = os.path.join(self.dir.name, "p.png")
        Image.fromarray(rgb.astype(np.uint8)).save(path)
        result = sc.check(path, town={"kind": "backdrop"})
        self.assertIn("warn", [c["status"] for c in result["checks"] if "foreground" in c["check"]])


def statuses(result):
    return {c["check"]: c["status"] for c in result["checks"]}


if __name__ == "__main__":
    unittest.main()
