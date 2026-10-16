"""import_settings.py: world art is imported GPU-compressed with mipmaps, UI stays lossless."""

import unittest

import helpers  # noqa: F401 (puts tools/art on the path)

import import_settings as imp


class ImportSettingsTest(unittest.TestCase):
    def test_params_are_set_in_place(self):
        text = "[params]\n\ncompress/mode=0\ncompress/high_quality=false\nmipmaps/generate=false\nmipmaps/limit=-1\n"
        out = imp.apply(text, imp.COMPRESSED_PARAMS)
        self.assertIn("compress/mode=2\n", out)
        self.assertIn("compress/high_quality=true\n", out)
        self.assertIn("mipmaps/generate=true\n", out)
        self.assertIn("mipmaps/limit=-1\n", out)

    def test_ui_and_the_hero_stay_lossless(self):
        for folder in ["ui", "items", "skills", "hero"]:
            self.assertIsNone(imp.wanted(folder))

    def test_every_world_picture_is_imported_as_listed(self):
        for path, params in imp.imports():
            text = open(path).read()
            self.assertEqual(imp.apply(text, params), text, f"{path}: run tools/art/import_settings.py")


if __name__ == "__main__":
    unittest.main()
