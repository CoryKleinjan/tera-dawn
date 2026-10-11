"""Every weapon with its own held picture shows in his hand about as big as its kind's template
(paperdoll_layers' weapon layers). Like test_sprite_edges this reads the real game sprites,
since what it guards is their output: a bow sheet drawn at a slant once came out half size and
tilted, a faint line nobody could see in game (see paperdoll_layers.stood_up)."""

import glob
import json
import os
import re
import unittest

import numpy as np
from PIL import Image

import helpers  # noqa: F401  (puts the tools folder on the import path)

ROOT = os.path.normpath(os.path.join(helpers.TOOLS, "..", ".."))
LAYERS = os.path.join(ROOT, "assets", "sprites", "characters", "layers")
RIG = os.path.join(ROOT, "assets", "sprites", "characters", "hero_rig.json")
ITEMS = os.path.join(ROOT, "data", "items")
# How small a weapon's own picture may be held against its kind's template (the longest the
# weapon reaches on any frame); held_size and the sheets' own sizes keep them well above it.
MIN_SHARE = 0.7


def weapon_kinds():
    """item id -> weapon kind, for every weapon item."""
    out = {}
    for path in glob.glob(os.path.join(ITEMS, "**", "*.tres"), recursive=True):
        with open(path) as f:
            text = f.read()
        item, kind = re.search(r'^id = &"(\w+)"', text, re.M), re.search(r'^weapon_kind = &"(\w+)"', text, re.M)
        if item and kind:
            out[item.group(1)] = kind.group(1)
    return out


def held_size(name, frames):
    """The longest a weapon layer reaches on any frame (its bounding box's diagonal, pixels)."""
    img = Image.open(os.path.join(LAYERS, f"weapon_{name}.png")).getchannel("A")
    fw = img.width // frames
    best = 0.0
    for i in range(frames):
        box = img.crop((i * fw, 0, (i + 1) * fw, img.height)).getbbox()
        if box:
            best = max(best, float(np.hypot(box[2] - box[0], box[3] - box[1])))
    return best


class WeaponLayers(unittest.TestCase):
    def test_every_weapon_is_held_about_as_big_as_its_kind(self):
        with open(RIG) as f:
            frames = len(json.load(f)["frames"])
        kinds = weapon_kinds()
        templates = {}
        checked = 0
        for path in sorted(glob.glob(os.path.join(LAYERS, "weapon_item_*.png"))):
            name = os.path.basename(path)[len("weapon_"):-len(".png")]
            if name.endswith("_behind"):
                continue
            kind = kinds.get(name[len("item_"):])
            self.assertIsNotNone(kind, f"{name}: no weapon item for this layer")
            if kind not in templates:
                templates[kind] = held_size(kind, frames)
            share = held_size(name, frames) / templates[kind]
            self.assertGreater(share, MIN_SHARE, f"{name} is held at {share:.0%} of a {kind}'s size")
            checked += 1
        self.assertGreater(checked, 0, "no weapon layers found")


if __name__ == "__main__":
    unittest.main()
