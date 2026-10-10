#!/usr/bin/env python3
"""Make the base image for a backdrop sheet that Gemini fills by editing (gemini_pass.json "edit").

    python3 tools/art/strip_template.py tools/art/templates/backdrop_strips_7.png
    (backdrop_strips_7_tall.png is the same at 1536 x 2731, which gives each strip room)

The image is the backdrop manifests' layout: 13 equal rows, 7 white strips labelled with
their layer, and flat magenta rows between them. Gemini paints inside the strips and leaves
the magenta rows alone, which keeps the gaps the slicer cuts on.
"""
import sys

from PIL import Image, ImageDraw, ImageFont

LAYERS = ["1. FAR LAYER", "2. MID LAYER", "3. NEAR LAYER", "4. CLOUDS", "5. LANDMARK",
          "6. SKY BODY", "7. MOTES"]
SIZE = (1536, 1024)  # the backdrop region of the area sheets
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def make(path, layers=LAYERS, size=SIZE):
    w, h = size
    rows = 2 * len(layers) - 1
    im = Image.new("RGB", size, (255, 0, 255))
    draw = ImageDraw.Draw(im)
    font = ImageFont.truetype(FONT, 18)
    for i, label in enumerate(layers):
        y0, y1 = h * 2 * i // rows, h * (2 * i + 1) // rows
        draw.rectangle((0, y0, w - 1, y1 - 1), fill=(255, 255, 255), outline=(40, 30, 40), width=2)
        draw.text((10, y0 + 4), label, fill=(40, 30, 40), font=font)
    im.save(path)


if __name__ == "__main__":
    make(sys.argv[1])
