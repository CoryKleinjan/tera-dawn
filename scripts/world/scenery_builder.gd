class_name SceneryBuilder
extends RefCounted
## Builds everything that stands on the ground: the biome's scattered trees, bushes and
## rocks, the map's buildings and hand-placed props, ropes and ladders, portals and doors,
## lanterns and the sign.

## How much bigger than the biome's art the signpost is drawn, and its depth.
const SIGN_SCALE := 1.2
const SIGN_DEPTH := -0.9
## How far inward from the entrance portal the signpost stands, so its words read as this
## map's name rather than as where that portal goes.
const SIGN_FROM_PORTAL := 200.0
## Warm light standing in a doorway.
const DOOR_LIGHT := Color("ffc47a")
## Space between the top of the signpost (or portal) and the sign's words.
const SIGN_LABEL_GAP := 6.0
## Room the sign's words need above their bottom edge, so no platform skin runs through them.
const SIGN_LABEL_H := 22.0
## Open ground between two of a town's background houses (`town_decor`), and the least
## between one and a building's edge, in game pixels.
const BACK_HOUSE_GAP := 100.0
const BACK_HOUSE_CLEAR := 20.0

var stage: TDStage
var root: Node3D

func _init(s: TDStage, r: Node3D) -> void:
	stage = s
	root = r

func build(map: MapDef, platforms: Array[Platform], rng: RandomNumberGenerator) -> void:
	var biome := map.biome
	for rule in biome.ground_decor:
		_scatter(rule, -300.0, map.width + 300.0, map.ground_y, rng)
	if map.town:
		for rule in biome.town_decor:
			var houses := _scatter(rule, -300.0, map.width + 300.0, map.ground_y, rng) if map.buildings.is_empty() \
					else _back_houses(rule, map, rng)
			for s in houses:
				if biome.chimney_smoke and s.texture.get_height() * s.pixel_size * TDStage.PX > 90.0:
					var h := s.texture.get_height() * s.pixel_size
					var w := s.texture.get_width() * s.pixel_size
					_smoke(s.position + Vector3((0.2 if s.flip_h else -0.2) * w, h * 0.92, 0.0), biome)
	for i in range(1, platforms.size()):
		var pl := platforms[i]
		for rule in biome.platform_decor:
			_scatter(rule, pl.x + 30.0, pl.x + pl.w - 30.0, pl.y, rng)
	for p in map.props:
		_prop(p, map)
	for b in map.buildings:
		_building(b, platforms[b.platform], biome)
	for c in map.climbables:
		_climbable(c)
	for p in map.portals:
		if p.door:
			_door(p, platforms[p.platform], biome)
		else:
			_portal(p, platforms[p.platform], biome)
	_lanterns(map, biome, rng)
	_sign(map, biome)
	_flyers(map, biome, rng)

## A town's background houses: one per `back_house_slots`, all at the same size and depth
## (some slots stay empty, by the rule's `chance`).
func _back_houses(rule: DecorDef, map: MapDef, rng: RandomNumberGenerator) -> Array[Sprite3D]:
	var placed: Array[Sprite3D] = []
	var z := TDStage.land_depth((rule.depth.x + rule.depth.y) * 0.5)
	for x in back_house_slots(rule, map):
		if rng.randf() >= rule.chance:
			continue
		var tex: Texture2D = rule.textures[rng.randi() % rule.textures.size()]
		var s := TDStage.sprite(tex, rule.texel * rule.scale.y, rule.shaded)
		s.position = TDStage.to3d(Vector2(x, map.ground_y + 3.0), z)
		s.flip_h = rng.randf() < 0.5
		root.add_child(s)
		placed.append(s)
	return placed

## Where a town with buildings stands its background houses: the x of each one's middle.
## They keep `BACK_HOUSE_GAP` apart and never stand straight behind a building, so the
## street reads clearly (a town without buildings scatters them like any decor).
static func back_house_slots(rule: DecorDef, map: MapDef) -> Array[float]:
	var out: Array[float] = []
	var w := back_house_width(rule)
	if w <= 0.0:
		return out
	var half := w * 0.5
	var x := half
	while x <= map.width - half:
		var past := -INF
		for b in map.buildings:
			var span := b.span()
			if x + half + BACK_HOUSE_CLEAR > span.x and x - half - BACK_HOUSE_CLEAR < span.y:
				past = maxf(past, span.y)
		if past > -INF:
			x = past + BACK_HOUSE_CLEAR + half + 0.5
			continue
		out.append(x)
		x += w + BACK_HOUSE_GAP
	return out

## How wide a background house stands (its widest picture), in game pixels.
static func back_house_width(rule: DecorDef) -> float:
	var widest := 0.0
	for t in rule.textures:
		widest = maxf(widest, TDStage.art_size(t, rule.texel * rule.scale.y).x)
	return widest

## Drops pieces from a DecorDef along [x0, x1] on the surface at y. Returns the sprites.
func _scatter(rule: DecorDef, x0: float, x1: float, y: float, rng: RandomNumberGenerator) -> Array[Sprite3D]:
	var placed: Array[Sprite3D] = []
	if rule.textures.is_empty():
		return placed
	var x := x0 + rng.randf_range(0.0, rule.spacing.x)
	while x < x1:
		if rng.randf() < rule.chance:
			var tex: Texture2D = rule.textures[rng.randi() % rule.textures.size()]
			var s := TDStage.sprite(tex, rule.texel * rng.randf_range(rule.scale.x, rule.scale.y), rule.shaded)
			s.position = TDStage.to3d(Vector2(x, y + 3.0), rng.randf_range(TDStage.land_depth(rule.depth.x), TDStage.land_depth(rule.depth.y)))
			s.flip_h = rng.randf() < 0.5
			root.add_child(s)
			placed.append(s)
		x += rng.randf_range(rule.spacing.x, rule.spacing.y)
	return placed

## A thin column of smoke rising from a chimney at `at`.
func _smoke(at: Vector3, biome: BiomeDef) -> void:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 5.0
	p.preprocess = 5.0
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	var m := TDStage.additive_material(biome.smoke_color)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3(0.3, 1, 0)
	p.spread = 8.0
	p.gravity = Vector3(0.15, 0.25, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 1))
	p.color_ramp = fade
	p.position = at
	root.add_child(p)

## Birds crossing the sky behind the town (BiomeDef.flyers).
func _flyers(map: MapDef, biome: BiomeDef, rng: RandomNumberGenerator) -> void:
	if biome.flyers == null or biome.flyer_count <= 0:
		return
	var anim := &"move" if biome.flyers.has_animation(&"move") else &"idle"
	var span := Vector2(-400.0, map.width + 400.0) / TDStage.PX
	for i in biome.flyer_count:
		var f := TDFlyer.new()
		f.sprite_frames = biome.flyers
		TDStage.style_sprite(f, TDStage.TEXEL * rng.randf_range(0.45, 0.7))
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.span = span
		f.speed = rng.randf_range(0.8, 1.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		f.flip_h = f.speed < 0.0
		f.base_y = -(map.ground_y - rng.randf_range(260.0, 420.0)) / TDStage.PX
		f.position = Vector3(rng.randf_range(span.x, span.y), f.base_y, rng.randf_range(-16.0, -10.0))
		f.play(anim)
		f.speed_scale = rng.randf_range(0.8, 1.2)
		root.add_child(f)

func _prop(p: PropPlacement, map: MapDef) -> void:
	if p.texture == null:
		return
	var y := p.y if p.y >= 0.0 else float(map.ground_y) + 3.0
	var s := TDStage.sprite(p.texture, TDStage.TEXEL * p.scale)
	s.position = TDStage.to3d(Vector2(p.x, y), TDStage.land_depth(p.depth))
	s.flip_h = p.flip
	root.add_child(s)
	if p.light_color.a > 0.0:
		var l := TDStage.light(p.light_color, p.light_energy, 4.0)
		l.position = s.position + Vector3(0, p.light_height / TDStage.PX, 0.6)
		root.add_child(l)

## A building standing at full size just behind the walking line, its door at `b.x`.
## Sized so it shows `height` game pixels tall at the play line despite standing further back.
func _building(b: BuildingPlacement, pl: Platform, biome: BiomeDef) -> void:
	var d := b.building
	if d == null or d.texture == null:
		return
	var z := TDStage.land_depth(b.depth)
	var s := TDStage.sprite(d.texture, d.texel() * b.scale * (stage.dist - z) / stage.dist)
	s.position = TDStage.to3d(Vector2(b.center_x(), pl.y + 3.0), z)
	s.flip_h = b.flip
	s.modulate = b.tint
	root.add_child(s)
	if biome.chimney_smoke and d.chimney.x >= 0.0:
		var across := (d.chimney.x - 0.5) * (-1.0 if b.flip else 1.0)
		var size := s.texture.get_size() * s.pixel_size
		_smoke(s.position + Vector3(across * size.x, d.chimney.y * size.y, 0.0), biome)

## A door: a warm light in the doorway (a building's picture has the door itself; in a room
## the biome's door picture stands on the back wall). Up enters it like any portal.
func _door(p: PortalDef, pl: Platform, biome: BiomeDef) -> void:
	var base := Vector2(p.x, pl.y + 3.0)
	var height := 60.0
	if biome.door:
		var s := TDStage.sprite(biome.door)
		s.position = TDStage.to3d(base, TDStage.land_depth(-2.0))
		root.add_child(s)
		height = TDStage.art_size(biome.door).y
	var l := TDStage.light(DOOR_LIGHT, 1.6, 3.5)
	l.position = TDStage.to3d(base + Vector2(0, -height * 0.45), -0.8)
	root.add_child(l)

## A rope or ladder: the style's top piece, its middle piece repeated, and its bottom piece.
func _climbable(c: ClimbableDef) -> void:
	var st := c.style
	if st == null or st.middle == null:
		return
	var z := TDStage.Z_CLIMBABLE
	var texel := st.texel
	var y := c.top
	if st.top:
		var top := TDStage.sprite(st.top, texel)
		top.offset = Vector2(0, -st.top.get_height() / 2.0)
		top.position = TDStage.to3d(Vector2(c.x, y), z)
		root.add_child(top)
		y += TDStage.art_size(st.top, texel).y * 0.9
	var bottom_h := TDStage.art_size(st.bottom, texel).y if st.bottom else 0.0
	var mid_h := TDStage.art_size(st.middle, texel).y
	while y < c.bottom - bottom_h - 2.0:
		var s := TDStage.sprite(st.middle, texel)
		s.offset = Vector2(0, -st.middle.get_height() / 2.0)  # hang from the top
		s.position = TDStage.to3d(Vector2(c.x, y), z)
		# the last piece may poke past the bottom; it hides behind the bottom piece or the floor
		root.add_child(s)
		y += mid_h - texel / TDStage.art_density(st.middle)  # overlap one texel
	if st.bottom:
		var b := TDStage.sprite(st.bottom, texel)
		b.position = TDStage.to3d(Vector2(c.x, c.bottom + 2.0), z + 0.01)
		root.add_child(b)

func _portal(p: PortalDef, pl: Platform, biome: BiomeDef) -> void:
	var base := Vector2(p.x, pl.y + 4.0)
	var at := TDStage.to3d(base, -0.3)
	if not biome.portal_frames.is_empty():
		var frames := SpriteFrames.new()
		frames.set_animation_speed(&"default", 6.0)
		for t in biome.portal_frames:
			frames.add_frame(&"default", t)
		var s := AnimatedSprite3D.new()
		s.sprite_frames = frames
		TDStage.style_sprite(s, TDStage.TEXEL / TDStage.art_density(biome.portal_frames[0]), false)
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.offset = Vector2(0, biome.portal_frames[0].get_height() / 2.0)
		s.modulate = Color(1.25, 1.2, 1.3)
		s.position = at
		s.play(&"default")
		root.add_child(s)
	var l := TDStage.light(Color("b49aff"), 3.0, 7.0)
	l.position = at + Vector3(0, 1.6, 0.8)
	root.add_child(l)
	var sparks := TDStage.particles(Color(2.0, 1.6, 3.0), 30, 0.12)
	sparks.lifetime = 2.0
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.8, 0.2, 0.3)
	sparks.gravity = Vector3(0, 0.6, 0)
	sparks.initial_velocity_min = 0.2
	sparks.initial_velocity_max = 0.6
	sparks.direction = Vector3.UP
	sparks.position = at + Vector3(0, 0.3, 0.2)
	root.add_child(sparks)

func _lanterns(map: MapDef, biome: BiomeDef, rng: RandomNumberGenerator) -> void:
	if biome.lantern == null or map.lantern_spacing <= 0.0:
		return
	var x := 320.0
	while x < map.width - 120.0:
		var pos := TDStage.to3d(Vector2(x, map.ground_y + 3.0), -1.3)
		var post := TDStage.sprite(biome.lantern)
		post.position = pos
		root.add_child(post)
		# the lamp hangs off the right of the post, near the top
		var size := TDStage.art_size(biome.lantern) / TDStage.PX
		var lamp := pos + Vector3(size.x * 0.22, size.y * 0.62, 0.05)
		var g := TDStage.glow_sprite(load("res://assets/sprites/fx/glow.png"), Color(biome.lantern_light, 0.5) * 1.5)
		g.position = lamp
		root.add_child(g)
		var l := TDStage.light(biome.lantern_light, 2.2, 6.0)
		l.position = lamp + Vector3(0, 0, 0.5)
		l.set_meta(&"energy", l.light_energy)
		l.add_to_group(&"flicker")
		root.add_child(l)
		x += rng.randf_range(map.lantern_spacing * 0.85, map.lantern_spacing * 1.15)

func _sign(map: MapDef, biome: BiomeDef) -> void:
	if map.sign_text == "" or biome.signpost == null:
		return
	var post := TDStage.sprite(biome.signpost, TDStage.TEXEL * SIGN_SCALE)
	post.position = TDStage.to3d(Vector2(sign_post_x(map), map.ground_y + 3.0), SIGN_DEPTH)
	root.add_child(post)

## Where the signpost stands: SIGN_FROM_PORTAL inward from the entrance, the floor portal
## nearest the map's `sign_x` (or at `sign_x` on a map with no portal on the floor).
static func sign_post_x(map: MapDef) -> float:
	var entrance: PortalDef = null
	for p in map.portals:
		if p.platform == 0 and not p.door and (entrance == null or absf(p.x - map.sign_x) < absf(entrance.x - map.sign_x)):
			entrance = p
	if entrance == null:
		return map.sign_x
	var inward := 1.0 if entrance.x < map.width / 2.0 else -1.0
	return entrance.x + inward * SIGN_FROM_PORTAL

## Where the sign's words go (game pixels, their bottom centre), or null for no sign. The
## overlay draws them, so they stay sharp and in front: over the post, at least as high as
## the biome's portal, and above any platform skin they would otherwise sit on.
static func sign_label_at(map: MapDef) -> Variant:
	var biome := map.biome
	if map.sign_text == "" or biome == null or biome.signpost == null:
		return null
	var h := TDStage.art_size(biome.signpost, TDStage.TEXEL * SIGN_SCALE).y
	if not biome.portal_frames.is_empty():
		h = maxf(h, TDStage.art_size(biome.portal_frames[0]).y)
	var x := sign_post_x(map)
	var y := map.ground_y + 3.0 - h - SIGN_LABEL_GAP
	var moved := true
	while moved: # lifting the words over one platform can put them in the one above
		moved = false
		for d in map.platforms:
			if x < d.x or x > d.x + d.width:
				continue
			var skin := TerrainBuilder.skin_span(d, biome)
			if y > skin.x and y - SIGN_LABEL_H < skin.y:
				y = skin.x - SIGN_LABEL_GAP
				moved = true
	return Vector2(x, y)
