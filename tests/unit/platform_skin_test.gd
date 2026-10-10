extends TestCase
## PlatformSkin: a platform's front is one picture of caps and middles that runs the
## platform's full width, with no gap, rounded end or hard seam inside it.

const BIOMES := ["meadow", "greenwood", "lumewood", "harbor", "coast", "ember", "forge", "lantern"]
const WIDTHS := [140.0, 200.0, 300.0, 420.0, 1000.0]
## Texel rows under the walking surface that must hold some land in every column.
const SURFACE_BAND := 12

func _biome(id: String) -> BiomeDef:
	return load("res://data/biomes/%s.tres" % id)

func test_skin_is_exactly_as_wide_as_asked() -> void:
	for id in BIOMES:
		var parts := PlatformSkin.pieces(_biome(id))
		for cols in [60, 200, 333, 900, 1700]:
			check_eq(PlatformSkin.compose(parts, cols).get_width(), cols, "%s skin %d texels wide" % [id, cols])

func test_walking_surface_runs_unbroken_from_end_to_end() -> void:
	# a row of pieces pasted side by side shows gaps between their rounded ends; a joined
	# skin has land in every column just under its walking surface, from where the left
	# cap's land starts to where the right cap's ends
	for id in BIOMES:
		var b := _biome(id)
		var parts := PlatformSkin.pieces(b)
		var row := PlatformSkin.surface_row(b)
		for w in WIDTHS:
			var img := PlatformSkin.compose(parts, roundi((w + 2.0 * PlatformSkin.OVERHANG) / PlatformSkin.texel(b)))
			var x0 := _first_land(parts[0], row, range(parts[0].get_width()))
			var x1 := img.get_width() - parts[-1].get_width() + _first_land(parts[-1], row, range(parts[-1].get_width() - 1, -1, -1))
			var holes := []
			for x in range(x0, x1 + 1):
				if not _land(img, x, row):
					holes.append(x)
			check_eq(holes, [], "%s: a %d px platform has land under all of its surface" % [id, w])

## Whether column x has land in the SURFACE_BAND rows under the walking surface `row`.
func _land(img: Image, x: int, row: int) -> bool:
	for y in range(row, mini(row + SURFACE_BAND, img.get_height())):
		if img.get_pixel(x, y).a > 0.5:
			return true
	return false

## The first of `columns` with land under the walking surface.
func _first_land(img: Image, row: int, columns: Array) -> int:
	for x in columns:
		if _land(img, x, row):
			return x
	return columns[-1]

func test_joins_are_no_harder_than_the_art_itself() -> void:
	for id in BIOMES:
		var b := _biome(id)
		var parts := PlatformSkin.pieces(b)
		var img := PlatformSkin.compose(parts, 1600)
		var placed := PlatformSkin.layout(parts, 1600)
		# how much neighbouring columns differ, everywhere in the skin
		var diffs: Array[float] = []
		for x in range(1, img.get_width()):
			diffs.append(_column_diff(img, x))
		var sorted := diffs.duplicate()
		sorted.sort()
		var typical: float = sorted[int(sorted.size() * 0.9)]
		for k in range(1, placed.size()):
			var prev: Image = placed[k - 1][0]
			var px: int = placed[k - 1][1]
			var piece: Image = placed[k][0]
			var j: int = placed[k][1]
			# the swap-over happens somewhere in the overlap; no column in it may differ from its
			# neighbour more than the art does there (in either piece) or than the art usually does
			for x in range(j + 1, px + prev.get_width()):
				var art := maxf(typical, maxf(_column_diff(prev, x - px), _column_diff(piece, x - j)))
				check(diffs[x - 1] <= art * 1.5 + 0.02, "%s: the join at %d (column %d) is as smooth as the art (%.3f vs %.3f)" % [id, j, x, diffs[x - 1], art])

## Mean premultiplied colour difference between column x-1 and column x.
func _column_diff(img: Image, x: int) -> float:
	var sum := 0.0
	for y in img.get_height():
		var a := img.get_pixel(x - 1, y)
		var c := img.get_pixel(x, y)
		sum += absf(a.r * a.a - c.r * c.a) + absf(a.g * a.a - c.g * c.a) + absf(a.b * a.a - c.b * c.a) + absf(a.a - c.a)
	return sum / img.get_height()
