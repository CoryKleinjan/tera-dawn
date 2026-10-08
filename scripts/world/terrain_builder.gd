class_name TerrainBuilder
extends RefCounted
## Builds the ground of a map: textured 3D blocks for the floor and each platform, the
## painted rocky front of every floating platform, and grass along the front edges.

## The ground textures repeat every this many 3D units (128 texels = 4 units = 128 px).
const TILE_UNITS := 4.0

var stage: TDStage
var root: Node3D

func _init(s: TDStage, r: Node3D) -> void:
	stage = s
	root = r

func build(map: MapDef, platforms: Array[Platform]) -> void:
	var biome := map.biome
	_build_blocks(map, platforms, biome)
	for i in range(1, platforms.size()):
		_platform_front(platforms[i], biome)
	_edge_grass(map, platforms, biome)

# ---------- blocks ----------

func _build_blocks(map: MapDef, platforms: Array[Platform], biome: BiomeDef) -> void:
	var sts: Array[SurfaceTool] = []
	for i in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
	var w := float(map.width) / TDStage.PX
	var h := float(map.height) / TDStage.PX
	for pl in platforms:
		var top := -pl.y / TDStage.PX
		if pl.solid:
			_block(sts, -40.0, w + 40.0, top, -h - 20.0, TDStage.GROUND_BACK, TDStage.GROUND_FRONT)
		else:
			_block(sts, pl.x / TDStage.PX, (pl.x + pl.w) / TDStage.PX, top, top - TDStage.PLAT_THICK,
				TDStage.PLAT_BACK, TDStage.PLAT_FRONT)
	var mesh := ArrayMesh.new()
	var textures := [biome.ground_top, biome.ground_side, biome.ground_soil]
	for i in 3:
		sts[i].generate_tangents()
		sts[i].commit(mesh)
		mesh.surface_set_material(i, _tile_material(textures[i]))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)

func _tile_material(texture: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 1.0
	return m

func _quad(st: SurfaceTool, pts: Array, uvs: Array, n: Vector3) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])

## A block of earth: grass on top, a band of cliff face under the top edge, soil below.
## sts: [top, side, soil] surface tools.
func _block(sts: Array[SurfaceTool], x0: float, x1: float, y_top: float, y_bot: float, z0: float, z1: float) -> void:
	var t := TILE_UNITS
	_quad(sts[0], [Vector3(x0, y_top, z0), Vector3(x1, y_top, z0), Vector3(x1, y_top, z1), Vector3(x0, y_top, z1)],
		[Vector2(x0, z0) / t, Vector2(x1, z0) / t, Vector2(x1, z1) / t, Vector2(x0, z1) / t], Vector3.UP)
	var lip_bot := maxf(y_bot, y_top - 4.0)
	for face in [[z1, Vector3.BACK], [z0, Vector3.FORWARD]]:
		var z: float = face[0]
		var a := x0 if face[1] == Vector3.BACK else x1
		var b := x1 if face[1] == Vector3.BACK else x0
		_quad(sts[1], [Vector3(a, y_top, z), Vector3(b, y_top, z), Vector3(b, lip_bot, z), Vector3(a, lip_bot, z)],
			[Vector2(a / t, 0), Vector2(b / t, 0), Vector2(b / t, (y_top - lip_bot) / t), Vector2(a / t, (y_top - lip_bot) / t)], face[1])
		if lip_bot > y_bot:
			_quad(sts[2], [Vector3(a, lip_bot, z), Vector3(b, lip_bot, z), Vector3(b, y_bot, z), Vector3(a, y_bot, z)],
				[Vector2(a, lip_bot) / t, Vector2(b, lip_bot) / t, Vector2(b, y_bot) / t, Vector2(a, y_bot) / t], face[1])
	for end in [[x0, Vector3.LEFT, z0, z1], [x1, Vector3.RIGHT, z1, z0]]:
		var x: float = end[0]
		var za: float = end[2]
		var zb: float = end[3]
		_quad(sts[1], [Vector3(x, y_top, za), Vector3(x, y_top, zb), Vector3(x, lip_bot, zb), Vector3(x, lip_bot, za)],
			[Vector2(za / t, 0), Vector2(zb / t, 0), Vector2(zb / t, (y_top - lip_bot) / t), Vector2(za / t, (y_top - lip_bot) / t)], end[1])
		if lip_bot > y_bot:
			_quad(sts[2], [Vector3(x, lip_bot, za), Vector3(x, lip_bot, zb), Vector3(x, y_bot, zb), Vector3(x, y_bot, za)],
				[Vector2(za, lip_bot) / t, Vector2(zb, lip_bot) / t, Vector2(zb, y_bot) / t, Vector2(za, y_bot) / t], end[1])
	_quad(sts[2], [Vector3(x0, y_bot, z1), Vector3(x1, y_bot, z1), Vector3(x1, y_bot, z0), Vector3(x0, y_bot, z0)],
		[Vector2(x0, z1) / t, Vector2(x1, z1) / t, Vector2(x1, z0) / t, Vector2(x0, z0) / t], Vector3.DOWN)

# ---------- painted platform fronts ----------

## Lines up the biome's left end, repeating middle and right end along a platform's front,
## so floating platforms look like the tileset's grassy rock ledges.
func _platform_front(pl: Platform, biome: BiomeDef) -> void:
	if biome.platform_middle == null:
		return
	var texel := biome.platform_texel
	var z := TDStage.PLAT_FRONT + 0.04
	var left := biome.platform_left
	var right := biome.platform_right
	var mid := biome.platform_middle
	var lw := left.get_width() * texel
	var rw := right.get_width() * texel
	var mw := mid.get_width() * texel
	var x0 := pl.x - 8.0
	var x1 := pl.x + pl.w + 8.0
	# middle pieces first (behind the ends), overlapping a little so the seams hide in the grass
	var x := x0 + lw * 0.6
	var n := 0
	while x < x1 - rw * 0.6:
		var s := _front_piece(mid, Vector2(x + mw / 2.0, pl.y), texel, z - 0.005 * (n % 2))
		s.flip_h = n % 2 == 1
		x += mw * 0.8
		n += 1
	_front_piece(left, Vector2(x0 + lw / 2.0, pl.y), texel, z + 0.01)
	_front_piece(right, Vector2(x1 - rw / 2.0, pl.y), texel, z + 0.01)

## A platform-front sprite hung from the platform's top edge (its grass rises a little above it).
func _front_piece(tex: Texture2D, top_center: Vector2, texel: float, z: float) -> Sprite3D:
	var s := TDStage.sprite(tex, texel)
	s.offset = Vector2(0, -tex.get_height() / 2.0)  # origin at the top centre
	s.position = TDStage.to3d(top_center + Vector2(0, -9.0 * texel), z)  # the grass tips rise above the edge
	root.add_child(s)
	return s

# ---------- grass along the edges ----------

func _edge_grass(map: MapDef, platforms: Array[Platform], biome: BiomeDef) -> void:
	if biome.edge_grass.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map.id) + 7
	var x := -300.0
	while x < map.width + 300.0:
		_grass(biome, rng, Vector2(x, map.ground_y), TDStage.GROUND_FRONT - 0.05)
		x += rng.randf_range(40.0, 70.0)
	for i in range(1, platforms.size()):
		var pl := platforms[i]
		x = pl.x + 20.0
		while x < pl.x + pl.w - 20.0:
			if rng.randf() < 0.5:
				_grass(biome, rng, Vector2(x, pl.y), rng.randf_range(TDStage.PLAT_BACK + 0.3, -0.8))
			x += rng.randf_range(50.0, 90.0)

func _grass(biome: BiomeDef, rng: RandomNumberGenerator, at: Vector2, z: float) -> void:
	var tex: Texture2D = biome.edge_grass[rng.randi() % biome.edge_grass.size()]
	var s := TDStage.sprite(tex, rng.randf_range(0.8, 1.05))
	s.position = TDStage.to3d(at + Vector2(0, 4), z)
	s.flip_h = rng.randf() < 0.5
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)
