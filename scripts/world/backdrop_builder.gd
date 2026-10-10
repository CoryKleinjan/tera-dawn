class_name BackdropBuilder
extends RefCounted
## Builds the parallax backdrop from the biome's BackdropLayerDefs: painted strips of
## mountains and trees standing far behind the play area (real 3D depth does the parallax),
## and loose pieces such as clouds and the sun scattered across the sky.

var stage: TDStage
var root: Node3D
var drifting: Array[Sprite3D] = []

func _init(s: TDStage, r: Node3D) -> void:
	stage = s
	root = r

func build(map: MapDef, rng: RandomNumberGenerator) -> void:
	var lowest := _lowest_strip(map)
	for layer in map.biome.backdrop:
		if layer.textures.is_empty():
			continue
		if layer.mode == BackdropLayerDef.Mode.STRIP:
			_strip(map, layer, layer == lowest)
		else:
			_scatter(map, layer, rng)

## The strip whose bottom edge shows lowest on screen: the land is flat, so nothing hides
## that edge, and only this strip gets a skirt below it (any other strip's bottom is in front
## of it or hidden behind it).
func _lowest_strip(map: MapDef) -> BackdropLayerDef:
	var lowest: BackdropLayerDef = null
	var best := -INF
	for layer in map.biome.backdrop:
		if layer.textures.is_empty() or layer.mode != BackdropLayerDef.Mode.STRIP:
			continue
		var z := -layer.depth
		var tex: Texture2D = layer.textures[0]
		var bottom := stage.screen_height(layer.screen_top.x, z) - tex.get_height() * _pixel_size(layer, tex, z)
		var frac := stage.screen_frac(bottom, z)
		if frac > best:
			best = frac
			lowest = layer
	return lowest

## Moves drifting pieces (clouds) and wraps them around.
func drift(delta: float) -> void:
	for s in drifting:
		s.position.x += delta * float(s.get_meta("speed"))
		if s.position.x > float(s.get_meta("x1")):
			s.position.x = float(s.get_meta("x0"))

## Texel size in 3D units for `tex` at depth z, so its art pixels show `layer.texel` game
## pixels on screen.
func _pixel_size(layer: BackdropLayerDef, tex: Texture2D, z: float) -> float:
	var r := stage.dist - z
	return layer.texel / TDStage.art_density(tex) / TDStage.PX * r / stage.dist

## The x range a layer at depth z must cover so it fills the view from either end of the map.
func _span(map: MapDef, z: float) -> Vector2:
	var r := stage.dist - z
	var half_view := TDWorld.world_view().x / TDStage.PX / 2.0 * r / stage.dist
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
## A `skirted` strip also continues below its bottom edge (see _skirt).
func _strip(map: MapDef, layer: BackdropLayerDef, skirted: bool) -> void:
	var z := -layer.depth
	var tex: Texture2D = layer.textures[0]
	var size := _pixel_size(layer, tex, z)
	var w := tex.get_width() * size
	var span := _span(map, z)
	var top := stage.screen_height(layer.screen_top.x, z)
	var bottom := top - tex.get_height() * size
	# a skirt runs on down from the strip's bottom edge, fading to a blur by SKIRT_FADE_TO and
	# holding that blur on past the bottom of the view, behind the floor
	var skirt := _skirt(tex) if skirted else null
	var fade_h := bottom - stage.screen_height(SKIRT_FADE_TO, z)
	var hold_h := stage.screen_height(SKIRT_FADE_TO, z) - stage.screen_height(SKIRT_TO, z)
	var x := span.x
	var i := 0
	while x < span.y:
		var s := _make(tex, layer, size)
		s.position = Vector3(x + w / 2.0, top, z)
		s.flip_h = i % 2 == 1
		if skirt and fade_h > 0.0:
			var fade := _make(skirt, layer, size)
			fade.scale.y = fade_h / (SKIRT_ROWS * size)
			fade.position = Vector3(x + w / 2.0, bottom + size * 0.5, z)
			fade.flip_h = s.flip_h
			var hold := _make(skirt, layer, size)
			hold.region_enabled = true
			hold.region_rect = Rect2(0, SKIRT_ROWS - 1, skirt.get_width(), 1)
			hold.offset = Vector2(0, -0.5)  # origin at the top centre
			hold.scale.y = hold_h / size + 1.0
			hold.position = Vector3(x + w / 2.0, bottom - fade_h + size * 0.5, z)
			hold.flip_h = s.flip_h
		x += w - size  # overlap one texel
		i += 1

## How far down the screen (as a fraction of its height, with the camera mid-map) a strip's
## skirt has faded to a full blur, and how far it reaches: well past the bottom, so it covers
## every camera height.
const SKIRT_FADE_TO := 0.9
const SKIRT_TO := 2.0
## How far across (texels each way) a skirt's colours are blurred at its bottom: enough that
## its streaks read as haze.
const SKIRT_BLUR := 32
## Rows in a skirt's picture: it goes from the strip's own bottom row to fully blurred.
const SKIRT_ROWS := 16
static var _skirts := {}

## A picture continuing `tex` below its bottom edge: its first row is the strip's last row,
## and each row below is blurred across a little more, so the strip seems to fade on down
## instead of ending in a hard line.
static func _skirt(tex: Texture2D) -> ImageTexture:
	if not _skirts.has(tex):
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		# running sums of the bottom row, for box blurs of any width
		var sums: Array[Color] = [Color(0, 0, 0, 0)]
		for x in w:
			sums.append(sums[-1] + img.get_pixel(x, h - 1))
		var out := Image.create(w, SKIRT_ROWS, false, Image.FORMAT_RGBA8)
		for y in SKIRT_ROWS:
			var r := roundi(SKIRT_BLUR * float(y) / (SKIRT_ROWS - 1))
			for x in w:
				var x0 := maxi(0, x - r)
				var x1 := mini(w, x + r + 1)
				var c: Color = (sums[x1] - sums[x0]) / float(x1 - x0)
				c.a = 1.0
				out.set_pixel(x, y, c)
		_skirts[tex] = ImageTexture.create_from_image(out)
	return _skirts[tex]

func _scatter(map: MapDef, layer: BackdropLayerDef, rng: RandomNumberGenerator) -> void:
	for i in layer.count:
		var z := -layer.depth - i * 3.0
		var tex: Texture2D = layer.textures[i % layer.textures.size()]
		var size := _pixel_size(layer, tex, z) * rng.randf_range(0.85, 1.15)
		var span := _span(map, z)
		var s := _make(tex, layer, size)
		var x := rng.randf_range(span.x, span.y) if layer.count > 1 else (span.x + span.y) / 2.0
		s.position = Vector3(x, stage.screen_height(rng.randf_range(layer.screen_top.x, layer.screen_top.y), z), z)
		s.flip_h = rng.randf() < 0.5
		if layer.drift > 0.0:
			s.set_meta("speed", layer.drift * rng.randf_range(0.6, 1.4))
			s.set_meta("x0", span.x - tex.get_width() * size)
			s.set_meta("x1", span.y + tex.get_width() * size)
			drifting.append(s)
