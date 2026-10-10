extends TestCase
## TerrainBuilder: the floor is the only land with 3D depth, floating platforms are flat
## painted skins, and the floor's front grass never rises over the characters' feet.

var root: Node3D
var map: MapDef

## A 1200-wide meadow map with the floor at 600 and two floating platforms.
func before_each() -> void:
	map = MapDef.new()
	map.id = &"t_terrain"
	map.width = 1200
	map.height = 700
	map.ground_y = 600
	map.biome = load("res://data/biomes/meadow.tres")
	for p in [[100.0, 450.0, 300.0], [600.0, 300.0, 240.0]]:
		var d := PlatformDef.new()
		d.x = p[0]
		d.y = p[1]
		d.width = p[2]
		map.platforms.append(d)
	root = Node3D.new()
	TerrainBuilder.new(null, root).build(map, MapLayout.new(map).platforms)

func after_each() -> void:
	root.free()

func _meshes() -> Array:
	return root.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D)

func _sprites() -> Array:
	return root.get_children().filter(func(n: Node) -> bool: return n is Sprite3D)

func test_only_the_floor_is_a_block() -> void:
	var meshes := _meshes()
	check_eq(meshes.size(), 1, "one mesh, the floor")
	var box: AABB = meshes[0].mesh.get_aabb()
	check_near(box.end.y, -map.ground_y / TDStage.PX, "nothing built above the floor's top")

func test_platforms_are_flat_skins_at_land_front() -> void:
	var skins := _sprites().filter(func(s: Sprite3D) -> bool: return s.texture is ImageTexture)
	check_eq(skins.size(), map.platforms.size(), "each platform gets one front skin picture")
	for s: Sprite3D in skins:
		check_near(s.position.z, TDStage.LAND_FRONT, "the skin stays behind the actors")

func test_skins_are_as_wide_as_their_platform() -> void:
	var skins := _sprites().filter(func(s: Sprite3D) -> bool: return s.texture is ImageTexture)
	skins.sort_custom(func(a: Sprite3D, b: Sprite3D) -> bool: return a.position.x < b.position.x)
	for i in skins.size():
		var d := map.platforms[i]
		var s: Sprite3D = skins[i]
		var shown := s.texture.get_width() * s.pixel_size * TDStage.PX
		check_near(shown, d.width + 2.0 * PlatformSkin.OVERHANG, "platform %d's skin covers it and its overhang" % i, 1.0)
		check_near(s.position.x * TDStage.PX, d.x + d.width / 2.0, "platform %d's skin is centred on it" % i, 0.5)
		# the skin hangs from its top edge; the walking surface row lands on the platform's top
		var surface_y := -s.position.y * TDStage.PX + PlatformSkin.surface_row(map.biome) * s.pixel_size * TDStage.PX
		check_near(surface_y, d.y, "platform %d's walking surface is its top edge" % i, 0.5)

func test_land_art_shows_at_one_pixel_size() -> void:
	for s: Sprite3D in _sprites():
		var density := TDStage.art_density(s.texture)
		if density == 1.0:
			continue
		# game pixels per art pixel: the platform skins exactly TEXEL, the edge grass close to it
		var art_px := s.pixel_size * TDStage.PX * density
		check_between(art_px, TDStage.TEXEL * 0.75, TDStage.TEXEL * 1.3, "%s shows near the shared pixel size" % s.texture.resource_path)

func test_floor_grass_stops_at_the_feet_line() -> void:
	var edge := -map.ground_y / TDStage.PX
	var fringe := _sprites().filter(func(s: Sprite3D) -> bool: return s.position.z > TDStage.GROUND_FRONT)
	check(fringe.size() > 0, "the floor has a grass fringe")
	for s in fringe:
		var top: float = s.position.y + s.texture.get_height() * s.pixel_size
		check(top <= edge + TerrainBuilder.FRINGE_RISE / TDStage.PX + 0.001, "fringe tips stay below the feet")
