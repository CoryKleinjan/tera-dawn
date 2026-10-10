class_name TerrainBuilder
extends RefCounted
## Builds the ground of a map: the textured 3D block of the floor, the painted front skin of
## every floating platform (flat, with no 3D block behind it), and grass along the edges.

## The ground textures repeat every this many 3D units (128 texels = 4 units = 128 px).
const TILE_UNITS := 4.0
## How many texels of a biome platform skin's grass rise above the platform's top edge.
const SKIN_GRASS := 9.0

var stage: TDStage
var root: Node3D

func _init(s: TDStage, r: Node3D) -> void:
	stage = s
	root = r

func build(map: MapDef, platforms: Array[Platform]) -> void:
	var biome := map.biome
	_build_floor(map, platforms[0], biome)
	for i in range(1, platforms.size()):
		if map.platforms[i - 1].look:
			_platform_look(platforms[i], map.platforms[i - 1])
		else:
			_platform_front(platforms[i], biome)
	_edge_grass(map, platforms, biome)

# ---------- the floor ----------

## The floor is the only land with depth: characters stand on its top, which runs back
## into the scene. Floating platforms are just their painted front skin.
func _build_floor(map: MapDef, ground: Platform, biome: BiomeDef) -> void:
	var sts: Array[SurfaceTool] = []
	for i in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
	var w := float(map.width) / TDStage.PX
	var h := float(map.height) / TDStage.PX
	_block(sts, -40.0, w + 40.0, -ground.y / TDStage.PX, -h - 20.0, TDStage.GROUND_BACK, TDStage.GROUND_FRONT)
	var mesh := ArrayMesh.new()
	var textures := [biome.ground_top, biome.ground_side, biome.ground_soil]
	for i in 3:
		sts[i].generate_tangents()
		sts[i].commit(mesh)
		mesh.surface_set_material(i, _tile_material(textures[i]))
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
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
	var z := TDStage.LAND_FRONT
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

## The game-y span a platform's painted skin covers: x is the top of its grass, y the bottom.
static func skin_span(d: PlatformDef, biome: BiomeDef) -> Vector2:
	if d.look:
		var t := d.look_texel()
		return Vector2(d.y - PlatformDef.LOOK_GRASS * t, d.y - PlatformDef.LOOK_GRASS * t + d.look.get_height() * t)
	if biome == null or biome.platform_middle == null:
		return Vector2(d.y, d.y)
	var texel := biome.platform_texel
	var top := d.y - SKIN_GRASS * texel
	return Vector2(top, top + biome.platform_middle.get_height() * texel)

## A platform drawn as one painted piece of land, hung so its grass rises above the top edge.
func _platform_look(pl: Platform, d: PlatformDef) -> void:
	var texel := d.look_texel()
	var s := TDStage.sprite(d.look, texel)
	s.offset = Vector2(0, -d.look.get_height() / 2.0)  # origin at the top centre
	s.position = TDStage.to3d(Vector2(pl.x + pl.w / 2.0, pl.y - PlatformDef.LOOK_GRASS * texel), TDStage.LAND_FRONT)
	root.add_child(s)

## A platform-front sprite hung from the platform's top edge (its grass rises a little above it).
func _front_piece(tex: Texture2D, top_center: Vector2, texel: float, z: float) -> Sprite3D:
	var s := TDStage.sprite(tex, texel)
	s.offset = Vector2(0, -tex.get_height() / 2.0)  # origin at the top centre
	s.position = TDStage.to3d(top_center + Vector2(0, -SKIN_GRASS * texel), z)  # the grass tips rise above the edge
	root.add_child(s)
	return s

# ---------- grass along the edges ----------

## How far the floor's front-edge grass may rise above the edge, in game pixels. The edge is
## nearer the camera than the actors, so it shows a little below their feet; a short fringe
## frames the bottom of the view without hiding anyone's legs.
const FRINGE_RISE := 6.0

func _edge_grass(map: MapDef, platforms: Array[Platform], biome: BiomeDef) -> void:
	if biome.edge_grass.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map.id) + 7
	var x := -300.0
	while x < map.width + 300.0:
		# in front of the floor's front face, sunk so only the tips rise above the edge
		var s := _grass(biome, rng, Vector2(x, map.ground_y), TDStage.GROUND_FRONT + 0.05)
		var tall := s.texture.get_height() * s.pixel_size * TDStage.PX
		s.position.y -= maxf(0.0, tall - FRINGE_RISE) / TDStage.PX
		x += rng.randf_range(40.0, 70.0)
	for i in range(1, platforms.size()):
		if map.platforms[i - 1].look:
			continue # painted land brings its own grass
		var pl := platforms[i]
		x = pl.x + 20.0
		while x < pl.x + pl.w - 20.0:
			if rng.randf() < 0.5:
				# just behind the skin, peeking over its top edge
				var s := _grass(biome, rng, Vector2(x, pl.y), TDStage.land_depth(TDStage.LAND_FRONT - rng.randf_range(0.03, 0.06)))
				s.pixel_size *= 0.75
			x += rng.randf_range(50.0, 90.0)

func _grass(biome: BiomeDef, rng: RandomNumberGenerator, at: Vector2, z: float) -> Sprite3D:
	var tex: Texture2D = biome.edge_grass[rng.randi() % biome.edge_grass.size()]
	var s := TDStage.sprite(tex, rng.randf_range(0.8, 1.05))
	s.position = TDStage.to3d(at + Vector2(0, 4), z)
	s.flip_h = rng.randf() < 0.5
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)
	return s
