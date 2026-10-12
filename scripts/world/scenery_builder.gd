class_name SceneryBuilder
extends RefCounted
## Builds everything that stands on the ground: the biome's scattered trees, bushes and
## rocks (where DecorPlacement puts them), the map's buildings and hand-placed props, ropes
## and ladders, portals and doors, and lanterns.

## Warm light standing in a doorway.
const DOOR_LIGHT := Color("ffc47a")
## How much nearer a portal's light sorts than where it stands (see _portal).
const PORTAL_SORT := 50.0
## How far the middle of the portal's glowing ground patch is above the bottom of its frames
## (texels; the halo fades out below it). The patch is what stands on the land.
const PORTAL_GROUND := 19.0
## Open ground between two of a town's background houses (`town_decor`), and the least
## between one and a building's edge, in game pixels.
const BACK_HOUSE_GAP := 100.0
const BACK_HOUSE_CLEAR := 20.0

var stage: TDStage
var root: Node3D
## Where this map's lanterns stand, and the ground they keep clear (LanternPlacement).
var _lantern_xs: Array[float] = []
var _lantern_clear: Array[Vector2] = []

func _init(s: TDStage, r: Node3D) -> void:
	stage = s
	root = r

func build(map: MapDef, platforms: Array[Platform], rng: RandomNumberGenerator) -> void:
	var biome := map.look()
	_lantern_xs = LanternPlacement.slots(map)
	_lantern_clear = LanternPlacement.keep_clear(map)
	var houses: Array[Sprite3D] = []
	for piece in DecorPlacement.floor_pieces(map, rng):
		var s := _stand(piece)
		if biome.town_decor.has(piece.rule):
			houses.append(s)
	if map.town:
		for rule in biome.town_decor:
			if not map.buildings.is_empty():
				houses.append_array(_back_houses(rule, map, rng))
		for s in houses:
			if biome.chimney_smoke and s.texture.get_height() * s.pixel_size * TDStage.PX > 90.0:
				var h := s.texture.get_height() * s.pixel_size
				var w := s.texture.get_width() * s.pixel_size
				_smoke(s.position + Vector3((0.2 if s.flip_h else -0.2) * w, h * 0.92, 0.0), biome)
	for piece in DecorPlacement.platform_pieces(map, rng):
		_stand(piece)
	for p in map.props:
		_prop(p, map)
	for b in map.buildings:
		_building(b, platforms[b.platform], biome)
	for c in map.climbables:
		_climbable(c, platforms)
	for p in map.portals:
		if p.door:
			_door(p, platforms[p.platform], biome)
		else:
			_portal(p, platforms[p.platform], biome)
	_lanterns(map, biome, rng)
	_flyers(map, biome, rng)

## A town's background houses: one per `back_house_slots`, all at the same size and depth
## (some slots stay empty, by the rule's `chance`, and any a lantern stands in front of).
func _back_houses(rule: DecorDef, map: MapDef, rng: RandomNumberGenerator) -> Array[Sprite3D]:
	var placed: Array[Sprite3D] = []
	var z := (rule.depth.x + rule.depth.y) * 0.5
	var half := back_house_width(rule) * 0.5
	for x in back_house_slots(rule, map):
		if rng.randf() >= rule.chance:
			continue
		if _lantern_clear.any(func(a: Vector2) -> bool: return x + half > a.x and x - half < a.y):
			continue
		var tex: Texture2D = rule.textures[rng.randi() % rule.textures.size()]
		var s := TDStage.sprite(tex, rule.texel * rule.scale.y, rule.shaded)
		TDStage.stand_on_land(s, Vector2(x, map.ground_y + 3.0), z)
		s.flip_h = rng.randf() < 0.5
		root.add_child(s)
		placed.append(s)
	return placed

## Where a town with buildings stands its background houses: the x of each one's middle.
## They keep `BACK_HOUSE_GAP` apart and never stand straight behind a building or a raised
## terrace (`PlatformDef.solid`), so the street reads clearly (a town without buildings scatters them like any decor).
static func back_house_slots(rule: DecorDef, map: MapDef) -> Array[float]:
	var out: Array[float] = []
	var w := back_house_width(rule)
	if w <= 0.0:
		return out
	var half := w * 0.5
	var x := half
	var taken := map.solid_spans_on(0)  # raised land's wall would hide them
	for b in map.buildings:
		taken.append(b.span())
	while x <= map.width - half:
		var past := -INF
		for span in taken:
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

## Stands a piece of scattered scenery where DecorPlacement put it.
func _stand(p: DecorPlacement.Piece) -> Sprite3D:
	var s := TDStage.sprite(p.texture, p.texel, p.rule.shaded)
	TDStage.stand_on_land(s, Vector2(p.x, p.y + 3.0), p.depth)
	s.flip_h = p.flip
	root.add_child(s)
	return s

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
	if p.on_wall:
		s.position = TDStage.to3d(Vector2(p.x, y), TDStage.LAND_FRONT + 0.005)
	else:
		TDStage.stand_on_land(s, Vector2(p.x, y), p.depth)
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
	var s := building_sprite(b, pl.y)
	root.add_child(s)
	if biome.chimney_smoke and d.chimney.x >= 0.0:
		var across := (d.chimney.x - 0.5) * (-1.0 if b.flip else 1.0)
		var size := s.texture.get_size() * s.pixel_size
		_smoke(s.position + Vector3(across * size.x, d.chimney.y * size.y, 0.0), biome)

## A building's picture standing on land whose walking line is at game-y `surface`. Its base
## stands right on the walking line (sunk only by land_sink, so it never shows above the
## land's grass edge), so the land's front hides no more of it than the grass lip:
## content_backdrop_test checks no building loses its doorstep at any camera height.
static func building_sprite(b: BuildingPlacement, surface: float) -> Sprite3D:
	var d := b.building
	var z := TDStage.land_depth(b.depth)
	var dist := TDStage.view_distance()
	var s := TDStage.sprite(d.texture, d.texel() * b.scale * (dist - z) / dist)
	TDStage.stand_on_land(s, Vector2(b.center_x(), surface), b.depth, false)
	s.flip_h = b.flip
	s.modulate = b.tint
	return s

## A door: the portal standing in the doorway, so players see they can go in, and a warm
## light behind it (a building's picture has the door itself; in a room the biome's door
## picture stands on the back wall). Up enters it like any portal.
func _door(p: PortalDef, pl: Platform, biome: BiomeDef) -> void:
	var base := Vector2(p.x, pl.y + 3.0)
	_portal(p, pl, biome)
	var height := 60.0
	if biome.door:
		var s := TDStage.sprite(biome.door)
		TDStage.stand_on_land(s, base, -2.0)
		root.add_child(s)
		height = TDStage.art_size(biome.door).y
	var l := TDStage.light(DOOR_LIGHT, 1.6, 3.5)
	# in front of the doorway, so it lights the door and the land's front around it
	l.position = TDStage.to3d(base + Vector2(0, -height * 0.45), TDStage.LAND_FRONT + 0.5)
	root.add_child(l)

## A rope or ladder: its style's pieces stacked edge to edge (ClimbStyleDef.pieces). Each piece
## is drawn one texture pixel taller than its slot, so the joints never show a hairline gap; the
## next piece covers the extra row. Like characters, climbables cast no shadows.
func _climbable(c: ClimbableDef, platforms: Array[Platform]) -> void:
	var st := c.style
	if st == null:
		return
	var z := TDStage.Z_CLIMBABLE
	var flip := st.top_flipped(ClimbStyleDef.ledge_room(c.x, c.top, platforms))
	for p in st.pieces(c.top, c.bottom):
		var tex: Texture2D = p.texture
		var s := TDStage.sprite(tex, st.texel)
		var art_h := TDStage.art_size(tex, st.texel).y
		s.scale.y = (p.height + st.texel / TDStage.art_density(tex)) / art_h
		s.offset = Vector2(0, -tex.get_height() / 2.0)  # hang from the top edge
		s.position = TDStage.to3d(Vector2(c.x, p.y), z)
		s.flip_h = flip and tex == st.top
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(s)
		z += 0.001  # each piece just in front of the one above, so the joints don't flicker

## A portal: the biome's animated portal frames standing on the platform, with a light and
## sparkles rising through it. Doors get one too (see _door).
func _portal(p: PortalDef, pl: Platform, biome: BiomeDef) -> void:
	var base := Vector2(p.x, pl.y + 3.0)
	if not biome.portal_frames.is_empty():
		# the glowing patch, not the soft halo under it, stands on the land
		base.y += PORTAL_GROUND * TDStage.TEXEL / TDStage.art_density(biome.portal_frames[0])
	var at := TDStage.to3d(base, TDStage.Z_PORTAL)
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
		s.modulate = Color(1.2, 1.25, 1.3)
		s.position = at
		# light is see-through and writes no depth, so it is drawn in sorted order: sort it as
		# nearer than any building or scenery (a tall building's middle sorts nearer than its door)
		s.sorting_offset = PORTAL_SORT
		s.play(&"default")
		root.add_child(s)
	var l := TDStage.light(Color("a8ccff"), 3.0, 7.0)
	l.position = at + Vector3(0, 1.6, 0.8)
	root.add_child(l)
	var sparks := TDStage.particles(Color(1.8, 2.3, 3.0), 30, 0.12)
	sparks.lifetime = 2.0
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.8, 0.2, 0.3)
	sparks.gravity = Vector3(0, 0.6, 0)
	sparks.initial_velocity_min = 0.2
	sparks.initial_velocity_max = 0.6
	sparks.direction = Vector3.UP
	sparks.position = at + Vector3(0, 0.3, 0.2)
	sparks.sorting_offset = PORTAL_SORT
	root.add_child(sparks)

## The lantern posts, where LanternPlacement put them (worked out in `build`), and the
## map's hand-placed ones on its raised levels.
func _lanterns(map: MapDef, biome: BiomeDef, _rng: RandomNumberGenerator) -> void:
	var spots: Array[Vector2] = []
	for x in _lantern_xs:
		spots.append(Vector2(x, map.ground_y))
	var on_floor := spots.size()
	if biome.lantern:
		for at in map.level_lanterns:
			spots.append(Vector2(at.x, map.platforms[at.y - 1].y))
	for i in spots.size():
		var post := TDStage.sprite(biome.lantern)
		if i < on_floor:
			TDStage.stand_on_land(post, spots[i] + Vector2(0, 3.0), -1.3)
		else:
			# a raised level's lantern stands in front of the land, like the people on it, so
			# the wall of the level above (straight behind it) doesn't hide it
			post.position = TDStage.to3d(spots[i] + Vector2(0, 3.0), TDStage.LAND_FRONT + 0.01)
		var pos := post.position
		root.add_child(post)
		var size := post.texture.get_size() * post.pixel_size
		var lamp := pos + Vector3(size.x * biome.lantern_lamp.x, size.y * biome.lantern_lamp.y, 0.05)
		var g := TDStage.glow_sprite(load("res://assets/sprites/fx/glow.png"), Color(biome.lantern_light, 0.5) * 1.5)
		g.position = lamp
		root.add_child(g)
		var l := TDStage.light(biome.lantern_light, 2.2, 6.0)
		l.position = lamp + Vector3(0, 0, 0.5)
		l.set_meta(&"energy", l.light_energy)
		l.add_to_group(&"flicker")
		root.add_child(l)
