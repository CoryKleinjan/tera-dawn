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
	var floor_top := -map.ground_y / TDStage.PX
	var skins := 0
	for s in _sprites():
		if s.position.y > floor_top + 1.0:
			check(s.position.z <= TDStage.LAND_FRONT + 0.011, "platform pieces stay behind the actors")
			if s.position.z >= TDStage.LAND_FRONT - 0.006:
				skins += 1
	check(skins >= 4, "each platform gets its front skin")

func test_floor_grass_stops_at_the_feet_line() -> void:
	var edge := -map.ground_y / TDStage.PX
	var fringe := _sprites().filter(func(s: Sprite3D) -> bool: return s.position.z > TDStage.GROUND_FRONT)
	check(fringe.size() > 0, "the floor has a grass fringe")
	for s in fringe:
		var top: float = s.position.y + s.texture.get_height() * s.pixel_size
		check(top <= edge + TerrainBuilder.FRINGE_RISE / TDStage.PX + 0.001, "fringe tips stay below the feet")
