"""Pieces: gear that keeps its shape (weapons, shields, hats) is one picture per view, which
the game places on the hero every frame (Paperdoll.Piece), instead of a strip drawn in each
pose. A piece is assets/sprites/characters/pieces/<name>.json, next to its pictures:

    {"views": {"<view>": {"picture": "res://.../<name>_<view>.png", "anchor": [x, y]}},
     "tinted": greyscale art the game tints with the item's colour,
     "fist": the weapon kind whose fist mask (fist_<kind>.png) cuts his fingers over its grip,
     "frames": per body frame, null (not shown) or
        {"view": "<view>", "at": [x, y] (frame pixels), "angle": degrees clockwise,
         "scale": s, "behind": under his body, "fist": cut his fingers over it}}

The picture is drawn with its view's anchor on "at", turned by "angle" about it and grown by
"scale"."""
from .common import *  # noqa: F401,F403

PIECES = os.path.join(CHAR, "pieces")


def pose(view, at, angle=0.0, scale=1.0, behind=False, fist=False):
    """One frame of a piece (see the module docstring)."""
    r1 = lambda v: round(float(v), 2)  # noqa: E731
    return {"view": view, "at": [r1(at[0]), r1(at[1])], "angle": r1(angle), "scale": round(float(scale), 4),
            "behind": bool(behind), "fist": bool(fist)}


def save_piece(name, views, frames, tinted=False, fist=None):
    """Writes a piece: `views` {view: (PIL picture, anchor)}, `frames` one pose() or None per
    body frame."""
    os.makedirs(PIECES, exist_ok=True)
    out = {"views": {}, "tinted": bool(tinted), "fist": fist, "frames": frames}
    saved = {}  # views showing the same picture share its file
    for view, (img, anchor) in views.items():
        png = saved.get(id(img)) or os.path.join(PIECES, f"{name}_{view}.png")
        if id(img) not in saved:
            (lift(img) if tinted else img).save(png)
            saved[id(img)] = png
        out["views"][view] = {"picture": "res://" + os.path.relpath(png, ROOT),
                              "anchor": [round(float(anchor[0]), 2), round(float(anchor[1]), 2)]}
    with open(os.path.join(PIECES, name + ".json"), "w") as f:
        json.dump(out, f, separators=(",", ":"))


def save_fist(kind, masks, fw, fh):
    """fist_<kind>.png: per body frame, white where his fingers wrap a `kind` weapon's grip
    (masks: a bool array or None per frame); the game cuts those pixels out of the weapon."""
    os.makedirs(PIECES, exist_ok=True)
    strip = np.zeros((fh, fw * len(masks), 4), np.uint8)
    for i, m in enumerate(masks):
        if m is not None:
            strip[:, i * fw:(i + 1) * fw][m] = 255
    Image.fromarray(strip, "RGBA").save(os.path.join(PIECES, f"fist_{kind}.png"))


def load_piece(name):
    """A piece as save_piece() wrote it, with its pictures and fist mask opened (or None)."""
    path = os.path.join(PIECES, name + ".json")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        p = json.load(f)
    for v in p["views"].values():
        v["img"] = Image.open(os.path.join(ROOT, v["picture"][len("res://"):])).convert("RGBA")
    fist = os.path.join(PIECES, f"fist_{p['fist']}.png") if p.get("fist") else None
    p["fist_img"] = np.asarray(Image.open(fist)) if fist and os.path.exists(fist) else None
    return p


def draw_piece(canvas, p, i, behind, tint=None, offset=(0, 0)):
    """Draws piece `p` (load_piece) on `canvas` as the game does for body frame `i`, if its
    pose there is on that side of the body (`behind`); `tint` multiplies it in. The frame's
    top-left is at `offset` on the canvas (a canvas bigger than a frame shows all of it)."""
    e = p["frames"][i]
    if e is None or e["behind"] != behind:
        return
    v = p["views"][e["view"]]
    img = v["img"]
    if e["scale"] != 1.0:
        img = img.resize((max(1, round(img.width * e["scale"])), max(1, round(img.height * e["scale"]))), Image.BICUBIC)
    anchor = (v["anchor"][0] * e["scale"], v["anchor"][1] * e["scale"])
    c, s = math.cos(math.radians(e["angle"])), math.sin(math.radians(e["angle"]))
    at = (e["at"][0] + offset[0], e["at"][1] + offset[1])
    m = (c, s, anchor[0] - c * at[0] - s * at[1], -s, c, anchor[1] + s * at[0] - c * at[1])
    layer = img.convert("RGBa").transform(canvas.size, Image.AFFINE, m, resample=Image.BICUBIC).convert("RGBA")
    arr = np.asarray(layer).astype(float)
    if tint is not None:
        arr[..., :3] *= np.array(tint[:3])
    if e["fist"] and p["fist_img"] is not None:
        fh, fw = p["fist_img"].shape[0], p["fist_img"].shape[1] // len(p["frames"])
        cut = np.zeros(arr.shape[:2], bool)
        sub = cut[offset[1]:offset[1] + fh, offset[0]:offset[0] + fw]
        sub |= p["fist_img"][:sub.shape[0], i * fw:i * fw + sub.shape[1], 3] > 0
        arr[cut, 3] = 0
    canvas.alpha_composite(Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA"))
