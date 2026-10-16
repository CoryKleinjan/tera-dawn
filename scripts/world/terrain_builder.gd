class_name TerrainBuilder
extends RefCounted
## Builds the land of a map, all flat like a 2D game: the painted front of the floor, the
## painted front skin of every floating platform, and grass peeking over their top edges
## (outside towns: town streets have no grass).


var stage: TDStage
var root: Node3D

func _init(s: TDStage, r: Node3D) -> void:
	stage = s
	root = r

func build(map: MapDef, platforms: Array[Platform]) -> void:
	var biome := map.look()
	_build_floor(map, platforms[0], biome)
	for i in range(1, platforms.size()):
		var d := map.platforms[i - 1]
		if d.in_scenery:
			continue  # the scenery behind it is its painting
		if d.look:
			_platform_look(platforms[i], d)
		else:
			_platform_front(platforms[i], biome, d.solid)
		if d.solid:
			_solid_wall(map, i, biome)
	_edge_grass(map, platforms, biome)

## Adds a piece of land to the map. Land casts no shadows: platforms and the floor would
## otherwise throw the sun's shadow onto the scenery standing behind them.
func _add(node: GeometryInstance3D) -> void:
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)

# ---------- the floor ----------

## How far past each side of the map the floor runs, in game pixels, so no edge shows when
## the view is wider than the map.
const FLOOR_MARGIN := 1280.0
## Middle pieces in one repeat of the floor's top edge.
const FLOOR_EDGE_PIECES := 4
## How far below the walking line the floor's rock and soil start, in game pixels: inside the
## solid part of the edge picture, so its ragged underside overlaps them.
const FLOOR_FILL_TOP := 10.0
## How tall the band of rock under the floor's edge is before plain soil, in game pixels.
const FLOOR_ROCK := 128.0
## Draws a tall wall with its sides kept straight up and down on screen.
const UPRIGHT_SHADER := preload("res://shaders/upright_wall.gdshader")

## The floor is flat, like the floating platforms: its top edge is the biome's platform middle
## pieces repeated along the whole map (the walking surface row on the floor's top), and the
## biome's rock and soil textures fill below it down past the bottom of the map.
func _build_floor(map: MapDef, ground: Platform, biome: BiomeDef) -> void:
	var x0 := -FLOOR_MARGIN
	var x1 := map.width + FLOOR_MARGIN
	var fill_top := ground.y
	if biome.platform_middle:
		var tex := floor_edge(biome)
		var t := PlatformSkin.texel(biome)
		var top := PlatformSkin.span(biome, ground.y).x
		var tile := Vector2(tex.get_width(), tex.get_height()) * t
		_add(_strip("FloorEdge", tex, Rect2(x0, top, x1 - x0, tile.y), tile, TDStage.LAND_FRONT))
		fill_top = ground.y + FLOOR_FILL_TOP
	var bottom := float(map.height) + FLOOR_MARGIN
	var rock_bottom := minf(fill_top + FLOOR_ROCK, bottom)
	var z := TDStage.LAND_FRONT - 0.01
	_add(_strip("FloorRock", biome.ground_side, Rect2(x0, fill_top, x1 - x0, rock_bottom - fill_top), TDStage.art_size(biome.ground_side), z))
	_add(_strip("FloorSoil", biome.ground_soil, Rect2(x0, rock_bottom, x1 - x0, bottom - rock_bottom), TDStage.art_size(biome.ground_soil), z))

## The floor's top edge: FLOOR_EDGE_PIECES of the biome's platform middles joined like a
## platform's skin, cut so it repeats seamlessly. The first middle stands in for both caps,
## and the picture runs from a column of the first one to the same column of the last, where
## neither is blended with its neighbour, so each copy meets the next exactly.
static var _edges := {}

## Lets go of the floor edges built so far (the map's biome changed).
static func forget() -> void:
	_edges.clear()

static func floor_edge(biome: BiomeDef) -> ImageTexture:
	var key := biome.platform_middle
	if not _edges.has(key):
		var parts := PlatformSkin.pieces(biome)
		var middles := parts.slice(1, parts.size() - 1)
		var first: Image = middles[0]
		var row: Array[Image] = [first]
		row.append_array(middles.slice(1))
		row.append(first)
		row.append(first)
		var cols := first.get_width()
		for i in FLOOR_EDGE_PIECES - 1:
			cols += middles[(i + 1) % middles.size()].get_width() - PlatformSkin.OVERLAP
		cols += first.get_width() - PlatformSkin.OVERLAP
		var img := PlatformSkin.compose(row, cols)
		var period := cols - first.get_width()
		img = img.get_region(Rect2i(PlatformSkin.OVERLAP, 0, period, img.get_height()))
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		tex.set_meta(&"art_density", TDStage.art_density(biome.platform_middle))
		_edges[key] = tex
	return _edges[key]

## A flat strip facing the camera at depth z covering `rect` (game pixels), with `texture`
## repeating every `tile` game pixels across and down: lined up with the world's x (so
## neighbouring strips run on), or starting at the strip's own left edge when not `world_x`.
## An `upright` strip keeps its sides straight up and down on screen (UPRIGHT_SHADER).
func _strip(name_: String, texture: Texture2D, rect: Rect2, tile: Vector2, z: float, world_x := true, upright := false) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = rect.size / TDStage.PX
	var uv_scale := Vector2(rect.size.x / tile.x, rect.size.y / tile.y)
	var uv_offset := Vector2(rect.position.x / tile.x if world_x else 0.0, 0.0)
	if upright:
		var u := ShaderMaterial.new()
		u.shader = UPRIGHT_SHADER
		u.set_shader_parameter(&"albedo_tex", texture)
		u.set_shader_parameter(&"uv_scale", uv_scale)
		u.set_shader_parameter(&"uv_offset", uv_offset)
		u.set_shader_parameter(&"top", q.size.y / 2.0)
		q.material = u
	else:
		var m := StandardMaterial3D.new()
		m.albedo_texture = texture
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.texture_repeat = true
		m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
		m.uv1_offset = Vector3(uv_offset.x, uv_offset.y, 0.0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.roughness = 1.0
		q.material = m
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = q
	mi.position = TDStage.to3d(rect.get_center(), z)
	return mi

# ---------- painted platform fronts ----------

## A floating platform's painted front: one picture built from the biome's platform pieces
## for this platform's width (PlatformSkin), hung so its walking surface is the top edge.
func _platform_front(pl: Platform, biome: BiomeDef, square := false) -> void:
	if biome.platform_middle == null:
		return
	var tex := PlatformSkin.texture(biome, pl.w, square)
	var s := TDStage.sprite(tex)
	s.offset = Vector2(0, -tex.get_height() / 2.0)  # origin at the top centre
	var top := PlatformSkin.span(biome, pl.y).x
	s.position = TDStage.to3d(Vector2(pl.x + pl.w / 2.0, top), TDStage.LAND_FRONT)
	_add(s)

## A solid platform's wall: the floor's rock texture from just under its painted top edge
## down behind the top edge of the land it stands on, across its walkable width, with the
## biome's corner-stone columns (if it has them) down both ends.
func _solid_wall(map: MapDef, platform: int, biome: BiomeDef) -> void:
	if biome.ground_side == null:
		return
	var d := map.platforms[platform - 1]
	var top := d.y + FLOOR_FILL_TOP
	var bottom := map.surface_y(map.land_under(platform)) + FLOOR_FILL_TOP
	# the wall runs straight down from the bottom of the top edge's square end stones
	var inset := PlatformSkin.square_inset(biome)
	var x0 := d.x + inset.x
	var x1 := d.x + d.width - inset.y
	var rect := Rect2(x0, top, x1 - x0, bottom - top)
	_add(_strip("SolidWall", biome.ground_side, rect, TDStage.art_size(biome.ground_side), TDStage.LAND_FRONT - 0.01, true, true))
	# each end gets the biome's corner stones, or else the square end stones' own outline
	for right in [false, true]:
		var corner: Texture2D = biome.terrace_corner_right if right else biome.terrace_corner_left
		var out := 0.0
		if corner == null and biome.terrace_left != null and biome.terrace_right != null:
			corner = PlatformSkin.square_edge(biome, right)
			out = PlatformSkin.EDGE_OUT * PlatformSkin.texel(biome)
		if corner == null:
			continue
		var tile := TDStage.art_size(corner)
		var x := x1 - tile.x + out if right else x0 - out
		var r := Rect2(x, top, tile.x, rect.size.y)
		_add(_strip("TerraceCorner", corner, r, tile, TDStage.LAND_FRONT - 0.005, false, true))

## The game-y span a platform's painted skin covers: x is the top of its grass, y the bottom.
static func skin_span(d: PlatformDef, biome: BiomeDef) -> Vector2:
	if d.in_scenery:
		return Vector2(d.y, d.y)
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
	_add(s)

# ---------- grass along the edges ----------

## Towns have no grass: their streets keep only the land's own painted edge.
func _edge_grass(map: MapDef, platforms: Array[Platform], biome: BiomeDef) -> void:
	if map.town or biome.edge_grass.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map.id) + 7
	_grass_along(biome, rng, -300.0, map.width + 300.0, map.ground_y)
	for i in range(1, platforms.size()):
		if map.platforms[i - 1].look or map.platforms[i - 1].in_scenery:
			continue # painted land brings its own grass
		var pl := platforms[i]
		_grass_along(biome, rng, pl.x + 20.0, pl.x + pl.w - 20.0, pl.y)

## Tufts along [x0, x1] just behind the land's front skin, peeking over its top edge at y.
func _grass_along(biome: BiomeDef, rng: RandomNumberGenerator, x0: float, x1: float, y: float) -> void:
	var x := x0
	while x < x1:
		if rng.randf() < 0.5:
			_grass(biome, rng, Vector2(x, y), TDStage.land_depth(TDStage.LAND_FRONT - rng.randf_range(0.03, 0.06)))
		x += rng.randf_range(50.0, 90.0)

## A tuft of edge grass, at or a little under the land art's pixel size.
func _grass(biome: BiomeDef, rng: RandomNumberGenerator, at: Vector2, z: float) -> Sprite3D:
	var tex: Texture2D = biome.edge_grass[rng.randi() % biome.edge_grass.size()]
	var s := TDStage.sprite(tex, TDStage.TEXEL * rng.randf_range(0.8, 1.0))
	s.position = TDStage.to3d(at + Vector2(0, 4), z)
	s.flip_h = rng.randf() < 0.5
	_add(s)
	return s
