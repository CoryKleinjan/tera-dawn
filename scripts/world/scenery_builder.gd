class_name SceneryBuilder
extends RefCounted
## Builds everything that stands on the ground: the biome's scattered trees, bushes and
## rocks, the map's hand-placed props, ropes and ladders, portals, lanterns and the sign.

## How much bigger than the biome's art the signpost is drawn, and its depth.
const SIGN_SCALE := 1.2
const SIGN_DEPTH := -0.9
## Space between the top of the signpost (or portal) and the sign's words.
const SIGN_LABEL_GAP := 6.0
## Room the sign's words need above their bottom edge, so no platform skin runs through them.
const SIGN_LABEL_H := 22.0

var stage: TDStage
var root: Node3D

func _init(s: TDStage, r: Node3D) -> void:
	stage = s
	root = r

func build(map: MapDef, platforms: Array[Platform], rng: RandomNumberGenerator) -> void:
	var biome := map.biome
	for rule in biome.ground_decor:
		_scatter(rule, -300.0, map.width + 300.0, map.ground_y, rng)
	for i in range(1, platforms.size()):
		var pl := platforms[i]
		for rule in biome.platform_decor:
			_scatter(rule, pl.x + 30.0, pl.x + pl.w - 30.0, pl.y, rng)
	for p in map.props:
		_prop(p, map)
	for c in map.climbables:
		_climbable(c)
	for p in map.portals:
		_portal(p, platforms[p.platform], biome)
	_lanterns(map, biome, rng)
	_sign(map, biome)

## Drops pieces from a DecorDef along [x0, x1] on the surface at y.
func _scatter(rule: DecorDef, x0: float, x1: float, y: float, rng: RandomNumberGenerator) -> void:
	if rule.textures.is_empty():
		return
	var x := x0 + rng.randf_range(0.0, rule.spacing.x)
	while x < x1:
		if rng.randf() < rule.chance:
			var tex: Texture2D = rule.textures[rng.randi() % rule.textures.size()]
			var s := TDStage.sprite(tex, rule.texel * rng.randf_range(rule.scale.x, rule.scale.y), rule.shaded)
			s.position = TDStage.to3d(Vector2(x, y + 3.0), rng.randf_range(TDStage.land_depth(rule.depth.x), TDStage.land_depth(rule.depth.y)))
			s.flip_h = rng.randf() < 0.5
			root.add_child(s)
		x += rng.randf_range(rule.spacing.x, rule.spacing.y)

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
		y += st.top.get_height() * texel * 0.9
	var bottom_h := st.bottom.get_height() * texel if st.bottom else 0.0
	var mid_h := st.middle.get_height() * texel
	while y < c.bottom - bottom_h - 2.0:
		var s := TDStage.sprite(st.middle, texel)
		s.offset = Vector2(0, -st.middle.get_height() / 2.0)  # hang from the top
		s.position = TDStage.to3d(Vector2(c.x, y), z)
		# the last piece may poke past the bottom; it hides behind the bottom piece or the floor
		root.add_child(s)
		y += mid_h - texel
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
		TDStage.style_sprite(s, TDStage.TEXEL, false)
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
		var lamp := pos + Vector3(biome.lantern.get_width() * 0.22 * TDStage.TEXEL / TDStage.PX,
			biome.lantern.get_height() * 0.62 * TDStage.TEXEL / TDStage.PX, 0.05)
		var g := TDStage.glow_sprite(load("res://assets/sprites/fx/glow.png"), Color(biome.lantern_light, 0.5) * 1.5)
		g.position = lamp
		root.add_child(g)
		var l := TDStage.light(biome.lantern_light, 2.2, 6.0)
		l.position = lamp + Vector3(0, 0, 0.5)
		root.add_child(l)
		x += rng.randf_range(map.lantern_spacing * 0.85, map.lantern_spacing * 1.15)

func _sign(map: MapDef, biome: BiomeDef) -> void:
	if map.sign_text == "" or biome.signpost == null:
		return
	var post := TDStage.sprite(biome.signpost, TDStage.TEXEL * SIGN_SCALE)
	post.position = TDStage.to3d(Vector2(map.sign_x, map.ground_y + 3.0), SIGN_DEPTH)
	root.add_child(post)

## Where the sign's words go (game pixels, their bottom centre), or null for no sign. The
## overlay draws them, so they stay sharp and in front: over the post, at least as high as
## the biome's portal so the portal by the entrance never hides them, and above any platform
## skin they would otherwise sit on.
static func sign_label_at(map: MapDef) -> Variant:
	var biome := map.biome
	if map.sign_text == "" or biome == null or biome.signpost == null:
		return null
	var h := biome.signpost.get_height() * SIGN_SCALE * TDStage.TEXEL
	if not biome.portal_frames.is_empty():
		h = maxf(h, biome.portal_frames[0].get_height() * TDStage.TEXEL)
	var y := map.ground_y + 3.0 - h - SIGN_LABEL_GAP
	var moved := true
	while moved: # lifting the words over one platform can put them in the one above
		moved = false
		for d in map.platforms:
			if map.sign_x < d.x or map.sign_x > d.x + d.width:
				continue
			var skin := TerrainBuilder.skin_span(d, biome)
			if y > skin.x and y - SIGN_LABEL_H < skin.y:
				y = skin.x - SIGN_LABEL_GAP
				moved = true
	return Vector2(map.sign_x, y)
