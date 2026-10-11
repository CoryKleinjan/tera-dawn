"""The build driver: reads the body, writes every layer in turn, then the region mask and the
rig (and, with --preview, a preview sheet)."""
from .common import *  # noqa: F401,F403
from .body import body_offsets, read_hero
from .faces import face_layers
from .gloves import glove_layers
from .hair import one_piece_layers, posed_layers
from .hats import hat_layers
from .weapons import holds, weapon_layers
from .worn import cape_layers, clothes_layers, shield_layers


def main():
    """Builds every layer, then the region mask and the rig (see paperdoll_layers.py)."""
    hero = read_hero()
    names, frames, info, fw, fh, r = hero.names, hero.frames, hero.info, hero.fw, hero.fh, hero.r
    strip = hero.strip

    hair, faces, weapons = cut("paperdoll_hair"), cut("paperdoll_faces"), cut("paperdoll_weapons")
    body_offsets(names, hero.body_cells, fw, fh)  # also fills BODY_PIECES, for shorts_mask

    old, old_hat = one_piece_layers(hero, hair)
    posed_layers(hero, old, old_hat)
    face_layers(hero, faces)
    held = holds(hero.hands, hero.hold_spec, names)
    rig_frames = rig_entries(hero, held)
    cape_layers(hero)
    shield_layers(hero, rig_frames)
    hat_layers(hero)
    glove_layers(hero, rig_frames)
    clothes_layers(hero)
    grips = weapon_layers(hero, weapons, held)

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


def rig_entries(hero, held):
    """The rig's frames: the head, face and neck found on the body, the hands placed by hand
    (paperdoll_rig.json), and how each weapon kind is held (`held`, from holds())."""
    names, info, hands = hero.names, hero.info, hero.hands
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
            entry["holds"] = {k: held[k][n] for k in WEAPON_KINDS if held[k][n] is not None}
            if h.get("weapon_behind"):
                entry["weapon_behind"] = True
        if "shield" in h:
            entry["shield"] = list(h["shield"])
        if n not in BACK_VIEW:
            entry["face"] = entry["head"]
        rig_frames.append(entry)
    return rig_frames


def preview(names, fw, fh, rig_frames):
    """Every frame with each weapon kind in his hand (one row of frames per kind, split in two),
    wearing tousled hair, a face, the cape and, with the sword, a shield."""
    load = lambda n: Image.open(os.path.join(LAYERS, n + ".png"))  # noqa: E731
    have = lambda n: os.path.exists(os.path.join(LAYERS, n + ".png"))  # noqa: E731
    body = Image.open(STRIP)
    tint = lambda im, c: Image.fromarray((np.asarray(im).astype(float) * (list(c) + [1])).astype(np.uint8), "RGBA")  # noqa: E731
    steel, wood = (0.85, 0.87, 0.92), (0.75, 0.55, 0.35)
    colours = {"sword": steel, "wand": wood, "staff": wood, "bow": wood, "gun": wood, "claw": steel, "knuckle": (0.85, 0.7, 0.4)}
    rows = []
    for kind in WEAPON_KINDS:
        hair = "hair_tousled" if have("hair_tousled") else "hair_long"
        stack = [tint(load("cape"), (0.8, 0.25, 0.25))]
        if have(hair + "_back"):
            stack.append(tint(load(hair + "_back"), DEFAULT_HAIR))
        if have(f"weapon_{kind}_behind"):
            stack.append(tint(load(f"weapon_{kind}_behind"), colours[kind]))
        stack += [body, tint(load("cape_front"), (0.8, 0.25, 0.25)), load("face_bright"),
                  tint(load("face_bright_eyes"), (0.3, 0.6, 1.0)), tint(load(hair), DEFAULT_HAIR),
                  tint(load(f"weapon_{kind}"), colours[kind])]
        if kind == "sword":
            stack.append(tint(load("shield_round"), (0.8, 0.7, 0.4)))
        out = Image.new("RGBA", body.size, (70, 100, 70, 255))
        for im in stack:
            out.alpha_composite(im)
        rows.append(out)
    half = (len(names) + 1) // 2
    sheet = Image.new("RGBA", (fw * half, fh * 2 * len(rows)))
    for i, out in enumerate(rows):
        sheet.paste(out.crop((0, 0, fw * half, fh)), (0, fh * 2 * i))
        sheet.paste(out.crop((fw * half, 0, fw * len(names), fh)), (0, fh * (2 * i + 1)))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    sheet.save(PREVIEW)
    print(f"preview: {os.path.relpath(PREVIEW, ROOT)} (rows: {', '.join(WEAPON_KINDS)})")
