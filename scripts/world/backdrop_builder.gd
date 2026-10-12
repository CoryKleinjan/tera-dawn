class_name BackdropBuilder
extends RefCounted
## Builds the parallax backdrop from the biome's BackdropLayerDefs: painted strips of
## mountains and trees standing far behind the play area (real 3D depth does the parallax),
## loose pieces such as clouds and the sun scattered across the sky, and single pictures.

var stage: TDStage
var root: Node3D
var drifting: Array[Sprite3D] = []

func _init(s: TDStage, r: Node3D) -> void:
	stage = s
	root = r

func build(map: MapDef, rng: RandomNumberGenerator) -> void:
	for layer in map.look().backdrop:
		if layer.textures.is_empty():
			continue
		if layer.mode == BackdropLayerDef.Mode.STRIP:
			_strip(map, layer)
		elif layer.mode == BackdropLayerDef.Mode.PICTURE:
			_picture(map, layer)
		else:
			_scatter(map, layer, rng)

## The 3D heights of a strip or picture layer's top (x) and bottom (y) edges on `map`. The land is flat,
## so nothing hides the bottom edge of the nearest strip but the floor: its art runs on down
## as painted ground, tall enough that the edge stays behind the floor or below the view
## wherever the camera is (content_backdrop_test checks every map).
static func strip_edges(map: MapDef, layer: BackdropLayerDef) -> Vector2:
	var z := -layer.depth
	var tex: Texture2D = layer.textures[0]
	var top := TDStage.screen_height_at(layer.screen_top.x, z, TDStage.backdrop_center(map))
	return Vector2(top, top - tex.get_height() * layer_pixel_size(map, layer))

## Texel size in 3D units of a strip or picture layer's art on `map`: a picture is stretched
## to cover the whole span the view sweeps over, a strip shows at its `texel`.
static func layer_pixel_size(map: MapDef, layer: BackdropLayerDef) -> float:
	var z := -layer.depth
	var tex: Texture2D = layer.textures[0]
	var size := pixel_size(layer, tex, z)
	if layer.mode == BackdropLayerDef.Mode.PICTURE:
		var span := span_at(map, z)
		size = maxf(size, (span.y - span.x) / tex.get_width())
	return size

## Moves drifting pieces (clouds) and wraps them around.
func drift(delta: float) -> void:
	for s in drifting:
		s.position.x += delta * float(s.get_meta("speed"))
		if s.position.x > float(s.get_meta("x1")):
			s.position.x = float(s.get_meta("x0"))

## Texel size in 3D units for `tex` at depth z, so its art pixels show `layer.texel` game
## pixels on screen.
static func pixel_size(layer: BackdropLayerDef, tex: Texture2D, z: float) -> float:
	var dist := TDStage.view_distance()
	return layer.texel / TDStage.art_density(tex) / TDStage.PX * (dist - z) / dist

## The x range a layer at depth z must cover so it fills the view from either end of the map.
static func span_at(map: MapDef, z: float) -> Vector2:
	var dist := TDStage.view_distance()
	var half_view := TDWorld.world_view().x / TDStage.PX / 2.0 * (dist - z) / dist
	return Vector2(-half_view - 4.0, float(map.width) / TDStage.PX + half_view + 4.0)

func _make(tex: Texture2D, layer: BackdropLayerDef, size: float) -> Sprite3D:
	var s := TDStage.sprite(tex, 1.0, false)  # painted colours; fog still fades them with distance
	s.pixel_size = size
	s.offset = Vector2(0, -tex.get_height() / 2.0)  # origin at the top centre
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.modulate = layer.tint
	if layer.glow:
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	else:
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	root.add_child(s)
	return s

## One strip repeated across the whole span; every other copy is mirrored so the seams match.
func _strip(map: MapDef, layer: BackdropLayerDef) -> void:
	var z := -layer.depth
	var tex: Texture2D = layer.textures[0]
	var size := pixel_size(layer, tex, z)
	var w := tex.get_width() * size
	var span := span_at(map, z)
	var top := strip_edges(map, layer).x
	var x := span.x
	var i := 0
	while x < span.y:
		var s := _make(tex, layer, size)
		s.position = Vector3(x + w / 2.0, top, z)
		s.flip_h = i % 2 == 1
		x += w - size  # overlap one texel
		i += 1

## One picture centred on the span, never repeated. It paints its own distance haze, so the
## fog leaves it alone.
func _picture(map: MapDef, layer: BackdropLayerDef) -> void:
	var z := -layer.depth
	var span := span_at(map, z)
	var tex: Texture2D = layer.textures[0]
	var s := _make(tex, layer, layer_pixel_size(map, layer))
	s.position = Vector3((span.x + span.y) / 2.0, strip_edges(map, layer).x, z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	mat.albedo_texture = tex
	mat.albedo_color = layer.tint
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	s.material_override = mat

func _scatter(map: MapDef, layer: BackdropLayerDef, rng: RandomNumberGenerator) -> void:
	for i in layer.count:
		var z := -layer.depth - i * 3.0
		var tex: Texture2D = layer.textures[i % layer.textures.size()]
		var size := pixel_size(layer, tex, z) * rng.randf_range(0.85, 1.15)
		var span := span_at(map, z)
		var s := _make(tex, layer, size)
		var x := rng.randf_range(span.x, span.y) if layer.count > 1 else (span.x + span.y) / 2.0
		s.position = Vector3(x, stage.screen_height(rng.randf_range(layer.screen_top.x, layer.screen_top.y), z), z)
		s.flip_h = rng.randf() < 0.5
		if layer.drift > 0.0:
			s.set_meta("speed", layer.drift * rng.randf_range(0.6, 1.4))
			s.set_meta("x0", span.x - tex.get_width() * size)
			s.set_meta("x1", span.y + tex.get_width() * size)
			drifting.append(s)
