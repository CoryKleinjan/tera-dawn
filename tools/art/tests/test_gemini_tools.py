"""The Gemini tools' offline parts: picking one item out of a batch, building the request,
choosing an aspect ratio, never overwriting an earlier try, reading the batch API's answers,
and the run list in gemini_pass.json. Nothing here talks to Gemini."""

import json
import os
import tempfile
import unittest
from unittest import mock

from PIL import Image

import helpers
import gemini_pass
import gemini_sheet


class PickItem(unittest.TestCase):
    BATCH = "Draw these:\n1. SWORD: a short blade\n2. WAND: a twig\n- BOW: a curve\nKeep the grid."

    def test_keeps_only_the_wanted_item(self):
        text = gemini_sheet.pick_item(self.BATCH, "WAND")
        self.assertIn("WAND: a twig", text)
        self.assertNotIn("SWORD", text)
        self.assertNotIn("BOW", text)
        self.assertIn("Keep the grid.", text)
        self.assertTrue(text.endswith("Draw ONLY WAND in this image, nothing else from my list."))

    def test_matches_in_any_case_and_with_a_number(self):
        self.assertIn("SWORD: a short blade", gemini_sheet.pick_item(self.BATCH, "1. sword"))

    def test_drops_the_ask_for_the_next_item(self):
        text = gemini_sheet.pick_item("1. A: x\n2. B: y\nStart with A; I'll ask for the next after.", "A")
        self.assertNotIn("Start with", text)


class Request(unittest.TestCase):
    def test_build_request_reads_like_a_chat(self):
        body = gemini_sheet.build_request("Message 0", "4 x 8", "Batch text", ["a.png", "b.png"], "16:9", "2K",
                                          image=lambda p: {"image": p})
        parts = body["contents"][0]["parts"]
        self.assertEqual(parts[:2], [{"image": "a.png"}, {"image": "b.png"}], "references first, in order")
        self.assertEqual(parts[2]["text"], "Message 0\n\n4 x 8")
        self.assertEqual([c["role"] for c in body["contents"]], ["user", "model", "user"])
        self.assertEqual(body["contents"][2]["parts"][0]["text"], "Batch text")
        self.assertEqual(body["generationConfig"]["imageConfig"], {"aspectRatio": "16:9", "imageSize": "2K"})

    def test_no_layout_means_message_0_alone(self):
        body = gemini_sheet.build_request("M0", None, "B", [], "1:1", "2K", image=lambda p: p)
        self.assertEqual(body["contents"][0]["parts"], [{"text": "M0"}])

    def test_closest_aspect(self):
        with tempfile.TemporaryDirectory() as d:
            for size, want in (((200, 100), "16:9"), ((100, 100), "1:1"), ((300, 400), "3:4"), ((2100, 900), "21:9")):
                path = os.path.join(d, "x.png")
                Image.new("RGB", size).save(path)
                self.assertEqual(gemini_sheet.closest_aspect(path), want, size)


class OutPath(unittest.TestCase):
    def test_never_overwrites_an_earlier_try(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(gemini_sheet, "OUT_DIR", d):
            first = gemini_sheet.out_path("art/hero.png", "B1", 4)
            self.assertEqual(os.path.basename(first), "hero_gemini.png")
            open(first, "w").close()
            second = gemini_sheet.out_path("art/hero.png", "B1", 4)
            self.assertEqual(os.path.basename(second), "hero_gemini_2.png")
            open(second, "w").close()
            self.assertEqual(os.path.basename(gemini_sheet.out_path("hero.png", "B1", 4)), "hero_gemini_3.png")

    def test_without_a_save_name_uses_part_and_batch(self):
        with tempfile.TemporaryDirectory() as d, mock.patch.object(gemini_sheet, "OUT_DIR", d):
            self.assertEqual(os.path.basename(gemini_sheet.out_path(None, "W1", 8)), "part8_w1_gemini.png")


class FindKey(unittest.TestCase):
    def test_finds_the_first_value_anywhere(self):
        resp = {"response": {"candidates": [{"content": {"parts": [{"text": "hi"}, {"inlineData": {"data": "abc"}}]}}]}}
        self.assertEqual(gemini_pass.find_key(resp, "inlineData"), {"data": "abc"})
        self.assertEqual(gemini_pass.find_key(resp, "text"), "hi")

    def test_missing_key(self):
        self.assertIsNone(gemini_pass.find_key({"a": [1, {"b": 2}]}, "c"))
        self.assertIsNone(gemini_pass.find_key("plain", "c"))


class RunList(unittest.TestCase):
    """gemini_pass.json is edited by hand; a slip there costs a paid run."""

    @classmethod
    def setUpClass(cls):
        with open(gemini_pass.LIST, encoding="utf-8") as f:
            cls.sheets = json.load(f)["sheets"]

    def test_ids_and_save_names_are_unique(self):
        ids = [s["id"] for s in self.sheets]
        self.assertEqual(len(ids), len(set(ids)))
        saves = [s["save"] for s in self.sheets]
        self.assertEqual(len(saves), len(set(saves)))

    def test_every_sheet_is_well_formed(self):
        for s in self.sheets:
            with self.subTest(s["id"]):
                self.assertIn(s["kind"], ("still", "anim"))
                self.assertTrue(s["save"].endswith(".png"))
                if s["cells"] is not None:
                    self.assertEqual(len(s["cells"]), 2)
                    self.assertTrue(all(isinstance(n, int) and n > 0 for n in s["cells"]))

    def test_edits_have_a_base_image_in_the_repo_and_an_instruction(self):
        for s in self.sheets:
            if not s.get("edit"):
                continue
            with self.subTest(s["id"]):
                base = os.path.join(gemini_sheet.ROOT, s["edit"]["base"])
                self.assertTrue(os.path.isfile(base), base)
                self.assertTrue(s["edit"].get("text", "").strip())
                for r in s["edit"].get("refs", []):
                    self.assertTrue(os.path.isfile(os.path.join(gemini_sheet.ROOT, r)), r)

    def test_anchors_name_other_sheets_or_files(self):
        ids = {s["id"] for s in self.sheets}
        for s in self.sheets:
            if s["anchor"]:
                with self.subTest(s["id"]):
                    self.assertTrue(s["anchor"] in ids or os.path.isfile(os.path.join(gemini_sheet.ROOT, s["anchor"])),
                                    s["anchor"])


if __name__ == "__main__":
    unittest.main()
