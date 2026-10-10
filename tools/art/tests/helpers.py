"""Shared bits for the art tool tests: the tools folder on the import path, and small
synthetic sheets drawn in code so no test reads real art or calls Gemini."""

import os
import sys

import numpy as np

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

MAGENTA = (255, 0, 255)
DIVIDER = (60, 20, 60)


def sheet(rows, cols, cell=64, line=2, sprite=(40, 120, 200), sprite_size=24, skip=()):
    """A magenta sheet of rows x cols cells split by thin dark lines, with a square sprite
    low in each cell (below the label band) except the 1-based cells in `skip`."""
    h, w = rows * cell, cols * cell
    rgb = np.zeros((h, w, 3), np.int32)
    rgb[:] = MAGENTA
    for r in range(1, rows):
        rgb[r * cell - line // 2:r * cell + (line + 1) // 2, :] = DIVIDER
    for c in range(1, cols):
        rgb[:, c * cell - line // 2:c * cell + (line + 1) // 2] = DIVIDER
    n = 0
    for r in range(rows):
        for c in range(cols):
            n += 1
            if n in skip:
                continue
            y0 = r * cell + cell - sprite_size - 8
            x0 = c * cell + (cell - sprite_size) // 2
            rgb[y0:y0 + sprite_size, x0:x0 + sprite_size] = sprite
    return rgb


def rod(angle_deg, size=80, length=60, width=4):
    """An RGBA picture of a straight rod through the centre, at `angle_deg` clockwise from
    pointing right (screen coordinates, y down)."""
    import math
    arr = np.zeros((size, size, 4), np.uint8)
    a = math.radians(angle_deg)
    cx = cy = size / 2
    for t in np.linspace(-length / 2, length / 2, length * 4):
        for o in np.linspace(-width / 2, width / 2, width * 2):
            x = cx + t * math.cos(a) - o * math.sin(a)
            y = cy + t * math.sin(a) + o * math.cos(a)
            xi, yi = int(round(x)), int(round(y))
            if 0 <= xi < size and 0 <= yi < size:
                arr[yi, xi] = (200, 200, 220, 255)
    return arr
