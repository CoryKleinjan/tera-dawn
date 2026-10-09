#!/usr/bin/env python3
"""Build the hero's layers from the part 2 paperdoll sheets.

The hero is drawn in layers: a bald, faceless body (assets/sprites/characters/hero.png, cut
by the paperdoll_body manifest), with hair, a face and worn gear on top. The hair, face,
cape and shield sheets draw each piece once (or once per pose) in its own cell, not where it
sits on every frame, so this tool finds the head, neck and hands in each body frame and
places the pieces there, writing one strip per layer that lines up frame for frame with
the body. The game plays a layer in step with the body (Paperdoll, PaperdollSprite).

    python3 tools/art/slice_sheets.py paperdoll_body   # the body strip first
    python3 tools/art/paperdoll_layers.py              # then the layers, mask and rig
    python3 tools/art/paperdoll_layers.py --preview    # also art/build/paperdoll_preview.png

Writes:
- assets/sprites/characters/hero_regions.png: the body strip's twin. Red channel = region
  id * 16 (Paperdoll.Region): skin, top (the chest a worn top covers), bottom (the shorts),
  shoes (the feet a worn pair covers). Alpha copies the body's.
- assets/sprites/characters/hero_rig.json: per frame, where the head, face, neck, hand and
  shield are (frame pixels), and whether the frame is seen from behind; plus each weapon's
  grip point.
- assets/sprites/characters/layers/*.png and assets/animations/paperdoll/*.tres: hair (front,
  back, under a hat) per hairstyle, face and eyes per face, cape (behind, and in front for
  back views), round and kite shields.
- assets/sprites/characters/weapons/<kind>.png: held weapons, pointing right, greyscale.

Hair, cape, shields and weapons are greyscale; the game tints them (hair colour, the worn
item's colour). The irises are split off the faces into their own layer for the eye colour.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import slice_sheets as ss  # noqa: E402

ROOT = ss.ROOT
CHAR = os.path.join(ROOT, "assets", "sprites", "characters")
STRIP = os.path.join(CHAR, "hero.png")
MASK = os.path.join(CHAR, "hero_regions.png")
RIG = os.path.join(CHAR, "hero_rig.json")
LAYERS = os.path.join(CHAR, "layers")
WEAPONS = os.path.join(CHAR, "weapons")
ANIMS = os.path.join(ROOT, "assets", "animations", "paperdoll")
BODY_MANIFEST = os.path.join(ss.SHEETS, "paperdoll_body.json")
PREVIEW = os.path.join(ROOT, "art", "build", "paperdoll_preview.png")

# Must match Paperdoll.Region in scripts/components/paperdoll.gd.
REGIONS = ["none", "hair", "skin", "eyes", "top", "bottom", "shoes", "cape", "weapon", "shield", "gloves"]
R = {name: i for i, name in enumerate(REGIONS)}
# The colour the hair art is shown in when no hair colour is picked (the hero's chestnut).
DEFAULT_HAIR = (0.55, 0.33, 0.2)
# And the irises (the painted hero's blue).
DEFAULT_EYES = (0.25, 0.42, 0.75)
# Greyscale art's middle grey is brightened to this (of 255); see lift().
LIFT_TO = 200

# Frames seen from behind: no face, the hair's "from behind" piece, the cape in front.
BACK_VIEW = ("rope1", "rope2", "ladder1", "ladder2", "climb_idle")
# The face's expression per frame (anything not listed: normal).
EXPRESSIONS = {"idle3": "blink", "hit": "ouch", "hurt": "ouch", "faint1": "dizzy", "faint2": "dizzy"}
HAIRSTYLES = ["tousled", "long", "ponytail", "twin_tails", "bun", "crest"]
FACES = ["bright", "determined", "rosy", "freckled", "cheeky"]
WEAPON_KINDS = ["sword", "bow", "wand", "staff", "claw", "knuckle", "gun"]

# Sizes against the head's radius r (measured on the body).
HAIR_WIDTH = 2.3      # a hairstyle's front piece is this wide
HAIR_LIFT = 0.12      # and starts this far above the scalp
FACE_WIDTH = 1.1      # the face (eyes to mouth) is this wide
FACE_AT = (0.2, 0.3)  # and centred this far forward and down from the head's centre
NECK = 0.95           # the neck is this far below the head's centre
SHIELD_HEIGHT = 1.25
SWORD_LENGTH = 1.9    # every weapon is drawn at the scale that makes the sword this long
WEAPON_LENGTH = 20    # rig "tip" is this far from "grip" along the weapon (only its direction matters)

# Where the weapon hand and shield are, and how the head is tilted, per frame: placed by hand,
# since the hands are hard to tell apart from the rest of the body.
HAND_RIG = os.path.join(ss.SHEETS, "paperdoll_rig.json")


# ---------- reading the body ----------

def frame_names():
    with open(BODY_MANIFEST) as f:
        spec = json.load(f)["sets"]["hero"]
    return list(spec["frames"]), spec


def distance_inside(mask):
    """Chessboard distance from each pixel of `mask` to the nearest pixel outside it."""
    d = np.zeros(mask.shape, int)
    cur = mask.copy()
    while cur.any():
        d += cur
        shrunk = cur.copy()
        shrunk[1:] &= cur[:-1]
        shrunk[:-1] &= cur[1:]
        shrunk[:, 1:] &= cur[:, :-1]
        shrunk[:, :-1] &= cur[:, 1:]
        cur = shrunk
    return d


def analyse(px):
    """The head, body axis and regions of one body frame (RGBA uint8 array)."""
    a = px[..., 3] > 127
    rgb = px[..., :3].astype(float) / 255
    mx, mn = rgb.max(2), rgb.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-3), 0)
    grey = a & (sat < 0.16) & (mx > 0.18) & (mx < 0.75)
    dark = a & (mx < 0.22)
    dist = distance_inside(a)
    r = dist.max()
    ys, xs = np.nonzero(dist >= r * 0.8)
    head = np.array([xs.mean(), ys.mean()])
    gy, gx = np.nonzero(grey)
    hips = np.array([gx.mean(), gy.mean()]) if len(gx) else head + [0, 2.5 * r]
    up = head - hips
    up /= max(np.linalg.norm(up), 1e-3)
    down = -up
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    along = (xx - head[0]) * down[0] + (yy - head[1]) * down[1]
    side = (xx - head[0]) * -down[1] + (yy - head[1]) * down[0]
    skin = a & ~grey & ~dark
    region = np.zeros(a.shape, np.uint8)
    region[skin] = R["skin"]
    region[grey] = R["bottom"]
    neck = r * NECK
    shorts_top = along[grey].min() if grey.any() else neck + 1.5 * r
    shorts_bottom = along[grey].max() if grey.any() else shorts_top + r
    feet = along[a].max()
    chest = skin & (along > neck) & (along < shorts_top + 2) & (np.abs(side) < r * 0.62)
    region[chest] = R["top"]
    soles = skin & (along > shorts_bottom + (feet - shorts_bottom) * 0.62)
    region[soles] = R["shoes"]
    return {"r": float(r), "head": head, "up": up, "region": region,
            "neck": head + down * neck, "feet_y": float(np.nonzero(a)[0].max()), "top_y": float(np.nonzero(a)[0].min())}


# ---------- placing pieces ----------

def scaled(piece_img, s):
    """A piece (PIL RGBA, sheet pixels) shrunk to game pixels."""
    arr = np.asarray(piece_img).astype(float) / 255
    rgb, alpha = ss.shrink(arr[..., :3], arr[..., 3], s)
    out = np.zeros(alpha.shape + (4,), np.uint8)
    out[..., :3] = (rgb * 255).round()
    out[..., 3] = ((alpha > 0.5) * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def place(canvas, img, anchor, at, angle=0.0):
    """Draws `img` on `canvas` with its point `anchor` on `at`, turned by `angle` degrees
    (clockwise on screen)."""
    if abs(angle) >= 0.5:
        pad = int(max(img.size) * 1.5)
        big = Image.new("RGBA", (pad * 2, pad * 2))
        big.paste(img, (int(round(pad - anchor[0])), int(round(pad - anchor[1]))))
        img = big.rotate(-angle, resample=Image.NEAREST, center=(pad, pad))
        anchor = (pad, pad)
    _paste(canvas, img, int(round(at[0] - anchor[0])), int(round(at[1] - anchor[1])))


def _paste(canvas, img, x, y):
    """alpha_composite that clips at the canvas edges."""
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(canvas.width, x + img.width), min(canvas.height, y + img.height)
    if x1 <= x0 or y1 <= y0:
        return
    canvas.alpha_composite(img.crop((x0 - x, y0 - y, x1 - x, y1 - y)), (x0, y0))


class Piece:
    """A cut piece and where its cell's origin is, in sheet pixels."""
    def __init__(self, sprite):
        self.img = sprite["image"]
        self.x, self.y = sprite["x"], sprite["y"]


def cut(manifest):
    sprites = {}
    ss.process(os.path.join(ss.SHEETS, manifest + ".json"), sprites=sprites)
    return {k.split(":", 1)[1]: Piece(v) for k, v in sprites.items()}


# ---------- weapons ----------

def weapon(piece, s):
    """A weapon shrunk to game pixels, its green grip dot painted over; returns (image, grip)."""
    arr = np.asarray(piece.img).astype(int)
    green = (arr[..., 1] > 170) & (arr[..., 0] < 120) & (arr[..., 2] < 120) & (arr[..., 3] > 0)
    gy, gx = np.nonzero(green)
    grip = (gx.mean(), gy.mean()) if len(gx) else (arr.shape[1] * 0.15, arr.shape[0] / 2)
    if len(gx):
        solid = (arr[..., 3] > 0) & ~green
        fill = arr[solid][:, :3].mean(0)
        near = ss.dilate(green, 2) & solid
        if near.any():
            fill = arr[near][:, :3].mean(0)
        arr[ss.dilate(green, 1) & (arr[..., 3] > 0), :3] = fill
        grey = arr[..., :3].mean(2, keepdims=True)  # the dot's surroundings are grey already
        arr[..., :3] = np.where(ss.dilate(green, 1)[..., None], grey, arr[..., :3])
    img = scaled(Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA"), s)
    return img, [round(grip[0] * s, 1), round(grip[1] * s, 1)]


# ---------- writing ----------

def lift(img):
    """Brightens greyscale art so its middle grey is near white: the game tints it by
    multiplying with a colour (Sprite3D/CanvasItem modulate), which then comes out close to
    that colour, with the art's shading."""
    arr = np.asarray(img).astype(float)
    solid = arr[..., 3] > 0
    if solid.any():
        mid = max(np.median(arr[solid][:, :3].mean(1)), 1)
        arr[..., :3] = (arr[..., :3] * LIFT_TO / mid).clip(0, 255)
    return Image.fromarray(arr.round().astype(np.uint8), "RGBA")


def save_layer(name, frames, fw, fh, index, anims, tinted=True):
    os.makedirs(LAYERS, exist_ok=True)
    os.makedirs(ANIMS, exist_ok=True)
    strip = Image.new("RGBA", (fw * len(frames), fh))
    for i, im in enumerate(frames):
        strip.alpha_composite(im, (i * fw, 0))
    if tinted:
        strip = lift(strip)
    png = os.path.join(LAYERS, name + ".png")
    strip.save(png)
    ss.write_sprite_frames(os.path.join(ANIMS, name + ".tres"), "res://" + os.path.relpath(png, ROOT),
                           fw, fh, index, anims)


def turned(v, angle):
    """A vector turned clockwise on screen by `angle` degrees."""
    a = math.radians(angle)
    return np.array([v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a)])


def main():
    names, spec = frame_names()
    index = {n: i for i, n in enumerate(names)}
    anims = spec["animations"]
    strip = Image.open(STRIP).convert("RGBA")
    fw, fh = strip.width // len(names), strip.height
    frames = [np.asarray(strip.crop((i * fw, 0, (i + 1) * fw, fh))) for i in range(len(names))]
    info = [analyse(f) for f in frames]
    with open(HAND_RIG) as f:
        hands = json.load(f)["frames"]
    missing = [n for n in names if n not in hands]
    if missing:
        sys.exit(f"{os.path.relpath(HAND_RIG, ROOT)} has no entry for {missing}")
    for n, fi in zip(names, info):
        fi["tilt"] = float(hands[n].get("head_tilt", 0))
    ref = info[0]  # idle1: pieces are sized against this frame
    r = ref["r"]

    hair, faces, layers, weapons = cut("paperdoll_hair"), cut("paperdoll_faces"), cut("paperdoll_layers"), cut("paperdoll_weapons")
    blank = lambda: Image.new("RGBA", (fw, fh))  # noqa: E731

    # hair: one transform per style from its front piece, used for all four pieces
    for style in HAIRSTYLES:
        front = hair[style + "_front"]
        s = r * HAIR_WIDTH / front.img.width
        head_cell = (front.x + front.img.width / 2, front.y + (r * (1 + HAIR_LIFT)) / s)
        out = {"": [], "_back": [], "_hat": []}
        for n, fi in zip(names, info):
            back_view = n in BACK_VIEW
            pieces = {"": "_behind" if back_view else "_front", "_back": None if back_view else "_back",
                      "_hat": "_behind" if back_view else "_hat"}
            for layer, which in pieces.items():
                canvas = blank()
                p = hair.get(style + which) if which else None
                if p:
                    img = scaled(p.img, s)
                    anchor = ((head_cell[0] - p.x) * s, (head_cell[1] - p.y) * s)
                    place(canvas, img, anchor, fi["head"], fi["tilt"])
                out[layer].append(canvas)
        for layer, fr in out.items():
            if any(im.getbbox() for im in fr):
                save_layer(f"hair_{style}{layer}", fr, fw, fh, index, anims)

    # faces: the irises (drawn in greys) go on their own layer for the eye colour
    for face in FACES:
        normal = faces[face + "_normal"]
        s = r * FACE_WIDTH / normal.img.width
        centre = (normal.x + normal.img.width / 2, normal.y + normal.img.height / 2)
        out, eyes = [], []
        for n, fi in zip(names, info):
            canvas, iris = blank(), blank()
            if n not in BACK_VIEW:
                p = faces[face + "_" + EXPRESSIONS.get(n, "normal")]
                img = scaled(p.img, s)
                anchor = ((centre[0] - p.x) * s, (centre[1] - p.y) * s)
                at = fi["head"] + turned(FACE_AT, fi["tilt"]) * fi["r"]
                place(canvas, img, anchor, at, fi["tilt"])
                px = np.asarray(canvas).copy()
                rgb = px[..., :3].astype(float) / 255
                mx, mn = rgb.max(2), rgb.min(2)
                grey = (px[..., 3] > 0) & (mx - mn < 0.1) & (mx > 0.28) & (mx < 0.8)
                ip = np.zeros_like(px)
                ip[grey] = px[grey]
                px[grey] = 0
                canvas, iris = Image.fromarray(px, "RGBA"), Image.fromarray(ip, "RGBA")
            out.append(canvas)
            eyes.append(iris)
        save_layer(f"face_{face}", out, fw, fh, index, anims, tinted=False)
        save_layer(f"face_{face}_eyes", eyes, fw, fh, index, anims)

    # the rig: the head, face and neck found on the body, the hands placed by hand
    rig_frames = []
    for n, fi in zip(names, info):
        h = hands[n]
        r2 = lambda v: [round(float(c), 1) for c in v]  # noqa: E731
        entry = {"name": n, "back": n in BACK_VIEW,
                 "head": r2(fi["head"]),
                 "head_top": r2(fi["head"] + turned((0, -fi["r"]), fi["tilt"])),
                 "head_angle": fi["tilt"],
                 "head_size": [round(fi["r"] * 2), round(fi["r"] * 2)],
                 "neck": r2(fi["neck"]),
                 "feet": [round(float(fi["head"][0]), 1), fi["feet_y"]]}
        if "weapon" in h:
            x, y, angle = h["weapon"]
            entry["grip"] = [x, y]
            entry["tip"] = r2(np.array([x, y]) + turned((WEAPON_LENGTH, 0), angle))
        if "shield" in h:
            entry["shield"] = list(h["shield"])
        if n not in BACK_VIEW:
            entry["face"] = entry["head"]
        rig_frames.append(entry)

    # cape: behind the body, except in back views where it hangs over the back
    cape0 = layers["cape_idle1"]
    s_cape = (ref["feet_y"] - ref["neck"][1]) * 0.7 / cape0.img.height
    behind, front = [], []
    for n, fi in zip(names, info):
        canvas = blank()
        p = layers.get("cape_" + n)
        if p:
            img = scaled(p.img, s_cape)
            a = np.asarray(img)[..., 3] > 0
            ys, xs = np.nonzero(a[: max(2, img.height // 6)])
            anchor = (xs.mean() if len(xs) else img.width / 2, 1)
            place(canvas, img, anchor, fi["neck"] - fi["up"] * fi["r"] * 0.15)
        (front if n in BACK_VIEW else behind).append(canvas)
        (behind if n in BACK_VIEW else front).append(blank())
    save_layer("cape", behind, fw, fh, index, anims)
    save_layer("cape_back_view", front, fw, fh, index, anims)

    # shields, on the arm (or on the back in back views)
    for style in ("round", "kite"):
        s_sh = r * SHIELD_HEIGHT / layers[f"{style}_idle1"].img.height
        out = []
        for n, entry in zip(names, rig_frames):
            canvas = blank()
            p = layers.get(f"{style}_{n}")
            if p and "shield" in entry:
                img = scaled(p.img, s_sh)
                place(canvas, img, (img.width / 2, img.height / 2), entry["shield"])
            out.append(canvas)
        save_layer(f"shield_{style}", out, fw, fh, index, anims)

    # weapons
    os.makedirs(WEAPONS, exist_ok=True)
    s_w = r * SWORD_LENGTH / weapons["sword"].img.width
    grips = {}
    for kind in WEAPON_KINDS:
        img, grip = weapon(weapons[kind], s_w)
        lift(img).save(os.path.join(WEAPONS, kind + ".png"))
        grips[kind] = grip

    # the region mask and the rig
    mask = Image.new("RGBA", strip.size)
    colours = [[1, 1, 1] for _ in REGIONS]
    sums = {k: [] for k in ("skin", "bottom")}
    for i, (px, fi) in enumerate(zip(frames, info)):
        m = np.zeros(px.shape, np.uint8)
        m[..., 0] = fi["region"] * 16
        m[..., 3] = px[..., 3]
        mask.paste(Image.fromarray(m, "RGBA"), (i * fw, 0))
        for k in sums:
            sel = fi["region"] == R[k]
            if sel.any():
                sums[k].append(px[sel][:, :3].mean(0) / 255)
    skin = np.median(sums["skin"], 0).round(3).tolist()
    for k in ("skin", "top", "shoes"):
        colours[R[k]] = skin
    colours[R["bottom"]] = np.median(sums["bottom"], 0).round(3).tolist()
    colours[R["hair"]] = list(DEFAULT_HAIR)
    colours[R["eyes"]] = list(DEFAULT_EYES)
    mask.save(MASK)
    with open(RIG, "w") as f:
        json.dump({"frame_size": [fw, fh], "regions": REGIONS, "frames": rig_frames,
                   "weapons": grips, "region_colors": colours}, f, indent=1)
    print(f"{len(names)} frames of {fw}x{fh}, head radius {r:.0f}: layers in {os.path.relpath(LAYERS, ROOT)}")

    if "--preview" in sys.argv:
        preview(names, fw, fh, rig_frames)


def preview(names, fw, fh, rig_frames):
    """Every frame with long hair, a face, the cape, a shield and a sword."""
    load = lambda n: Image.open(os.path.join(LAYERS, n + ".png"))  # noqa: E731
    body = Image.open(STRIP)
    tint = lambda im, c: Image.fromarray((np.asarray(im).astype(float) * (list(c) + [1])).astype(np.uint8), "RGBA")  # noqa: E731
    stack = [tint(load("cape"), (0.8, 0.25, 0.25)), tint(load("hair_long_back"), DEFAULT_HAIR), body,
             tint(load("cape_back_view"), (0.8, 0.25, 0.25)), load("face_bright"),
             tint(load("face_bright_eyes"), (0.3, 0.6, 1.0)), tint(load("hair_long"), DEFAULT_HAIR),
             tint(load("shield_round"), (0.8, 0.7, 0.4))]
    out = Image.new("RGBA", body.size, (70, 100, 70, 255))
    for im in stack:
        out.alpha_composite(im)
    sword = Image.open(os.path.join(WEAPONS, "sword.png"))
    with open(RIG) as f:
        grip = json.load(f)["weapons"]["sword"]
    for i, e in enumerate(rig_frames):
        if "grip" in e and "tip" in e:
            ang = math.degrees(math.atan2(e["tip"][1] - e["grip"][1], e["tip"][0] - e["grip"][0]))
            place_on = Image.new("RGBA", (fw, fh))
            place(place_on, sword, grip, e["grip"], ang)
            out.alpha_composite(place_on, (i * fw, 0))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    half = len(names) // 2
    two = Image.new("RGBA", (fw * half, fh * 2))
    two.paste(out.crop((0, 0, fw * half, fh)), (0, 0))
    two.paste(out.crop((fw * half, 0, fw * len(names), fh)), (0, fh))
    two.resize((two.width * 2, two.height * 2), Image.NEAREST).save(PREVIEW)
    print(f"preview: {os.path.relpath(PREVIEW, ROOT)}")


if __name__ == "__main__":
    main()
