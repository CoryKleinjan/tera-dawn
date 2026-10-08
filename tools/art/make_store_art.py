#!/usr/bin/env python3
"""Cut the three key-art panels out of art/source/key_art.png and size them for Steam.

The sheet has a wide landscape panel (top left), a long banner (bottom left) and a
tall portrait panel (right) on a white background. Each panel is saved at full size
in store/source/, then cropped (never stretched) to each Steam capsule's aspect ratio
and resized in store/. Capsules still need the Tera Dawn logo added before upload:
Steam requires the game's name to be legible on every capsule.

    python3 tools/art/make_store_art.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "art", "source", "key_art.png")
OUT = os.path.join(ROOT, "store")

# capsule name: (panel, width, height, horizontal focus 0..1)
CAPSULES = {
    "header_capsule": ("landscape", 920, 430, 0.62),
    "main_capsule": ("landscape", 1232, 706, 0.6),
    "small_capsule": ("banner", 462, 174, 0.5),
    "vertical_capsule": ("portrait", 748, 896, 0.5),
    "library_capsule": ("portrait", 600, 900, 0.5),
    "library_hero": ("banner", 1920, 620, 0.5),
}


def panels(im):
    """Bounding boxes of the non-white panels, found from the white gutters between them."""
    a = np.asarray(im.convert("RGB")).astype(int)
    art = a.min(2) < 235
    boxes = []
    seen = np.zeros_like(art)
    h, w = art.shape
    for y in range(0, h, 8):
        for x in range(0, w, 8):
            if art[y, x] and not seen[y, x]:
                # grow a rectangle while its edges still touch art
                x0, x1, y0, y1 = x, x, y, y
                grown = True
                while grown:
                    grown = False
                    if x0 > 0 and art[y0:y1 + 1, x0 - 1].mean() > 0.5:
                        x0 -= 1; grown = True
                    if x1 < w - 1 and art[y0:y1 + 1, x1 + 1].mean() > 0.5:
                        x1 += 1; grown = True
                    if y0 > 0 and art[y0 - 1, x0:x1 + 1].mean() > 0.5:
                        y0 -= 1; grown = True
                    if y1 < h - 1 and art[y1 + 1, x0:x1 + 1].mean() > 0.5:
                        y1 += 1; grown = True
                seen[y0:y1 + 1, x0:x1 + 1] = True
                if (x1 - x0) > 200 and (y1 - y0) > 200:
                    boxes.append((x0 + 2, y0 + 2, x1 - 1, y1 - 1))
    named = {}
    for b in boxes:
        bw, bh = b[2] - b[0], b[3] - b[1]
        if bh > bw:
            named["portrait"] = b
        elif bw > bh * 2.4:
            named["banner"] = b
        else:
            named["landscape"] = b
    return named


def fit(im, w, h, focus):
    """Crops to the target aspect ratio around `focus`, then resizes."""
    sw, sh = im.size
    if sw / sh > w / h:
        cw = round(sh * w / h)
        x0 = round((sw - cw) * focus)
        im = im.crop((x0, 0, x0 + cw, sh))
    else:
        ch = round(sw * h / w)
        y0 = round((sh - ch) * 0.5)
        im = im.crop((0, y0, sw, y0 + ch))
    return im.resize((w, h), Image.LANCZOS)


def main():
    im = Image.open(SRC).convert("RGB")
    found = panels(im)
    os.makedirs(os.path.join(OUT, "source"), exist_ok=True)
    crops = {}
    for name, box in found.items():
        crops[name] = im.crop(box)
        crops[name].save(os.path.join(OUT, "source", f"key_art_{name}.png"))
        print(f"panel {name}: {crops[name].size}")
    for cap, (panel, w, h, focus) in CAPSULES.items():
        src = crops[panel]
        out = fit(src, w, h, focus)
        out.save(os.path.join(OUT, f"{cap}.png"))
        scale = max(w / src.size[0], h / src.size[1])
        note = f" (upscaled x{scale:.2f}: regenerate larger before launch)" if scale > 1.05 else ""
        print(f"{cap}: {w}x{h} from {panel}{note}")


if __name__ == "__main__":
    main()
