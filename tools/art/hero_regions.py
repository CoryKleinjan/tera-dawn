#!/usr/bin/env python3
"""Map out the hero strip so the game can dress the hero before layered art exists.

The hero is one painted sprite strip (assets/sprites/characters/hero.png), so his hair,
skin, tunic, boots, cape, sword and shield are baked into it. This tool works out which
pixels of every frame are which, so the game can recolour them (hair colour, skin tone,
the colour of the worn top) or hide them (no shield worn, a bow instead of the sword), and
where the head, face, hand and body are, so code-drawn stand-ins for hats, hairstyles and
weapons sit in the right place.

    python3 tools/art/hero_regions.py              # writes the mask and the rig
    python3 tools/art/hero_regions.py --preview    # also writes art/build/hero_regions_preview.png

Outputs:
- assets/sprites/characters/hero_regions.png: the strip's twin. Red channel = region id
  (see REGIONS) * 16; alpha copies the hero's.
- assets/sprites/characters/hero_rig.json: one entry per frame (anchors in frame pixels).

Once the hero is redrawn as separate layers (see the ChatGPT art prompts), this goes away.
It only uses colour and shape, so expect a stray pixel or two; it's a stand-in.
"""
import colorsys
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
STRIP = os.path.join(ROOT, "assets", "sprites", "characters", "hero.png")
MASK = os.path.join(ROOT, "assets", "sprites", "characters", "hero_regions.png")
RIG = os.path.join(ROOT, "assets", "sprites", "characters", "hero_rig.json")
PREVIEW = os.path.join(ROOT, "art", "build", "hero_regions_preview.png")
MANIFEST = os.path.join(ROOT, "art", "sheets", "hero_main.json")
FRAME_W = 132
# Frames where he faces away from the camera (no face to draw on).
BACK_VIEW = ("rope", "ladder", "climb_idle")

# Must match Paperdoll.Region in scripts/components/paperdoll.gd.
REGIONS = ["none", "hair", "skin", "eyes", "top", "bottom", "shoes", "cape", "weapon", "shield", "gloves"]
R = {name: i for i, name in enumerate(REGIONS)}
PREVIEW_COLOURS = [(40, 120, 40), (140, 70, 20), (255, 205, 170), (0, 255, 255), (0, 70, 255), (20, 20, 120),
	(90, 50, 10), (255, 0, 0), (230, 230, 230), (255, 140, 0), (200, 0, 200)]


def colour_class(r, g, b, a):
	if a < 128:
		return None
	h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
	h *= 360
	if v < 0.2:
		return "dark"
	if s < 0.18 and v > 0.45:
		return "silver"
	if (h < 12 or h > 335) and s > 0.45:
		return "red"
	if 190 <= h <= 255 and s > 0.25:
		return "blue"
	if 36 <= h <= 60 and s > 0.45 and v > 0.5:
		return "gold"
	if 12 <= h <= 42 and s < 0.5 and v > 0.68:
		return "skin"
	if 5 <= h <= 40 and s >= 0.3:
		return "brown"
	return "other"


def neighbours(x, y, w, h, eight=True):
	steps = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)) if eight else ((1, 0), (-1, 0), (0, 1), (0, -1))
	for dx, dy in steps:
		nx, ny = x + dx, y + dy
		if 0 <= nx < w and 0 <= ny < h:
			yield nx, ny


def components(cls, wanted):
	"""Connected groups of pixels whose class is in `wanted`, biggest first."""
	h, w = len(cls), len(cls[0])
	seen = [[False] * w for _ in range(h)]
	out = []
	for y in range(h):
		for x in range(w):
			if seen[y][x] or cls[y][x] not in wanted:
				continue
			group = []
			q = deque([(x, y)])
			seen[y][x] = True
			while q:
				px, py = q.popleft()
				group.append((px, py))
				for nx, ny in neighbours(px, py, w, h):
					if not seen[ny][nx] and cls[ny][nx] in wanted:
						seen[ny][nx] = True
						q.append((nx, ny))
			out.append(group)
	out.sort(key=len, reverse=True)
	return out


def bbox(points):
	xs = [p[0] for p in points]
	ys = [p[1] for p in points]
	return min(xs), min(ys), max(xs), max(ys)


def centre(points):
	return [round(sum(p[0] for p in points) / len(points), 1), round(sum(p[1] for p in points) / len(points), 1)]


def elongation(points):
	"""How long and thin a group is (1 for round), and its main direction."""
	pts = np.array(points, dtype=float)
	if len(pts) < 3:
		return 1.0, np.array([1.0, 0.0])
	cov = np.cov((pts - pts.mean(axis=0)).T)
	vals, vecs = np.linalg.eigh(cov)
	return float(np.sqrt(max(vals[1], 1e-6) / max(vals[0], 1e-6))), vecs[:, 1]


def grow(region, cls, mask, into, steps, limit=None):
	"""Spreads a region over neighbouring pixels of the classes in `into` (its outline),
	only inside the box `limit` (x0, y0, x1, y1) if one is given."""
	h, w = len(cls), len(cls[0])
	x0, y0, x1, y1 = limit if limit else (0, 0, w, h)
	edge = [(x, y) for y in range(h) for x in range(w) if mask[y][x] == region]
	for _ in range(steps):
		nxt = []
		for x, y in edge:
			for nx, ny in neighbours(x, y, w, h, eight=False):
				if mask[ny][nx] == 0 and cls[ny][nx] in into and x0 <= nx <= x1 and y0 <= ny <= y1:
					mask[ny][nx] = region
					nxt.append((nx, ny))
		edge = nxt


def frame_regions(img):
	w, h = img.size
	px = img.load()
	cls = [[colour_class(*px[x, y]) for x in range(w)] for y in range(h)]
	mask = [[0] * w for _ in range(h)]
	rig = {}
	opaque = [(x, y) for y in range(h) for x in range(w) if cls[y][x] is not None]
	if not opaque:
		return mask, rig
	feet_y = max(p[1] for p in opaque)

	def paint(points, region):
		for x, y in points:
			if mask[y][x] == 0:
				mask[y][x] = region

	# hair: the biggest brown patch
	browns = components(cls, {"brown"})
	hair = browns[0] if browns else []
	paint(hair, R["hair"])
	hx0, hy0, hx1, hy1 = bbox(hair) if hair else (0, 0, w - 1, h - 1)
	head_h = hy1 - hy0 + 1

	# skin: every skin patch (face and hands); the face is the skin touching the head
	head_box = (hx0 - 4, hy0, hx1 + 4, hy1 + int(head_h * 0.45))
	face = []
	for group in components(cls, {"skin"}):
		paint(group, R["skin"])
		gx, gy = centre(group)
		if head_box[0] <= gx <= head_box[2] and head_box[1] <= gy <= head_box[3]:
			face += group

	# the sword: the biggest long, thin patch of blade colours
	blade = []
	for group in components(cls, {"silver", "other", "skin"}):
		if len(group) < 25:
			break
		ratio, _ = elongation(group)
		if ratio > 3.0:
			blade = [p for p in group if mask[p[1]][p[0]] in (0, R["skin"])]
			break
	for x, y in blade:
		mask[y][x] = R["weapon"]

	# eyes: small blue patches in the face
	blues = components(cls, {"blue"})
	eyes = []
	if face:
		fx0, fy0, fx1, fy1 = bbox(face)
		for group in blues:
			gx, gy = centre(group)
			if len(group) <= 40 and fx0 - 2 <= gx <= fx1 + 2 and fy0 - 2 <= gy <= fy1 + 2:
				eyes += group
		paint(eyes, R["eyes"])

	# the shield: the blue patch with the most gold inside its box (the lion and the rim)
	gold = {(x, y) for y in range(h) for x in range(w) if cls[y][x] == "gold"}
	shield = []
	best = 0.0
	for group in blues:
		if len(group) < 30 or any(mask[y][x] for x, y in group[:1]):
			continue
		bx0, by0, bx1, by1 = bbox(group)
		area = (bx1 - bx0 + 1) * (by1 - by0 + 1)
		inside = sum(1 for gx, gy in gold if bx0 < gx < bx1 and by0 < gy < by1)
		# the lion sits in the middle of the shield, surrounded by blue
		fill = len(group) / area
		score = inside / area * fill
		if score > best and inside >= 8 and (bx1 - bx0) < 30 and (by1 - by0) < 36:
			best = score
			shield = group
	if shield:
		bx0, by0, bx1, by1 = bbox(shield)
		paint(shield, R["shield"])
		# the rim and the lion: everything else inside the shield's outline
		rim = [(x, y) for y in range(max(0, by0 - 3), min(h, by1 + 4)) for x in range(max(0, bx0 - 3), min(w, bx1 + 4))
			if cls[y][x] in ("gold", "brown", "dark", "other", "silver") and mask[y][x] == 0]
		paint(rim, R["shield"])

	# clothes: blue is the tunic, its darkest blue low on the body the trousers
	body_h = max(1, feet_y - hy1)
	for group in blues:
		for x, y in group:
			if mask[y][x]:
				continue
			r, g, b, _ = px[x, y]
			v = max(r, g, b) / 255
			low = y > feet_y - body_h * 0.42
			mask[y][x] = R["bottom"] if low and v < 0.42 else R["top"]
	# red: the cape and scarf, except the reddish glints in the hair
	for group in components(cls, {"red"}):
		gx, gy = centre(group)
		in_hair = hx0 <= gx <= hx1 and hy0 <= gy <= hy1 and len(group) < 40
		paint(group, R["hair"] if in_hair else R["cape"])
	# boots low down, the rest of the leather (belt, bracers) counts as gloves
	for group in browns[1:]:
		_, gy = centre(group)
		paint(group, R["shoes"] if gy > feet_y - body_h * 0.4 else R["gloves"])

	# outlines go with what they outline, so hidden gear leaves nothing behind
	for region in ("weapon", "shield", "cape"):
		grow(R[region], cls, mask, {"dark", "other", "silver", "gold"}, 2)
	# the hair's dark shadows and outline, but not the face's outline below it
	grow(R["hair"], cls, mask, {"dark", "other"}, 3, limit=(hx0 - 3, hy0 - 3, hx1 + 3, hy0 + int(head_h * 0.7)))
	grow(R["hair"], cls, mask, {"dark"}, 1)

	# anchors, in frame pixels with the origin at the top left
	rig["feet"] = [round(sum(p[0] for p in opaque) / len(opaque), 1), feet_y]
	if hair:
		rig["head_top"] = [round((hx0 + hx1) / 2, 1), hy0]
		rig["head"] = [round((hx0 + hx1) / 2, 1), round((hy0 + hy1) / 2, 1)]
		rig["head_size"] = [hx1 - hx0 + 1, head_h]
	if len(face) >= 12 and eyes:
		rig["face"] = centre(face + eyes)  # no eyes: he's facing away (climbing)
	torso = [(x, y) for y in range(h) for x in range(w) if mask[y][x] == R["top"]]
	if torso:
		rig["torso"] = centre(torso)
		tx0, ty0, tx1, ty1 = bbox(torso)
		rig["torso_size"] = [tx1 - tx0 + 1, ty1 - ty0 + 1]
	if shield:
		rig["shield"] = centre(shield)
	if blade:
		ratio, direction = elongation(blade)
		c = np.array(centre(blade))
		pts = np.array(blade, dtype=float)
		proj = (pts - c) @ direction
		a, b = c + direction * proj.min(), c + direction * proj.max()
		# the grip is the end nearer the middle of the body
		mid = np.array(rig.get("torso", rig["feet"]))
		grip, tip = (a, b) if np.linalg.norm(a - mid) < np.linalg.norm(b - mid) else (b, a)
		rig["grip"] = [round(float(grip[0]), 1), round(float(grip[1]), 1)]
		rig["tip"] = [round(float(tip[0]), 1), round(float(tip[1]), 1)]
	return mask, rig


def _typical(colours):
	if not colours:
		return [1.0, 1.0, 1.0]
	arr = np.array(colours, dtype=float) / 255.0
	lum = arr @ np.array([0.299, 0.587, 0.114])
	keep = arr[lum > 0.15]  # leave the outline out
	if len(keep) == 0:
		keep = arr
	return [round(float(v), 3) for v in np.median(keep, axis=0)]


def main():
	strip = Image.open(STRIP).convert("RGBA")
	frames = strip.width // FRAME_W
	out = Image.new("RGBA", strip.size, (0, 0, 0, 0))
	preview = Image.new("RGB", strip.size, PREVIEW_COLOURS[0])
	rig = {"frame_size": [FRAME_W, strip.height], "regions": REGIONS, "frames": []}
	alpha = strip.getchannel("A").load()
	samples = [[] for _ in REGIONS]
	o = out.load()
	p = preview.load()
	with open(MANIFEST) as f:
		names = list(json.load(f)["sets"]["hero"]["frames"].keys())
	for i in range(frames):
		mask, anchors = frame_regions(strip.crop((i * FRAME_W, 0, (i + 1) * FRAME_W, strip.height)))
		anchors["name"] = names[i] if i < len(names) else str(i)
		if anchors["name"].startswith(BACK_VIEW):
			anchors.pop("face", None)
		rig["frames"].append(anchors)
		for y in range(strip.height):
			for x in range(FRAME_W):
				sx = i * FRAME_W + x
				a = alpha[sx, y]
				if a:
					o[sx, y] = (mask[y][x] * 16, 0, 0, a)
					samples[mask[y][x]].append(strip.getpixel((sx, y))[:3])
					p[sx, y] = PREVIEW_COLOURS[mask[y][x]] if mask[y][x] else strip.getpixel((sx, y))[:3]
	# each region's typical colour: recolouring keeps every pixel's brightness relative to it
	rig["region_colors"] = [_typical(c) for c in samples]
	out.save(MASK)
	with open(RIG, "w") as f:
		json.dump(rig, f, indent=1)
	print("wrote %s and %s (%d frames)" % (os.path.relpath(MASK, ROOT), os.path.relpath(RIG, ROOT), frames))
	if "--preview" in sys.argv:
		os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
		big = preview.resize((preview.width * 2, preview.height * 2), Image.NEAREST)
		half = FRAME_W * 2 * (frames // 2)
		sheet = Image.new("RGB", (half, big.height * 2))
		sheet.paste(big.crop((0, 0, half, big.height)), (0, 0))
		sheet.paste(big.crop((half, 0, big.width, big.height)), (0, big.height))
		sheet.save(PREVIEW)
		print("wrote", os.path.relpath(PREVIEW, ROOT))


if __name__ == "__main__":
	main()
