#!/usr/bin/env python3
"""The town kit: every new town is painted from the same fixed canvases and locked prompts.

    python3 tools/art/town_kit.py canvases               # redraw the fixed canvases (templates/town/)
    python3 tools/art/town_kit.py entries <town>         # print the Gemini entries the town's card makes
    python3 tools/art/town_kit.py entries <town> --pilot # only the pilot: the first building and the backdrop
    python3 tools/art/town_kit.py entries <town> --write # add them to gemini_pass.json (never replaces one)
    python3 tools/art/town_kit.py height <cut building.png>  # its BuildingDef height and manifest art_px
    python3 tools/art/town_kit.py names Lettie "Old Dace"    # are these NPC names free on main and every branch?

A town's card (`tools/art/towns/<town>.json`, keys in `CARD_KEYS`) holds everything that differs
between towns: its look from docs/zone-vibes.md, its building, prop and townsfolk lists, and its
signature materials. Everything else is fixed here, so every town is asked for in the same words:

- one piece per paint for buildings, the lamp and the backdrop; props six to a sheet;
- every building canvas marks the doorway at the bottom centre, at the size of a door next to the
  hero, and every kit building is cut at the same scale (`KIT_ART_PX`), so doors match in every
  town and a tower's height comes from its painting;
- fixed references: buildings get the NPC style picture and this town's approved flat buildings
  only; the backdrop and props get no picture with people or buildings in it;
- the other towns' signature materials are named as banned in every prompt;
- each entry carries a `town_check` that sheet_check.py runs on the result (door on its mark,
  nothing cut off at the edge, stray bits, glow halos, a clear backdrop foreground).

Results go in exactly as painted. A failed check goes to Cory as keep, repaint or leave out.
"""
import argparse
import glob
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
CANVAS_DIR = os.path.join(HERE, "templates", "town")
CARD_DIR = os.path.join(HERE, "towns")
PASS_FILE = os.path.join(HERE, "gemini_pass.json")
STYLE_REF = "/mnt/project-files/art-sheets/flat-buildings/npc_style_ref.png"

MAGENTA = (255, 0, 255)
# The doorway mark: a flat dark brown doorway with a round top. Gemini paints the door over it.
DOOR_COLOUR = (74, 44, 30)
# Sheet pixels per art pixel for every kit building (art/sheets "art_px"). Dawnharbor's tavern, the
# gold standard, is 3.461: its doorway mark is 344 px tall in the painting; the door painted in it shows about 1.2 heroes in game.
KIT_ART_PX = 3.461
TEXEL = 1.25  # game px per art px (TDStage.TEXEL)
DOOR_W, DOOR_H = 225, 344  # the doorway mark in canvas px (the tavern's door)
GROUND_MARGIN = 110  # canvas px between the doorway's bottom (the ground line) and the canvas bottom

# name: (width, height, Gemini size, has a doorway mark)
CANVASES = {
    "building_wide": (1434, 1377, "2K", True),     # halls, stores, houses
    "building_narrow": (1100, 1500, "2K", True),   # row houses, small shops
    "building_tall": (1152, 2048, "2K", True),     # towers, lookouts, windmills
    "lamp_post": (1152, 2048, "2K", False),
    "props": (3072, 1728, "4K", False),            # 2 rows x 3 props
    "panorama": (3072, 1316, "4K", False),         # one backdrop for the whole town
    "townsfolk": (2048, 1024, "2K", False),        # 1 row x 4 (three villagers and the keeper)
    "room_wall": (2880, 4096, "4K", False),        # a back wall tile, as flat colour bands
}
BUILDING_CANVASES = [k for k, v in CANVASES.items() if v[3]]

CARD_KEYS = {
    "id": "town id, as in data/maps (e.g. lanternfall)",
    "name": "the town's name",
    "role": "who lives there, e.g. \"the thieves' town\"",
    "mood": "one line of feel, from docs/zone-vibes.md",
    "light": "the light, from docs/zone-vibes.md",
    "palette": "the colours, with the zone's hex values",
    "materials": "what its buildings are made of",
    "texture": "the painted detail to show (wood grain, cracked plaster...)",
    "signature": "its own materials that no other town may use",
    "buildings": "list of {id, name, canvas, look}; the first is the pilot",
    "approved_refs": "approved flat buildings of this town to match (paths), filled after the pilot",
    "backdrop": "the panorama's scene",
    "backdrop_bottom": "what the bottom quarter of the panorama shows (far away, nothing near)",
    "lamp": "the lamp post's look",
    "props": "6 or 12 props, each a short look seen exactly from the side",
    "raised": "materials for the raised levels' top, wall and corners, or null",
    "townsfolk": "4 of {label, look}; the 4th is the town's own storage keeper",
    "npc_refs": "paths of NPC sheets already living in the town (job tutor, shopkeeper)",
    "rooms": "{store: look, hall: look} for the two back walls",
}
EXISTING_KEYS = ("id", "name", "signature")  # a town built before the kit needs only these

STYLE_LINE = ("they are drawn in exactly the art style the whole game must have: soft cel-painted "
              "shading with clear light and shadow shapes and bright highlights on the lit edges, rich "
              "warm saturated colours, bold dark brown outlines, and plenty of hand-painted detail ({texture})")
PAINTED = "Painted, not pixel art: smooth painted shading with visible soft brush texture, no visible pixels."
NO_TEXT = "No letters, numbers or words anywhere."
MAGENTA_BG = ("Flat pure magenta #FF00FF background everywhere outside the art, with no magenta or pink "
              "anywhere inside it, and no glow or light spilling onto the background.")
NO_FIGURES = "Do not draw any characters, animals or birds."


# --- canvases ---------------------------------------------------------------------------------

def door_box(name):
    """The doorway mark [x0, y0, x1, y1] on a building canvas."""
    w, h, _, _ = CANVASES[name]
    x0 = (w - DOOR_W) // 2
    y1 = h - GROUND_MARGIN
    return [x0, y1 - DOOR_H, x0 + DOOR_W, y1]


def draw_canvas(name):
    w, h, _, door = CANVASES[name]
    if name == "panorama":
        # a soft neutral gradient: a scene is painted edge to edge, so it needs no magenta
        top, bottom = np.array([92, 112, 150]), np.array([236, 214, 190])
        t = np.linspace(0, 1, h)[:, None, None]
        rgb = (top * (1 - t) + bottom * t).repeat(w, axis=1).astype(np.uint8)
        return Image.fromarray(rgb, "RGB")
    if name == "room_wall":
        # flat colour bands where Dawnharbor's wall has them: a wood frieze, the wall, a window
        # and wood panelling. Painted fresh over flat colours, never over an old (pixel) wall.
        im = Image.new("RGB", (w, h), (176, 160, 140))
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, w, round(h * 0.13)], fill=(110, 74, 48))
        d.rectangle([0, round(h * 0.76), w, h], fill=(120, 82, 54))
        d.rectangle([round(w * 0.36), round(h * 0.24), round(w * 0.64), round(h * 0.62)], fill=(150, 170, 190))
        return im
    im = Image.new("RGB", (w, h), MAGENTA)
    d = ImageDraw.Draw(im)
    if door:
        x0, y0, x1, y1 = door_box(name)
        r = (x1 - x0) // 2
        d.rectangle([x0, y0 + r, x1 - 1, y1 - 1], fill=DOOR_COLOUR)
        d.ellipse([x0, y0, x1 - 1, y0 + 2 * r], fill=DOOR_COLOUR)
    return im


def write_canvases():
    os.makedirs(CANVAS_DIR, exist_ok=True)
    for name in CANVASES:
        path = os.path.join(CANVAS_DIR, name + ".png")
        draw_canvas(name).save(path, optimize=True)
        print(os.path.relpath(path, ROOT))


def canvas_path(name):
    return os.path.relpath(os.path.join(CANVAS_DIR, name + ".png"), ROOT)


# --- cards ------------------------------------------------------------------------------------

def card_path(town):
    return os.path.join(CARD_DIR, town + ".json")


def load_card(town):
    with open(card_path(town)) as f:
        return json.load(f)


def all_cards():
    return {os.path.splitext(os.path.basename(p))[0]: json.load(open(p))
            for p in sorted(glob.glob(os.path.join(CARD_DIR, "*.json")))
            if not os.path.basename(p).startswith("_")}


def card_problems(card):
    """What a card is missing before it can make a kit (empty list when complete)."""
    out = ["missing %s (%s)" % (k, v) for k, v in CARD_KEYS.items() if k not in card]
    if out:
        return out
    if not 5 <= len(card["buildings"]) <= 6:
        out.append("5 or 6 buildings, found %d" % len(card["buildings"]))
    for b in card["buildings"]:
        if b.get("canvas") not in BUILDING_CANVASES:
            out.append("%s: canvas must be one of %s" % (b.get("id"), ", ".join(BUILDING_CANVASES)))
    ids = [b.get("id") for b in card["buildings"]]
    if len(set(ids)) != len(ids):
        out.append("two buildings share an id")
    if len(card["props"]) not in (6, 12):
        out.append("6 or 12 props (sheets of 6), found %d" % len(card["props"]))
    if len(card["townsfolk"]) != 4:
        out.append("4 townsfolk (three villagers and the storage keeper), found %d" % len(card["townsfolk"]))
    if set(card["rooms"]) != {"store", "hall"}:
        out.append("rooms needs exactly store and hall")
    return out


def banned_line(card, cards):
    others = [c["signature"] for t, c in sorted(cards.items()) if t != card["id"] and c.get("signature")]
    if not others:
        return ""
    return ("Never use these materials, they belong to other towns: %s." % "; ".join(others))


def town_line(card):
    return "%s, %s in my 2D side-scrolling game: %s, lit by %s" % (card["name"], card["role"], card["mood"], card["light"])


# --- locked prompts ---------------------------------------------------------------------------

def building_entry(card, b, cards):
    refs = [STYLE_REF] + list(card["approved_refs"])
    text = ("The first image is an empty magenta canvas with a dark brown doorway shape at the bottom "
            "centre. On it, paint ONE building for %s. The second image shows four of my game's NPC "
            "characters; %s. " % (town_line(card), STYLE_LINE.format(texture=card["texture"])))
    if card["approved_refs"]:
        text += ("The next images are buildings already approved for the same town: match their style, "
                 "palette, outline thickness and level of detail exactly, so they clearly belong together, "
                 "but do not copy their shapes. ")
    text += ("The building is the %s: %s. Materials and colours: %s; palette %s. Strict rules: "
             "1) Pure front view at eye level, like an architect's front elevation: only the front face "
             "shows, no roof surface seen from above, no side wall, every horizontal line level and every "
             "wall edge vertical. "
             "2) The building's front door is painted exactly over the dark brown doorway shape: the same "
             "place and the same size, its bottom on the doorway's bottom edge. "
             "3) The bottom of the whole building is ONE straight horizontal line, level with the bottom "
             "of the doorway, from edge to edge, with nothing hanging lower. Nothing below the base or in "
             "front of it: no steps, path, ground line, ground patch, grass, roots or shadow. "
             "4) The whole building fits inside the picture, centred, with a clear band of magenta on "
             "every side; nothing touches the edges. Nothing (rope, chain, cloth, bunting) ends loose in "
             "mid-air. 5) %s %s %s %s %s"
             % (b["name"].upper(), b["look"], card["materials"], card["palette"], PAINTED, NO_TEXT,
                banned_line(card, cards), MAGENTA_BG, NO_FIGURES))
    return entry(card, "%s_city_%s" % (card["id"], b["id"]), "building: %s" % b["name"], canvas_path(b["canvas"]),
                 refs, text, stands=True, size=CANVASES[b["canvas"]][2],
                 town_check={"kind": "building", "door": door_box(b["canvas"])})


def backdrop_entry(card, cards):
    text = ("The first image is a blank canvas showing only a soft colour gradient. Repaint the whole canvas "
            "as ONE complete, seamless, highly detailed background painting for %s. The whole game uses one "
            "art style: soft cel-painted shading with clear light and shadow shapes and bright highlights on "
            "the lit edges, rich warm saturated colours, bold dark brown outlines, and plenty of hand-painted "
            "detail (%s). Paint the background in that style, a little softer and lighter in contrast so it "
            "sits behind the characters. The scene: %s. Colours: %s. Strict rules: "
            "1) Side-on view at eye level, the horizon level, everything upright. "
            "2) No people, no characters, no figures of any kind, no animals, no birds. "
            "3) Nothing in the near foreground: the bottom quarter of the picture is %s, with nothing close "
            "to the viewer (no flowers, grass blades, fences, rocks, decks, planks, stairs, posts or "
            "plants up front); the closest things are in the middle distance. "
            "4) The left and right edges continue naturally, nothing is cut in half at the edges. "
            "5) Fill the whole canvas edge to edge with painting; no border, no frame, no magenta. "
            "6) %s %s %s"
            % (town_line(card), card["texture"], card["backdrop"], card["palette"], card["backdrop_bottom"],
               PAINTED, NO_TEXT, banned_line(card, cards)))
    return entry(card, "%s_backdrop_panorama" % card["id"], "backdrop panorama", canvas_path("panorama"),
                 [], text, stands=False, size="4K", town_check={"kind": "backdrop"})


def lamp_entry(card, cards):
    refs = [STYLE_REF] + list(card["approved_refs"])
    text = ("The first image is an empty magenta canvas. On it, paint ONE lamp post for %s. The second image "
            "shows four of my game's NPC characters; %s. " % (town_line(card), STYLE_LINE.format(texture=card["texture"])))
    if card["approved_refs"]:
        text += "The next images are buildings from the same town: match their palette, materials and level of detail. "
    text += ("The lamp: %s. It is about two and a half times as tall as a person. Strict rules: 1) Pure side view "
             "at eye level, perfectly upright and centred. 2) Its bottom is ONE flat straight horizontal edge, with "
             "no ground, grass or shadow under it. 3) It fills most of the canvas height with a clear band of "
             "magenta on every side; nothing touches the edges. Nothing hangs loose from it. 4) %s %s %s %s %s"
             % (card["lamp"], PAINTED, NO_TEXT, banned_line(card, cards), MAGENTA_BG, NO_FIGURES))
    return entry(card, "%s_lamp_post" % card["id"], "lamp post", canvas_path("lamp_post"), refs, text,
                 stands=True, size="2K", town_check={"kind": "single"})


def props_entries(card, cards):
    out = []
    for n in range(len(card["props"]) // 6):
        six = card["props"][n * 6:(n + 1) * 6]
        listed = " ".join("%d) %s." % (i + 1, p) for i, p in enumerate(six))
        text = ("The first image is an empty magenta canvas. On it, paint SIX separate props for %s, in two rows "
                "of three, each centred in its own sixth of the canvas with a wide band of plain magenta around "
                "it, none touching. Paint them in the game's art style: soft cel-painted shading with clear "
                "light and shadow shapes, bright highlights, rich warm saturated colours, bold dark brown "
                "outlines and hand-painted detail (%s). Materials and colours: %s. The props, left to right, "
                "top row first: %s Strict rules: 1) Every prop is a pure flat side view at eye level, like an "
                "architect's elevation: only its front face shows, NO top surface of anything visible (no box "
                "lids, barrel tops, basin or tray insides, seat tops or rims seen from above), every edge level "
                "or vertical. 2) Each stands upright on ONE flat straight bottom edge, with no ground, grass, "
                "shadow or base under it. 3) Nothing (rope, cloth) ends loose in mid-air. 4) No grid lines, "
                "borders or frames. 5) %s %s %s %s %s"
                % (town_line(card), card["texture"], card["materials"], listed, PAINTED, NO_TEXT,
                   banned_line(card, cards), MAGENTA_BG, NO_FIGURES))
        out.append(entry(card, "%s_props_%d" % (card["id"], n + 1), "props %d" % (n + 1), canvas_path("props"),
                         [], text, stands=True, size="4K", cells=[2, 3], town_check={"kind": "cells"}))
    return out


def raised_entry(card, cards):
    if not card["raised"]:
        return []
    text = ("The first image is a sheet of painted ground pieces for a raised stone terrace in my 2D "
            "side-scrolling game (Dawnharbor's): the top row is the top edge of the terrace cut into four pieces "
            "that join side by side (END LEFT, MIDDLE A, MIDDLE B, END RIGHT), and below are a left corner column, "
            "a repeating wall, and a right corner column. Keep the sheet's size, layout, labels, magenta "
            "background, and every piece's outline shape, position and size EXACTLY, so the pieces still join "
            "seamlessly and the wall still repeats. Repaint ONLY the materials so they belong to %s: %s. "
            "Paint them in the game's art style (soft cel-painted shading, bright highlights, bold dark outlines, "
            "%s). Everything stays a flat front view, with no top surface seen from above. %s %s Flat pure "
            "magenta #FF00FF background everywhere outside the pieces."
            % (town_line(card), card["raised"], card["texture"], PAINTED, banned_line(card, cards)))
    return [entry(card, "%s_raised_pieces" % card["id"], "raised level pieces",
                  "art/source/terrace_pieces_dawnharbor.png", [], text, stands=True, size="2K",
                  town_check={"kind": "sheet"})]


def townsfolk_entry(card, cards):
    refs = [STYLE_REF] + list(card["npc_refs"])
    cols = " ".join("Column %d: %s%s." % (i + 1, "the town's STORAGE KEEPER, " if i == 3 else "", t["look"])
                    for i, t in enumerate(card["townsfolk"]))
    text = ("The first image is an empty magenta canvas. On it, paint FOUR townsfolk of %s side by side in one "
            "row, each centred in its own quarter of the canvas, none touching. The other images show my game's "
            "NPC characters (and the ones who already live in this town); the new ones must look like they "
            "belong with them: the same chibi proportions and size, soft cel-painted shading, rich colours, dark "
            "outlines, painted cloth folds and worn patches. Do not copy any character from those images. %s "
            "Rules: every character stands still, upright, facing slightly toward the viewer, both feet flat on "
            "one shared level ground line, full body in its quarter. Hands are simple rounded mittens in the "
            "game's style. Nothing else in the picture: no labels, objects, flags or grid lines. %s %s"
            % (town_line(card), cols, PAINTED, MAGENTA_BG))
    return entry(card, "%s_townsfolk" % card["id"], "townsfolk", canvas_path("townsfolk"), refs, text,
                 stands=False, size="2K", cells=[1, 4], town_check={"kind": "cells"})


def room_entries(card, cards):
    out = []
    for room in ("store", "hall"):
        text = ("The first image is a flat colour layout of one repeating tile of the back wall inside the %s in "
                "%s: a wooden frieze band at the top, the wall in the middle with one window, and wooden panelling "
                "at the bottom. Keep those bands and the window in exactly the same places, at the same image size, "
                "and repaint the whole tile as a finished painting: %s. Everything is seen straight from the front, "
                "flat against the wall, with no perspective, no top faces and no side depth; nothing ends loose in "
                "mid-air. No shelves or goods unless asked. The left and right edges must join seamlessly when the "
                "tile is repeated side by side. Paint in the game's style: rich colours, strong light and shadow "
                "with bright highlights, visible painted texture at a fairly chunky brush scale, a thin dark "
                "outline (%s). %s %s %s"
                % ("shop" if room == "store" else "job hall", town_line(card), card["rooms"][room],
                   card["texture"], PAINTED, NO_TEXT, banned_line(card, cards)))
        out.append(entry(card, "room_%s_%s_wall" % (card["id"], room), "%s wall" % room, canvas_path("room_wall"),
                         [STYLE_REF], text, stands=False, size="4K", town_check={"kind": "wall"}))
    return out


def entry(card, sid, what, base, refs, text, stands, size, cells=(1, 1), town_check=None):
    return {"id": sid, "prompts": None, "batch": "%s town kit: %s" % (card["name"], what), "with": None,
            "refs": [], "save": sid + ".png", "replaces": None, "kind": "still", "stands": stands,
            "cells": list(cells), "anchor": None, "size": size,
            "note": "Made by tools/art/town_kit.py from tools/art/towns/%s.json (town kit)." % card["id"],
            "edit": {"base": base, "refs": refs, "text": text}, "town_check": town_check}


def kit_entries(card, cards, pilot=False):
    problems = card_problems(card)
    if problems:
        raise ValueError("%s's card is not ready: %s" % (card["id"], "; ".join(problems)))
    if pilot:
        return [building_entry(card, card["buildings"][0], cards), backdrop_entry(card, cards)]
    out = [building_entry(card, b, cards) for b in card["buildings"]]
    out += [backdrop_entry(card, cards), lamp_entry(card, cards)] + props_entries(card, cards)
    out += raised_entry(card, cards) + [townsfolk_entry(card, cards)] + room_entries(card, cards)
    return out


def write_entries(entries):
    with open(PASS_FILE) as f:
        data = json.load(f)
    have = {s["id"] for s in data["sheets"]}
    added = [e for e in entries if e["id"] not in have]
    for e in entries:
        if e["id"] in have:
            print("kept the existing entry %s (never replaced; give a redo its own id)" % e["id"])
    data["sheets"] += added
    with open(PASS_FILE, "w") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    return added


# --- sizes and names --------------------------------------------------------------------------

def building_height(path):
    """BuildingDef.height (game px) for a kit building cut from its canvas: the visible art's
    height at the kit scale, so every kit door is the same size next to the hero."""
    a = np.asarray(Image.open(path).convert("RGBA"))
    if a[..., 3].min() == 255:  # an uncut canvas: everything that isn't magenta
        rgb = a[..., :3].astype(int)
        solid = np.abs(rgb - np.array(MAGENTA)).sum(2) > 90
    else:
        solid = a[..., 3] > 16
    rows = np.flatnonzero(solid.any(1))
    h = rows[-1] - rows[0] + 1 if len(rows) else 0
    return round(h / KIT_ART_PX * TEXEL, 1)


def last_word(name):
    return name.split()[-1].lower() if name.split() else ""


def taken_names():
    """{last word of every NPC display name: [where]} on main and every fetched branch."""
    out = {}
    refs = ["HEAD"] + subprocess.run(["git", "for-each-ref", "--format=%(refname:short)", "refs/remotes"],
                                     cwd=ROOT, capture_output=True, text=True).stdout.split()
    for ref in refs:
        res = subprocess.run(["git", "grep", "-h", "^display_name = ", ref, "--", "data/npcs"],
                             cwd=ROOT, capture_output=True, text=True)
        for line in res.stdout.splitlines():
            name = line.split("=", 1)[1].strip().strip('"')
            out.setdefault(last_word(name), set()).add("%s (%s)" % (name, ref))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("canvases")
    e = sub.add_parser("entries")
    e.add_argument("town")
    e.add_argument("--pilot", action="store_true")
    e.add_argument("--write", action="store_true")
    h = sub.add_parser("height")
    h.add_argument("png")
    n = sub.add_parser("names")
    n.add_argument("names", nargs="+")
    args = ap.parse_args()
    if args.cmd == "canvases":
        write_canvases()
    elif args.cmd == "entries":
        try:
            entries = kit_entries(load_card(args.town), all_cards(), args.pilot)
        except ValueError as err:
            sys.exit(str(err))
        if args.write:
            for x in write_entries(entries):
                print("added", x["id"])
        else:
            print(json.dumps(entries, indent=1, ensure_ascii=False))
    elif args.cmd == "height":
        print("height = %.1f  (art_px %.3f)" % (building_height(args.png), KIT_ART_PX))
    elif args.cmd == "names":
        taken = taken_names()
        clash = False
        for name in args.names:
            where = sorted(taken.get(last_word(name), []))
            clash |= bool(where)
            print("%-20s %s" % (name, "taken: " + ", ".join(where) if where else "free"))
        sys.exit(1 if clash else 0)


if __name__ == "__main__":
    main()
