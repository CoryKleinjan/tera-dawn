#!/usr/bin/env python3
"""Lay every PNG in a folder on one image over a checkerboard, for checking cut-outs.

    python3 tools/art/contact_sheet.py assets/sprites/monsters out.png [zoom]
"""
import os
import sys

from PIL import Image, ImageDraw


def main():
    folder, out = sys.argv[1], sys.argv[2]
    zoom = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    ims = [(f, Image.open(os.path.join(folder, f)).convert("RGBA")) for f in sorted(os.listdir(folder)) if f.endswith(".png")]
    pad, width = 12, 1600
    x = y = pad
    row_h = 0
    places = []
    for name, im in ims:
        im = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
        if x + im.width > width and x > pad:
            x, y = pad, y + row_h + pad + 14
            row_h = 0
        places.append((name, im, x, y))
        x += im.width + pad
        row_h = max(row_h, im.height)
    sheet = Image.new("RGBA", (width, y + row_h + pad + 14), (0, 0, 0, 255))
    d = ImageDraw.Draw(sheet)
    for yy in range(0, sheet.height, 8):
        for xx in range(0, width, 8):
            if (xx // 8 + yy // 8) % 2:
                d.rectangle([xx, yy, xx + 7, yy + 7], fill=(70, 90, 70, 255))
            else:
                d.rectangle([xx, yy, xx + 7, yy + 7], fill=(110, 130, 110, 255))
    for name, im, x, y in places:
        sheet.alpha_composite(im, (x, y))
        d.text((x, y + im.height + 1), name[:-4][:22], fill=(255, 255, 255, 255))
    sheet.convert("RGB").save(out)


if __name__ == "__main__":
    main()
