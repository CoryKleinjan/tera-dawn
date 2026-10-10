#!/usr/bin/env python3
"""How big one art pixel of every piece of land shows in the game, compared with the rest.

    python3 tools/art/land_pixels.py           # the table, worst first
    python3 tools/art/land_pixels.py --check   # exit 1 if any piece is off by more than allowed

Land art (art/sheets manifests with "art_px": tiles, platform pieces, ground textures) is cut
at 2 texels per art pixel, and the game draws it at TDStage.TEXEL game pixels per art pixel,
times the piece's "grow" in its manifest and the scale a biome's decor rule or a map's prop
gives it. This reads all three and reports grow x scale for every use: 1.0 means the piece
shows at exactly the shared pixel size.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
# grow x scale may stray this far from 1 either way before a piece stands out
ALLOWED = (0.75, 1.3)


def grows():
    """res:// path of every land sprite -> its grow, from the manifests that cut it."""
    out = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "art", "sheets", "*.json"))):
        with open(path) as f:
            man = json.load(f)
        if not man.get("art_px"):
            continue
        over = man.get("overrides", {})
        for row in man["cells"]:
            for name in row:
                if not name:
                    continue
                o = over.get(name, {})
                if o.get("save", man.get("save", True)) is False:
                    continue
                out_dir = o.get("out_dir", man["out_dir"])
                out["res://%s/%s.png" % (out_dir, name)] = o.get("grow", man.get("grow", 1.0))
    return out


def uses():
    """(file, texture path, low scale, high scale) for every decor rule and prop that draws land art."""
    found = []
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "biomes", "*.tres")) +
                       glob.glob(os.path.join(ROOT, "data", "maps", "*.tres"))):
        text = open(path).read()
        ext = {i: p for p, i in re.findall(r'\[ext_resource type="[^"]+" path="([^"]+)" id="([^"]+)"\]', text)}
        for block in re.split(r"\n(?=\[sub_resource)", text):
            script = re.search(r'script = ExtResource\("([^"]+)"\)', block)
            if not script or not ext.get(script.group(1), "").endswith(("decor_def.gd", "prop_placement.gd")):
                continue
            pair = re.search(r"\nscale = Vector2\(([\d.]+), ([\d.]+)\)", block)
            one = re.search(r"\nscale = ([\d.]+)\n", block + "\n")
            lo, hi = (float(pair.group(1)), float(pair.group(2))) if pair else \
                ((float(one.group(1)),) * 2 if one else (1.0, 1.0))
            texel = re.search(r"\ntexel = ([\d.]+)", block)
            k = float(texel.group(1)) / 1.25 if texel else 1.0  # decor texel against TDStage.TEXEL
            for tid in re.findall(r'ExtResource\("([^"]+)"\)', block):
                tex = ext.get(tid, "")
                if tex.endswith(".png"):
                    found.append((os.path.relpath(path, ROOT), tex, lo * k, hi * k))
    return found


def table():
    g = grows()
    rows = []
    for where, tex, lo, hi in uses():
        if tex in g:
            rows.append((where, tex, g[tex] * lo, g[tex] * hi))
    return rows


def off(rows):
    lo, hi = ALLOWED
    return [r for r in rows if r[2] < lo - 1e-6 or r[3] > hi + 1e-6]


def main():
    rows = table()
    rows.sort(key=lambda r: -max(abs(r[2] - 1), abs(r[3] - 1)))
    for where, tex, lo, hi in rows[:40]:
        print("%-36s %-56s %.2f-%.2f" % (where, tex.replace("res://assets/sprites/", ""), lo, hi))
    bad = off(rows)
    print("%d uses of land art, %d outside %.2f-%.2f" % (len(rows), len(bad), *ALLOWED))
    if "--check" in sys.argv and bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
