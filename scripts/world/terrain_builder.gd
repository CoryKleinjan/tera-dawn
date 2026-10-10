class_name TerrainBuilder
extends RefCounted
## Builds the ground of a map: the textured 3D block of the floor, the painted front skin of
## every floating platform (flat, with no 3D block behind it), and grass along the edges.


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
	var textures := [biome.ground_top, biome.ground_side, biome.ground_soil]
	var ts: Array[float] = []
	for tex: Texture2D in textures:
		ts.append(TDStage.art_size(tex).x / TDStage.PX)
	_block(sts, ts, -40.0, w + 40.0, -ground.y / TDStage.PX, -h - 20.0, TDStage.GROUND_BACK, TDStage.GROUND_FRONT)
	var mesh := ArrayMesh.new()
	for i in 3:
		sts[i].generate_tangents()
		sts[i].commit(mesh)
		mesh.surface_set_material(i, _top_material(biome) if i == 0 else _tile_material(textures[i]))
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	mi.mesh = mesh
	root.add_child(mi)

func _tile_material(texture: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 1.0
	return m

static var _clouds: NoiseTexture2D

## The floor's top, with cloud shadows drifting over it when the biome has them.
func _top_material(biome: BiomeDef) -> ShaderMaterial:
	if _clouds == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.012
		noise.fractal_octaves = 3
		_clouds = NoiseTexture2D.new()
		_clouds.width = 256
		_clouds.height = 256
		_clouds.seamless = true
		_clouds.noise = noise
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ground.gdshader")
	m.set_shader_parameter(&"albedo_tex", biome.ground_top)
	m.set_shader_parameter(&"clouds", _clouds)
	m.set_shader_parameter(&"cloud_strength", 0.22 if biome.cloud_shadows else 0.0)
	return m

func _quad(st: SurfaceTool, pts: Array, uvs: Array, n: Vector3) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])

## A block of earth: grass on top, a band of cliff face under the top edge, soil below.
## sts: [top, side, soil] surface tools.
## ts: how many 3D units each surface's texture covers before it repeats.
func _block(sts: Array[SurfaceTool], ts: Array[float], x0: float, x1: float, y_top: float, y_bot: float, z0: float, z1: float) -> void:
	var t := ts[0]
	_quad(sts[0], [Vector3(x0, y_top, z0), Vector3(x1, y_top, z0), Vector3(x1, y_top, z1), Vector3(x0, y_top, z1)],
		[Vector2(x0, z0) / t, Vector2(x1, z0) / t, Vector2(x1, z1) / t, Vector2(x0, z1) / t], Vector3.UP)
	var lip_bot := maxf(y_bot, y_top - 4.0)
	var side := ts[1]
	var soil := ts[2]
	for face in [[z1, Vector3.BACK], [z0, Vector3.FORWARD]]:
		var z: float = face[0]
		var a := x0 if face[1] == Vector3.BACK else x1
		var b := x1 if face[1] == Vector3.BACK else x0
		_quad(sts[1], [Vector3(a, y_top, z), Vector3(b, y_top, z), Vector3(b, lip_bot, z), Vector3(a, lip_bot, z)],
			[Vector2(a / side, 0), Vector2(b / side, 0), Vector2(b / side, (y_top - lip_bot) / side), Vector2(a / side, (y_top - lip_bot) / side)], face[1])
		if lip_bot > y_bot:
			_quad(sts[2], [Vector3(a, lip_bot, z), Vector3(b, lip_bot, z), Vector3(b, y_bot, z), Vector3(a, y_bot, z)],
				[Vector2(a, lip_bot) / soil, Vector2(b, lip_bot) / soil, Vector2(b, y_bot) / soil, Vector2(a, y_bot) / soil], face[1])
	for end in [[x0, Vector3.LEFT, z0, z1], [x1, Vector3.RIGHT, z1, z0]]:
		var x: float = end[0]
		var za: float = end[2]
		var zb: float = end[3]
		_quad(sts[1], [Vector3(x, y_top, za), Vector3(x, y_top, zb), Vector3(x, lip_bot, zb), Vector3(x, lip_bot, za)],
			[Vector2(za / side, 0), Vector2(zb / side, 0), Vector2(zb / side, (y_top - lip_bot) / side), Vector2(za / side, (y_top - lip_bot) / side)], end[1])
		if lip_bot > y_bot:
			_quad(sts[2], [Vector3(x, lip_bot, za), Vector3(x, lip_bot, zb), Vector3(x, y_bot, zb), Vector3(x, y_bot, za)],
				[Vector2(za, lip_bot) / soil, Vector2(zb, lip_bot) / soil, Vector2(zb, y_bot) / soil, Vector2(za, y_bot) / soil], end[1])
	_quad(sts[2], [Vector3(x0, y_bot, z1), Vector3(x1, y_bot, z1), Vector3(x1, y_bot, z0), Vector3(x0, y_bot, z0)],
		[Vector2(x0, z1) / soil, Vector2(x1, z1) / soil, Vector2(x1, z0) / soil, Vector2(x0, z0) / soil], Vector3.DOWN)

# ---------- painted platform fronts ----------

## A floating platform's painted front: one picture built from the biome's platform pieces
## for this platform's width (PlatformSkin), hung so its walking surface is the top edge.
func _platform_front(pl: Platform, biome: BiomeDef) -> void:
	if biome.platform_middle == null:
		return
	var tex := PlatformSkin.texture(biome, pl.w)
	var s := TDStage.sprite(tex)
	s.offset = Vector2(0, -tex.get_height() / 2.0)  # origin at the top centre
	var top := PlatformSkin.span(biome, pl.y).x
	s.position = TDStage.to3d(Vector2(pl.x + pl.w / 2.0, top), TDStage.LAND_FRONT)
	root.add_child(s)

## The game-y span a platform's painted skin covers: x is the top of its grass, y the bottom.
static func skin_span(d: PlatformDef, biome: BiomeDef) -> Vector2:
	if d.look:
		var top := d.y - d.look_grass()
		return Vector2(top, top + d.look.get_height() * d.look_texel())
	if biome == null or biome.platform_middle == null:
		return Vector2(d.y, d.y)
	return PlatformSkin.span(biome, d.y)

## A platform drawn as one painted piece of land, hung so its grass rises above the top edge.
func _platform_look(pl: Platform, d: PlatformDef) -> void:
	var texel := d.look_texel()
	var s := TDStage.sprite(d.look, texel * TDStage.art_density(d.look))
	s.offset = Vector2(0, -d.look.get_height() / 2.0)  # origin at the top centre
	s.position = TDStage.to3d(Vector2(pl.x + pl.w / 2.0, pl.y - d.look_grass()), TDStage.LAND_FRONT)
	root.add_child(s)

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
				_grass(biome, rng, Vector2(x, pl.y), TDStage.land_depth(TDStage.LAND_FRONT - rng.randf_range(0.03, 0.06)))
			x += rng.randf_range(50.0, 90.0)

## A tuft of edge grass, at or a little under the land art's pixel size.
func _grass(biome: BiomeDef, rng: RandomNumberGenerator, at: Vector2, z: float) -> Sprite3D:
	var tex: Texture2D = biome.edge_grass[rng.randi() % biome.edge_grass.size()]
	var s := TDStage.sprite(tex, TDStage.TEXEL * rng.randf_range(0.8, 1.0))
	s.position = TDStage.to3d(at + Vector2(0, 4), z)
	s.flip_h = rng.randf() < 0.5
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)
	return s
