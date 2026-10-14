extends TestCase
## Everything shows one pixel size: an art pixel of a building, rope, lantern, portal,
## backdrop layer or room piece is TDStage.TEXEL game pixels on screen, like the land
## (tests/unit/terrain_builder_test.gd and tools/art/land_pixels.py check the land itself).
## Art drawn at its own density 1 would be the old, coarser cut.

const Scan := preload("res://tests/content/content_scan.gd")

## How far a piece may stray from TDStage.TEXEL game pixels per art pixel.
const ALLOWED := Vector2(0.75, 1.3)

func _near_texel(px: float, what: String) -> void:
	check_between(px, TDStage.TEXEL * ALLOWED.x, TDStage.TEXEL * ALLOWED.y, "%s shows near the shared pixel size" % what)

func _cut_for_the_shared_size(tex: Texture2D, what: String) -> void:
	check(TDStage.art_density(tex) > 1.0, "%s is cut at the land's density (%s)" % [what, tex.resource_path])

func _biomes(rooms := true) -> Array[BiomeDef]:
	var out: Array[BiomeDef] = []
	for path in Scan.files("res://data/biomes"):
		if rooms or not path.contains("/rooms/"):
			out.append(load(path))
	return out

func test_buildings_show_at_the_shared_pixel_size() -> void:
	for path in Scan.files("res://data/buildings"):
		var d: BuildingDef = load(path)
		_cut_for_the_shared_size(d.texture, String(d.id))
		_near_texel(d.texel(), String(d.id))

func test_placed_buildings_keep_it() -> void:
	for path in Scan.files("res://data/maps"):
		var m: MapDef = load(path)
		for b in m.buildings:
			if b.building:
				_near_texel(b.building.texel() * b.scale, "%s on %s" % [b.building.id, m.id])

func test_ropes_and_ladders_show_at_the_shared_pixel_size() -> void:
	for path in Scan.files("res://data/climb_styles"):
		var st: ClimbStyleDef = load(path)
		for tex in [st.top, st.middle, st.bottom]:
			if tex:
				_cut_for_the_shared_size(tex, path.get_file())
		_near_texel(st.texel, path.get_file())

func test_lanterns_and_portals_are_cut_for_the_shared_size() -> void:
	for b in _biomes(false):
		for tex in [b.lantern] + b.portal_frames:
			if tex:
				_cut_for_the_shared_size(tex, b.resource_path.get_file())

func test_backdrops_show_at_the_shared_pixel_size() -> void:
	# backdrop layers (a room's back wall too) are cut to the size they show at, depth taken into account
	for b in _biomes():
		for layer in b.backdrop:
			for tex in layer.textures:
				_cut_for_the_shared_size(tex, b.resource_path.get_file())
			_near_texel(layer.texel, "a backdrop layer of %s" % b.resource_path.get_file())

func test_rooms_are_cut_for_the_shared_size() -> void:
	for path in Scan.files("res://data/biomes/rooms"):
		var b: BiomeDef = load(path)
		for tex in [b.ground_side, b.ground_soil, b.door]:
			_cut_for_the_shared_size(tex, path.get_file())
	for path in Scan.files("res://data/maps/rooms"):
		var m: MapDef = load(path)
		for p in m.props:
			_cut_for_the_shared_size(p.texture, String(m.id))
