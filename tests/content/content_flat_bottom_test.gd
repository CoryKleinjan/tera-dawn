extends TestCase
## Everything that stands on the ground sits flush on it: its picture ends in a flat bottom
## edge, not a rounded, tapering or ragged one (Cory, 2026-10-11). The slicer squares bottoms
## off (`flat_bottom` in art/sheets manifests); this checks every piece a map stands on the
## land: buildings, background houses and scattered decor, props, lanterns and doors.

const Scan := preload("res://tests/content/content_scan.gd")

## Same rule as tools/art/slice_sheets.py flat_bottom_rows: a bottom row is still curving in
## when the row above it is this much (of the body's width) wider.
const WIDEN := 0.04
const SOLID := 0.5
## Bottom rows that may still curve in (an anti-aliased corner).
const ALLOWED_ROWS := 1

## Rows at the bottom of `tex` where its outline still curves in.
static func curving_rows(tex: Texture2D) -> int:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var widths: Array[int] = []
	var top := -1
	var bottom := -1
	for y in img.get_height():
		var n := 0
		for x in img.get_width():
			if img.get_pixel(x, y).a >= SOLID:
				n += 1
		widths.append(n)
		if n > 0:
			if top < 0:
				top = y
			bottom = y
	if bottom - top < 8:
		return 0
	var body := 0
	for y in range(maxi(top, bottom - int((bottom - top + 1) * 0.35)), bottom + 1):
		body = maxi(body, widths[y])
	var rows := 0
	while rows < bottom - top - 1 and widths[bottom - rows - 1] - widths[bottom - rows] > WIDEN * body:
		rows += 1
	return rows

## Every picture a map stands on its land, by path, with what it is.
func _ground_pieces() -> Dictionary:
	var out := {}
	for m: MapDef in Content.maps.values():
		var bi := m.biome
		for rule in bi.ground_decor + bi.town_decor + bi.platform_decor:
			for t in rule.textures:
				out[t.resource_path] = t
		for t in [bi.lantern, bi.door]:
			if t:
				out[t.resource_path] = t
		for b in m.buildings:
			if b.building and b.building.texture:
				out[b.building.texture.resource_path] = b.building.texture
		for p in m.props:
			if p.texture and p.y < 0.0:  # a prop with its own y hangs (lamps), it doesn't stand
				out[p.texture.resource_path] = p.texture
	return out

func test_ground_pieces_have_flat_bottoms() -> void:
	var pieces := _ground_pieces()
	check(pieces.size() > 100, "found the ground pieces (%d)" % pieces.size())
	for path: String in pieces:
		var rows := curving_rows(pieces[path])
		check(rows <= ALLOWED_ROWS, "%s: its bottom curves in over %d rows; give its cell \"flat_bottom\" in its art/sheets manifest" % [path, rows])
