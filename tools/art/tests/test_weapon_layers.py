"""Every weapon with its own held picture shows in his hand about as big as its kind's template
(paperdoll_layers' weapon pieces, assets/sprites/characters/pieces/weapon_*.json). Like test_sprite_edges this reads the real game sprites,
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
PIECES = os.path.join(ROOT, "assets", "sprites", "characters", "pieces")
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


def held_size(name):
    """How long a weapon piece is held (its held picture's diagonal, grown by its largest pose)."""
    with open(os.path.join(PIECES, f"weapon_{name}.json")) as f:
        piece = json.load(f)
    img = Image.open(os.path.join(ROOT, piece["views"]["held"]["picture"][len("res://"):])).getchannel("A")
    box = img.getbbox()
    grow = max((e["scale"] for e in piece["frames"] if e and e["view"] == "held"), default=0.0)
    return float(np.hypot(box[2] - box[0], box[3] - box[1])) * grow if box else 0.0


class WeaponLayers(unittest.TestCase):
    def test_every_weapon_is_held_about_as_big_as_its_kind(self):
        kinds = weapon_kinds()
        templates = {}
        checked = 0
        for path in sorted(glob.glob(os.path.join(PIECES, "weapon_item_*.json"))):
            name = os.path.basename(path)[len("weapon_"):-len(".json")]
            kind = kinds.get(name[len("item_"):])
            self.assertIsNotNone(kind, f"{name}: no weapon item for this piece")
            if kind not in templates:
                templates[kind] = held_size(kind)
            share = held_size(name) / templates[kind]
            self.assertGreater(share, MIN_SHARE, f"{name} is held at {share:.0%} of a {kind}'s size")
            checked += 1
        self.assertGreater(checked, 0, "no weapon pieces found")


if __name__ == "__main__":
    unittest.main()
