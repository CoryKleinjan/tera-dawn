extends TestCase
## TerrainBuilder: all land is flat, like a 2D game. The floor is a painted front with the
## platforms' grass edge on its walking line, floating platforms are flat painted skins, and
## land scenery stands in a thin layer just behind them, in order and at its authored size.

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

func test_the_floor_is_flat() -> void:
	var meshes := _meshes()
	check(meshes.size() > 0, "the floor is built")
	for mi: MeshInstance3D in meshes:
		check(mi.mesh is QuadMesh, "%s is one flat quad facing the camera" % mi.name)
		check(mi.position.z <= TDStage.LAND_FRONT + 0.001, "%s stays behind the actors" % mi.name)
		check_eq(mi.rotation, Vector3.ZERO, "%s is not tipped back into the scene" % mi.name)

func test_floor_edge_walking_row_is_the_ground() -> void:
	var edge: MeshInstance3D = root.get_node("FloorEdge")
	var q := edge.mesh as QuadMesh
	var top := -(edge.position.y + q.size.y / 2.0) * TDStage.PX
	var t := PlatformSkin.texel(map.biome)
	check_near(top + PlatformSkin.surface_row(map.biome) * t, map.ground_y, "the floor's walking surface is the ground line", 0.5)
	var tex := TerrainBuilder.floor_edge(map.biome)
	check_eq(tex.get_height(), map.biome.platform_middle.get_height(), "the floor's edge is as tall as a platform's")
	check_near(q.size.y * TDStage.PX, tex.get_height() * t, "and drawn at the platforms' pixel size", 0.01)

func test_floor_edge_repeats_seamlessly() -> void:
	# the picture starts and ends inside an unblended copy of the first middle, so its last
	# column is followed (in the next copy) by the first middle's column right after it
	var img := TerrainBuilder.floor_edge(map.biome).get_image()
	var first := PlatformSkin.pieces(map.biome)[1]
	for y in img.get_height():
		check_eq(img.get_pixel(0, y), first.get_pixel(PlatformSkin.OVERLAP, y), "row %d starts on the first middle" % y)

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

func test_grass_stays_behind_the_land() -> void:
	var grass := _sprites().filter(func(s: Sprite3D) -> bool: return not s.texture is ImageTexture)
	check(grass.size() > 0, "the land has grass")
	for s: Sprite3D in grass:
		check(s.position.z < TDStage.LAND_FRONT, "grass peeks over the land from behind")

func test_towns_have_no_grass() -> void:
	root.free()
	map.town = true
	root = Node3D.new()
	TerrainBuilder.new(null, root).build(map, MapLayout.new(map).platforms)
	var grass := _sprites().filter(func(s: Sprite3D) -> bool: return not s.texture is ImageTexture)
	check_eq(grass.size(), 0, "a town's floor and platforms grow no grass tufts")
	check_eq(_sprites().size(), map.platforms.size(), "its platforms still get their skins")

func test_land_depth_keeps_order_in_a_thin_layer() -> void:
	var prev := INF
	for z in [TDStage.LAND_FRONT, 0.0, -0.5, -2.0, -4.0, -8.8, -TDStage.SCENERY_DEEP]:
		var d := TDStage.land_depth(z)
		check(d < TDStage.LAND_FRONT, "depth %.1f stays behind the land's front" % z)
		check(d >= -TDStage.SCENERY_LAYER - 0.001, "depth %.1f stays in the thin layer" % z)
		check(d <= prev, "depth %.1f keeps its order" % z)
		prev = d

func test_scenery_keeps_its_size_and_tucks_in() -> void:
	var tex: Texture2D = map.biome.edge_grass[0]
	var s := TDStage.sprite(tex)
	var authored := s.pixel_size
	TDStage.stand_on_land(s, Vector2(100, map.ground_y), -8.0)
	var cam_z := cos(deg_to_rad(TDStage.PITCH)) * TDStage.view_distance()
	var shown := s.pixel_size / (cam_z - s.position.z)
	check_near(shown, authored / (cam_z + 8.0), "shows as big as it would 8 units back", 0.000001)
	check(s.position.y < -map.ground_y / TDStage.PX, "its base sinks behind the grass edge")
	s.free()

func test_portals_stand_in_front_of_the_land_behind_everyone() -> void:
	check(TDStage.Z_PORTAL > TDStage.LAND_FRONT, "portals stand in front of the land and scenery")
	for z in [TDStage.Z_CLIMBABLE, TDStage.Z_NPC, TDStage.Z_MONSTER, TDStage.Z_DROP, TDStage.Z_OTHER_PLAYER, TDStage.Z_PLAYER]:
		check(TDStage.Z_PORTAL < z, "portals stand behind what you can touch (%.2f)" % z)
