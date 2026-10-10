class_name PlatformSkin
extends RefCounted
## The painted front of a floating platform, built as one picture from the biome's platform
## pieces: the left cap, middles (alternating the two) and the right cap, set edge to edge
## for the platform's exact width. Neighbouring pieces overlap where they match best and swap
## over along the row-by-row path where they differ least, so no seam or rounded end shows
## inside a long platform. tools/art/platform_pieces.py gives the pieces one height and one
## walking surface row, so they line up without offsets.

## The fewest texels neighbouring pieces overlap; the swap-over path runs inside the overlap.
const OVERLAP := 10
## The most texels two pieces may overlap, when they match better further in.
const MAX_OVERLAP := 24
## A platform's skin reaches this far past each end of its walkable top, in game pixels.
const OVERHANG := 8.0

static var _cache := {}
static var _surface := {}

## Game pixels per texel of the pieces: TDStage.TEXEL per art pixel.
static func texel(biome: BiomeDef) -> float:
	return TDStage.TEXEL / TDStage.art_density(biome.platform_middle)

## The skin of a platform `width` game pixels wide (its overhang included), cached per
## biome and width.
static func texture(biome: BiomeDef, width: float) -> ImageTexture:
	var cols := maxi(1, roundi((width + 2.0 * OVERHANG) / texel(biome)))
	var key := "%s:%d" % [biome.resource_path if biome.resource_path else str(biome.get_instance_id()), cols]
	if not _cache.has(key):
		var img := compose(pieces(biome), cols)
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		tex.set_meta(&"art_density", TDStage.art_density(biome.platform_middle))
		_cache[key] = tex
	return _cache[key]

## [left cap, middles..., right cap] as images.
static func pieces(biome: BiomeDef) -> Array[Image]:
	var out: Array[Image] = []
	for t: Texture2D in [biome.platform_left, biome.platform_middle, biome.platform_middle_alt, biome.platform_right]:
		if t:
			var img := t.get_image()
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			out.append(img)
	return out

## Texel rows above the walking surface (grass, crystals): the first row at least half
## opaque is where feet go.
static func surface_row(biome: BiomeDef) -> int:
	var t := biome.platform_middle
	if not _surface.has(t):
		var img := pieces(biome)[1]
		var row := 0
		for y in img.get_height():
			var solid := 0
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					solid += 1
			if solid * 2 >= img.get_width():
				row = y
				break
		_surface[t] = row
	return _surface[t]

## The game-y span the skin covers when its walking surface is at `top`: x is its top
## edge (grass rising above), y its bottom.
static func span(biome: BiomeDef, top: float) -> Vector2:
	var t := texel(biome)
	var y0 := top - surface_row(biome) * t
	return Vector2(y0, y0 + biome.platform_middle.get_height() * t)

## The picture `cols` texels wide: the caps at the ends and middles between them.
static func compose(parts: Array[Image], cols: int) -> Image:
	var placed := layout(parts, cols)
	var h := 0
	for p in placed:
		h = maxi(h, p[0].get_height())
	var out := Image.create(cols, h, false, Image.FORMAT_RGBA8)
	for k in placed.size():
		var piece: Image = placed[k][0]
		var x: int = placed[k][1]
		if k == 0:
			out.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i.ZERO)
		else:
			var prev: Array = placed[k - 1]
			_join(out, piece, x, prev[1] + prev[0].get_width() - x)
	return out

## Where each piece goes: [image, column] pairs from left to right. Each piece overlaps the
## one before it by OVERLAP to MAX_OVERLAP texels, wherever the two match best. The last
## middle is cut from its left, so its right edge (drawn to meet the right cap) still does.
## A narrow platform gets the outer parts of the two caps.
static func layout(parts: Array[Image], cols: int) -> Array:
	var left := parts[0]
	var right := parts[-1]
	var middles := parts.slice(1, parts.size() - 1)
	if left.get_width() + right.get_width() - OVERLAP >= cols:
		var lw := mini(left.get_width(), ceili((cols + OVERLAP) / 2.0))
		var rw := mini(right.get_width(), cols + OVERLAP - lw)
		return [[left.get_region(Rect2i(0, 0, lw, left.get_height())), 0],
			[right.get_region(Rect2i(right.get_width() - rw, 0, rw, right.get_height())), cols - rw]]
	var out := [[left, 0]]
	var end := left.get_width()  # the first column after the pieces placed so far
	var r := cols - right.get_width()  # where the right cap goes
	var i := 0
	while true:
		var m: Image = middles[i % middles.size()]
		var prev: Image = out[-1][0]
		var start := r + OVERLAP - m.get_width()  # a last middle starting here meets the right cap
		var room := end - start  # how far that last middle would overlap what is placed
		if room >= OVERLAP:
			# the last middle: cut `cut` columns off its left where it overlaps best
			var cut := room - OVERLAP
			var cost := INF
			for c in range(maxi(0, room - MAX_OVERLAP), room - OVERLAP + 1):
				var k := _match(prev, m, room - c, c)
				if k < cost:
					cut = c
					cost = k
			out.append([m.get_region(Rect2i(cut, 0, m.get_width() - cut, m.get_height())), start + cut])
			break
		var ov := OVERLAP
		var cost := INF
		for o in range(OVERLAP, MAX_OVERLAP + 1):
			var k := _match(prev, m, o, 0)
			if k < cost:
				ov = o
				cost = k
		out.append([m, end - ov])
		end += m.get_width() - ov
		i += 1
	out.append([right, r])
	return out

## How much `prev`'s last `o` columns and `next`'s columns from `from` on differ along the
## best swap-over path between them (lower matches better).
static func _match(prev: Image, next: Image, o: int, from: int) -> float:
	var h := mini(prev.get_height(), next.get_height())
	var acc := _path_costs(prev, prev.get_width() - o, next, from, o, h)
	var best := INF
	for c in o:
		best = minf(best, acc[(h - 1) * o + c])
	return best

## For `h` rows of an `o` column overlap (a's columns from ax over b's from bx): the cost of
## the cheapest top-to-bottom swap-over path down to each texel, moving at most one column
## per row.
static func _path_costs(a: Image, ax: int, b: Image, bx: int, o: int, h: int) -> PackedFloat32Array:
	var acc := PackedFloat32Array()
	acc.resize(h * o)
	for y in h:
		for c in o:
			var p := a.get_pixel(ax + c, y)
			var q := b.get_pixel(bx + c, y)
			var d := Color(p.r * p.a - q.r * q.a, p.g * p.a - q.g * q.a, p.b * p.a - q.b * q.a, p.a - q.a)
			var cost := d.r * d.r + d.g * d.g + d.b * d.b + d.a * d.a
			if y > 0:
				var best := acc[(y - 1) * o + c]
				if c > 0:
					best = minf(best, acc[(y - 1) * o + c - 1])
				if c < o - 1:
					best = minf(best, acc[(y - 1) * o + c + 1])
				cost += best
			acc[y * o + c] = cost
	return acc

## Lays `piece` into `out` at column `x`. Its first `o` columns lie over what is already
## there: each row swaps from the old picture to the piece at the column on the cheapest
## top-to-bottom swap-over path.
static func _join(out: Image, piece: Image, x: int, o: int) -> void:
	o = clampi(o, 0, piece.get_width())
	var h := piece.get_height()
	var rest := Rect2i(o, 0, piece.get_width() - o, h)
	if rest.size.x > 0:
		out.blit_rect(piece, rest, Vector2i(x + o, 0))
	if o == 0:
		return
	var acc := _path_costs(out, x, piece, 0, o, h)
	var cut := 0
	for c in o:
		if acc[(h - 1) * o + c] < acc[(h - 1) * o + cut]:
			cut = c
	for y in range(h - 1, -1, -1):
		if y < h - 1:
			var best := cut
			for c in [cut - 1, cut + 1]:
				if c >= 0 and c < o and acc[y * o + c] < acc[y * o + best]:
					best = c
			cut = best
		for c in range(cut, o):
			out.set_pixel(x + c, y, piece.get_pixel(c, y))
