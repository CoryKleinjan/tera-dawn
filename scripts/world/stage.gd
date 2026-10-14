class_name TDStage
extends Node3D
## The HD-2D view of the map: painted sprites standing in a lit 3D diorama.
## Gameplay stays 2D (game pixels, y down); this node owns the camera, sky, light and
## post effects, and asks the builders to turn the map into 3D:
##   TerrainBuilder  the painted front skins of the floor and the platforms
##   BackdropBuilder the parallax mountains, trees, clouds and sun
##   SceneryBuilder  props, climbables, portals, lanterns and signs
## One 3D unit is PX game pixels. Static helpers here make sprites and lights for everyone.

const PX := 32.0
const FOV := 30.0
const PITCH := 9.0 # degrees the camera looks down
## How far the camera sees (3D units): backdrop layers must stand nearer than this.
const FAR := 400.0
## Size of one art pixel in game pixels, for characters, props and land. Every piece of
## land art (tiles, platform pieces, ground textures) is drawn so one of its art pixels
## shows this big, so all the land shows its painted detail at one shared scale.
const TEXEL := 1.25
## Texels per art pixel of the art in these folders. tools/art/slice_sheets.py cuts every
## sheet at 2 texels per art pixel ("art_px" land at "density" 2, everything else at "detail" 2)
## with smooth edges, so outlines stay clean on a 1080p screen. The art is painted, not pixel art:
## "art pixel" is just the unit the game sizes it in. Art anywhere else (the hero's layers, the
## UI) has one texel per art pixel.
const ART_DENSITY := {
	"res://assets/sprites/npcs/": 2.0,
	"res://assets/sprites/monsters/": 2.0,
	"res://assets/sprites/pets/": 2.0,
	"res://assets/sprites/items/": 2.0,
	"res://assets/sprites/effects/": 2.0,
	"res://assets/sprites/projectiles/": 2.0,
	"res://assets/sprites/skills/": 2.0,
	"res://assets/sprites/tiles/": 2.0,
	"res://assets/sprites/platforms/": 2.0,
	"res://assets/sprites/ground/": 2.0,
	"res://assets/sprites/buildings/": 2.0,
	"res://assets/sprites/backgrounds/": 2.0,
	"res://assets/sprites/rooms/": 2.0,
	# the scenery pieces of props/ (dawnshards there are drop items, drawn at their own size)
	"res://assets/sprites/props/portal_": 2.0,
	"res://assets/sprites/props/lantern_": 2.0,
	"res://assets/sprites/props/ladder_": 2.0,
	"res://assets/sprites/props/rope": 2.0,
	"res://assets/sprites/props/vine_": 2.0,
}

## Land is flat, like a 2D game: the floor and the floating platforms are painted front skins
## at LAND_FRONT, with no ground running back into the scene. What stands on the land (trees,
## houses, props, signs) lives in a thin layer just behind the skins. Content gives depths from
## 0 back to SCENERY_DEEP, and land_depth squeezes them into the SCENERY_LAYER units behind
## LAND_FRONT, keeping their front-to-back order (see stand_on_land).
const SCENERY_DEEP := 9.0
const SCENERY_LAYER := 0.9

## Draw order. Depth is 3D z: bigger is nearer the camera. Everything the player can touch
## (climbables, NPCs, monsters, drops, the player) stands in front of all the land, so the
## ground, platforms and their decoration never hide it. New content should use these.
## Land: platform front skins sit at LAND_FRONT; decoration and props are clamped behind it.
## (The grass on the floor's front edge is nearer, but it shows below everyone's feet.)
const LAND_FRONT := 0.14
## Portals stand in front of all the land and scenery (so nothing hides the way out) but behind
## everything you can touch: ropes, NPCs, monsters, drops and the player.
const Z_PORTAL := 0.17
const Z_CLIMBABLE := 0.2
const Z_NPC := 0.3
## Monsters spread over [Z_MONSTER, Z_MONSTER + Z_MONSTER_SPREAD) so overlapping ones don't flicker.
const Z_MONSTER := 0.38
const Z_MONSTER_SPREAD := 0.14
const Z_DROP := 0.56
## Other players stand just behind you, so your own hero is never hidden in a crowd.
const Z_OTHER_PLAYER := 0.6
const Z_PLAYER := 0.64
## Skill and hit effects play just in front of the player, on the characters' plane (effect_sprite).
const Z_EFFECT := 0.8
## Render priorities. See-through things (every sprite's soft edge) are drawn back to front, by
## how far away the middle of each one is, which goes wrong for a tall building behind a short
## character. Priority comes first: the scenery, NPCs, monsters and drops are drawn at 0, then
## other players' heroes, then yours, then effects. A hero takes HERO_PRIORITIES priorities, one
## per layer (PaperdollSprite).
const HERO_PRIORITIES := 60
const PRIORITY_OTHER_PLAYER := 1
const PRIORITY_PLAYER := PRIORITY_OTHER_PLAYER + HERO_PRIORITIES
const PRIORITY_EFFECT := PRIORITY_PLAYER + HERO_PRIORITIES
## Seconds a map change takes to fade out (and again to fade in).
const FADE_TIME := 0.25
## Seconds a screen flash takes to fade (to a hundredth of its strength).
const FLASH_TIME := 0.18

var world: TDWorld
var camera: Camera3D
var env: Environment
var sun: DirectionalLight3D
var map_root: Node3D
## The scenery of portals that open and shut with a quest (PortalDef.locked) -> their PortalDef.
var locked_portals := {}
var motes: CPUParticles3D
var backdrop: BackdropBuilder
var dist := 0.0
var camera_attrs: CameraAttributesPractical
## The finishing pass (post.gdshader): blur, grade and the fade between maps.
var post_material: ShaderMaterial
## 0 shows the scene, 1 is faded out (see fade_to).
var fade := 0.0
var _fade_target := 0.0
## How strongly the screen is washed with a flash (see flash_screen); fades by itself.
var _flash := 0.0

## The stage showing now.
static var current: TDStage

static var _soft_dot: Texture2D

# ---------- helpers for everyone ----------

## Where a piece of land decoration with content depth `z` (0 at the land's front, down to
## -SCENERY_DEEP) really stands: in the thin layer behind the land's front skins, in the same
## order, and always behind everything you can touch.
static func land_depth(z: float) -> float:
	var front := LAND_FRONT - 0.02
	if z >= front:
		return front
	return lerpf(front, -SCENERY_LAYER, clampf((front - z) / (front + SCENERY_DEEP), 0.0, 1.0))

## Stands `s` (origin at its bottom centre) on the land at `foot` (game pixels), at content
## depth `z`: at its land_depth, scaled so it shows as big as it would at `z`, and sunk
## (land_sink) so its base tucks behind the land's grass edge instead of floating over it.
## Pass keep_size = false for art sized for the play line (buildings).
static func stand_on_land(s: SpriteBase3D, foot: Vector2, z: float, keep_size := true) -> void:
	var d := land_depth(z)
	if keep_size:
		var cam_z := cos(deg_to_rad(PITCH)) * view_distance()
		s.pixel_size *= (cam_z - d) / (cam_z - minf(z, d))
	s.position = to3d(foot, d) + Vector3(0, -land_sink(d, foot.y), 0)

## How far (3D units) something at depth `z` standing on land whose top is at game-y `surface`
## must sink so its base never shows above the land's front edge. The camera looks down on
## the land, so things further back appear higher; most of all when the camera is at the top
## of the map.
static func land_sink(z: float, surface: float) -> float:
	var pitch := deg_to_rad(PITCH)
	var dist_ := view_distance()
	var above := (surface - TDWorld.world_view().y / 2.0) / PX + sin(pitch) * dist_
	return maxf(0.0, above) * maxf(0.0, LAND_FRONT - z) / (cos(pitch) * dist_ - LAND_FRONT)

## The camera distance that shows TDWorld.world_view().y game pixels at the play line.
static func view_distance() -> float:
	return (TDWorld.world_view().y / PX) / 2.0 / tan(deg_to_rad(FOV / 2.0))

## Texels per art pixel of `texture` (ART_DENSITY; a built texture or an animation frame can
## carry its own as the "art_density" meta). An animation frame without one counts as the strip
## it's cut from.
static func art_density(texture: Texture2D) -> float:
	if texture != null and texture.has_meta(&"art_density"):
		return texture.get_meta(&"art_density")
	if texture is AtlasTexture:
		texture = (texture as AtlasTexture).atlas
	if texture == null:
		return 1.0
	if texture.has_meta(&"art_density"):
		return texture.get_meta(&"art_density")
	for dir: String in ART_DENSITY:
		if texture.resource_path.begins_with(dir):
			return ART_DENSITY[dir]
	return 1.0

## Texels per art pixel of an animation's frames (all cut from one strip).
static func frames_density(frames: SpriteFrames) -> float:
	for anim in frames.get_animation_names():
		if frames.get_frame_count(anim) > 0:
			return art_density(frames.get_frame_texture(anim, 0))
	return 1.0

## How big `texture` shows, in game pixels, drawn `texel` game pixels per art pixel.
static func art_size(texture: Texture2D, texel := TEXEL) -> Vector2:
	return texture.get_size() * texel / art_density(texture)

static func to3d(p: Vector2, z := 0.0) -> Vector3:
	return Vector3(p.x / PX, -p.y / PX, z)

## Sprite defaults: smooth (the art is painted, and nearest-neighbour at a non-whole scale
## makes jagged, shimmering edges), the art's own soft edge blended in, lit, origin at the
## bottom centre.
static func style_sprite(s: SpriteBase3D, texel := TEXEL, shaded := true) -> void:
	s.pixel_size = texel / PX
	s.centered = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	s.shaded = shaded
	s.double_sided = true

## A sprite whose origin is the bottom centre of its texture, `texel` game pixels per art
## pixel (see art_density).
static func sprite(texture: Texture2D, texel := TEXEL, shaded := true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = texture
	style_sprite(s, texel / art_density(texture), shaded)
	s.offset = Vector2(0, texture.get_height() / 2.0)
	return s

## Unshaded, soft-edged sprite with HDR colour so it blooms (glows, effects, the sun).
static func glow_sprite(texture: Texture2D, col: Color, texel := TEXEL) -> Sprite3D:
	var s := sprite(texture, texel, false)
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.offset = Vector2.ZERO
	s.modulate = col
	return s

## A skill, hit or projectile effect: a glow_sprite whose solid parts also record their depth,
## so the depth of field keeps it as sharp as the characters it plays over instead of blurring
## it with the scenery behind (see Z_EFFECT). Its soft edges still blend over what's behind.
static func effect_sprite(texture: Texture2D, col: Color, texel := TEXEL) -> Sprite3D:
	var s := glow_sprite(texture, col, texel)
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	s.render_priority = PRIORITY_EFFECT
	return s

static func light(col: Color, energy: float, range_: float, shadows := false) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = col
	o.light_energy = energy
	o.omni_range = range_
	o.omni_attenuation = 1.4
	o.shadow_enabled = shadows
	return o

static func additive_material(col: Color) -> StandardMaterial3D:
	if _soft_dot == null:
		_soft_dot = load("res://assets/sprites/fx/soft_dot.png")
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	m.albedo_texture = _soft_dot
	m.disable_receive_shadows = true
	return m

## Glowing particles (sparks, embers, dust motes). Colours may be HDR.
static func particles(col: Color, amount: int, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = additive_material(col)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# ---------- camera, sky and post effects ----------

func _ready() -> void:
	current = self
	_fit_distance()
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 1.0
	camera.far = FAR
	camera.rotation_degrees = Vector3(-PITCH, 0, 0)
	add_child(camera)
	camera.make_current()
	# soft sprite edges (alpha to coverage, see style_sprite)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_build_environment()
	_build_sun()
	_build_motes()
	_build_post()

func _exit_tree() -> void:
	if current == self:
		current = null

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4, 5] else 0.0)
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = dist + 12.0
	env.fog_depth_end = dist + 160.0
	env.fog_depth_curve = 1.6
	env.fog_density = 0.6
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.08
	apply_video(Settings.video)
	Settings.changed.connect(_on_settings_changed)
	var we := WorldEnvironment.new()
	we.environment = env
	camera_attrs = CameraAttributesPractical.new()
	camera_attrs.dof_blur_far_enabled = true
	camera_attrs.dof_blur_far_transition = 14.0
	camera_attrs.dof_blur_near_enabled = true
	camera_attrs.dof_blur_near_distance = dist - 6.0
	camera_attrs.dof_blur_near_transition = 5.0
	we.camera_attributes = camera_attrs
	add_child(we)

func _on_settings_changed(section: SettingsSection) -> void:
	if section is VideoSettings:
		apply_video(section)

## Turns the costly effects on or off as the player's video settings say.
func apply_video(v: VideoSettings) -> void:
	env.glow_enabled = v.bloom
	env.ssao_enabled = v.ambient_occlusion
	env.fog_enabled = v.fog

func _build_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.75, -0.48, -0.45).normalized(), Vector3.UP)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.3
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = dist + 30.0
	add_child(sun)

func _build_motes() -> void:
	motes = particles(Color.WHITE, 70, 0.14)
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(18, 10, 5)
	motes.spread = 60.0
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.4
	motes.scale_amount_min = 0.4
	motes.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	motes.color_ramp = fade
	add_child(motes)

func _build_post() -> void:
	var post_layer := CanvasLayer.new()
	post_layer.layer = 5
	var post := ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_material = ShaderMaterial.new()
	post_material.shader = load("res://shaders/post.gdshader")
	post.material = post_material
	post_layer.add_child(post)
	add_child(post_layer)

## Rebuilds everything for the world's current map.
func build() -> void:
	if map_root:
		remove_child(map_root)
		map_root.queue_free()
	map_root = Node3D.new()
	add_child(map_root)
	locked_portals.clear()
	var map := world.map
	var biome := map.look()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map.id)
	_apply_biome(biome)
	_apply_place(map)
	TerrainBuilder.new(self, map_root).build(map, world.platforms)
	backdrop = BackdropBuilder.new(self, map_root)
	backdrop.build(map, rng)
	SceneryBuilder.new(self, map_root).build(map, world.platforms, rng)
	if biome.light_shafts:
		_build_light_shafts(map, biome, rng)
	_build_tears(map)
	follow(world.cam)
	show_open_portals(Game.me)

## Shows the locked portals `c` has opened and hides the rest.
func show_open_portals(c: Character) -> void:
	for node: Node3D in locked_portals:
		node.visible = (locked_portals[node] as PortalDef).open_to(c)

func _apply_biome(b: BiomeDef) -> void:
	var sky_mat := env.sky.sky_material as ShaderMaterial
	sky_mat.set_shader_parameter("top_color", b.sky_top)
	sky_mat.set_shader_parameter("mid_color", b.sky_mid)
	sky_mat.set_shader_parameter("low_color", b.sky_low)
	sky_mat.set_shader_parameter("horizon_color", b.sky_horizon)
	sky_mat.set_shader_parameter("sun_color", b.sun_color)
	env.ambient_light_color = b.ambient_color
	env.ambient_light_energy = b.ambient_energy
	env.fog_light_color = b.fog_color
	sun.light_color = b.light_color
	sun.light_energy = b.light_energy
	post_material.set_shader_parameter(&"tint", b.grade_tint)
	post_material.set_shader_parameter(&"lift", b.grade_lift)
	post_material.set_shader_parameter(&"lift_amount", b.grade_lift_amount)
	post_material.set_shader_parameter(&"saturation", b.grade_saturation)
	((motes.mesh as PrimitiveMesh).material as StandardMaterial3D).albedo_color = b.mote_color
	motes.gravity = Vector3(0, 0.35 if b.motes_rise else 0.05, 0)
	motes.direction = Vector3(0.2 if b.motes_rise else 0.3, 1, 0)

## The camera distance that shows TDWorld.world_view().y game pixels at the play line.
func _fit_distance() -> void:
	dist = view_distance()

## The window changed shape: refit the camera and rebuild the scenery for the new view.
func fit_view() -> void:
	_fit_distance()
	env.fog_depth_begin = dist + 12.0
	env.fog_depth_end = dist + 160.0
	camera_attrs.dof_blur_near_distance = dist - 6.0
	sun.directional_shadow_max_distance = dist + 30.0
	if world.map and map_root:
		build()

## Towns are for looking around: their backdrop is kept clearer (less fog) than a hunting
## field's, where the eye should stay on the play line. A room's back wall is close, so it
## stays sharp with no haze. The far blur is only a light touch of depth everywhere: the
## painted backdrops should read sharp, never smeared.
func _apply_place(map: MapDef) -> void:
	env.fog_density = 0.0 if map.interior else 0.35 if map.town else 0.6
	camera_attrs.dof_blur_far_distance = dist + (14.0 if map.interior else 10.0 if map.town else 3.0)
	camera_attrs.dof_blur_amount = 0.01 if map.interior else 0.015 if map.town else 0.02

## Soft slanting beams of sunlight between the backdrop and the play line, gently pulsing.
func _build_light_shafts(map: MapDef, biome: BiomeDef, rng: RandomNumberGenerator) -> void:
	var x := rng.randf_range(100.0, 400.0)
	while x < map.width:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_texture = _beam_texture()
		mat.disable_receive_shadows = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var c := biome.light_shaft_color
		mat.albedo_color = c
		var q := QuadMesh.new()
		q.size = Vector2(rng.randf_range(1.5, 3.5), map.height / PX * 1.2)
		var beam := MeshInstance3D.new()
		beam.mesh = q
		beam.material_override = mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3(x / PX, -map.height / PX * 0.45, rng.randf_range(-7.0, -3.5))
		beam.rotation_degrees = Vector3(0, 0, rng.randf_range(-24.0, -16.0))
		beam.set_meta(&"alpha", c.a * rng.randf_range(0.6, 1.0))
		beam.set_meta(&"phase", rng.randf() * TAU)
		beam.add_to_group(&"light_shaft")
		map_root.add_child(beam)
		x += rng.randf_range(260.0, 520.0)

## How far back the glows over the water (MapDef.tears) hang, their size (3D units) and colour.
const TEAR_Z := -6.0
const TEAR_SIZE := 2.6
const TEAR_COLOR := Color(1.0, 0.98, 0.94, 0.55)

## A tear that opens (MapDef.tear_platform) hangs close over the floor, bigger and brighter.
const OPENING_TEAR_Z := -1.5
const OPENING_TEAR_SIZE := 4.2

## The map's faint white glows over the water: soft, bright in the middle, slowly breathing.
## A tear that opens stays hidden until it does (show_tears).
func _build_tears(map: MapDef) -> void:
	var opens := map.tear_platform >= 0
	for at in map.tears:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_texture = _glow_texture()
		mat.albedo_color = TEAR_COLOR
		mat.disable_receive_shadows = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var q := QuadMesh.new()
		var size := OPENING_TEAR_SIZE if opens else TEAR_SIZE
		q.size = Vector2(size, size)
		var glow := MeshInstance3D.new()
		glow.mesh = q
		glow.material_override = mat
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position = to3d(Vector2(at.x, map.ground_y - at.y), OPENING_TEAR_Z if opens else TEAR_Z)
		glow.visible = not opens
		glow.add_to_group(&"tear")
		map_root.add_child(glow)

## Shows a map's tear once it has opened (a map whose tears are always there ignores it).
func show_tears(open: bool) -> void:
	if world.map.tear_platform < 0:
		return
	for glow: Node3D in get_tree().get_nodes_in_group(&"tear"):
		glow.visible = open

static var _glow: ImageTexture

## A round glow: white in the middle, fading softly to nothing at the edge.
static func _glow_texture() -> ImageTexture:
	if _glow == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x - (n - 1) / 2.0, y - (n - 1) / 2.0).length() / (n / 2.0)
				var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_glow = ImageTexture.create_from_image(img)
	return _glow

static var _beam: ImageTexture

## A soft beam: bright down the middle, fading at the sides and toward the bottom.
static func _beam_texture() -> ImageTexture:
	if _beam == null:
		var img := Image.create(32, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			var down := 1.0 - y / 127.0
			for x in 32:
				var across := 1.0 - absf(x / 31.0 - 0.5) * 2.0
				img.set_pixel(x, y, Color(1, 1, 1, smoothstep(0.0, 1.0, across) * smoothstep(0.0, 0.7, down)))
		_beam = ImageTexture.create_from_image(img)
	return _beam

## Fades the scene out (to 1) or back in (to 0) over the next few frames (map changes).
func fade_to(target: float) -> void:
	_fade_target = target

## Washes the screen with `col` at `strength` (0 to 1) for a moment (you got hit).
func flash_screen(col: Color, strength: float) -> void:
	_flash = maxf(_flash, strength)
	post_material.set_shader_parameter(&"flash_color", col)
	post_material.set_shader_parameter(&"flash", _flash)

## Fades out at once (the next map starts dark and fades in).
func set_faded(v: float) -> void:
	fade = v
	_fade_target = v
	post_material.set_shader_parameter(&"fade", v)

# ---------- camera ----------

## Aims the camera so the world_view()-sized box at `cam` (its top left) fills the screen.
func follow(cam: Vector2) -> void:
	var target := to3d(cam + TDWorld.world_view() / 2.0)
	var pitch := deg_to_rad(PITCH)
	camera.position = target + Vector3(0, sin(pitch), cos(pitch)) * dist
	motes.position = Vector3(target.x, target.y, 1.0)

## Where a gameplay point appears in the 960x540 canvas.
func screen(p: Vector2, z := 0.0) -> Vector2:
	return camera.unproject_position(to3d(p, z)) * TDWorld.VIEW / get_viewport().get_visible_rect().size

func in_view(p: Vector2, z := 0.0) -> bool:
	return not camera.is_position_behind(to3d(p, z)) and Rect2(Vector2(-80, -80), TDWorld.VIEW + Vector2(160, 160)).has_point(screen(p, z))

## World height (3D y) at depth z that appears `frac` of the way down the screen
## when the camera is in the middle of its vertical range.
func screen_height(frac: float, z: float) -> float:
	return screen_height_at(frac, z, _mid_center())

func _mid_center() -> float:
	return backdrop_center(world.map)

## The camera height (game-y of the view's middle) a map's backdrop is laid out for. In a
## town it is where the view sits while the hero walks the street (the floor), so the
## backdrop meets the street as painted and a tall town's upper levels just show more sky;
## elsewhere it is the middle of the camera's range.
static func backdrop_center(map: MapDef) -> float:
	var r := view_center_range(map.height)
	if map.town:
		var view := TDWorld.world_view().y
		return clampf(map.ground_y - view * WorldCamera.STAND_AT + view / 2.0, r.x, r.y)
	return (r.x + r.y) / 2.0

## The game-y of the middle of the view, highest (x) and lowest (y), as the camera moves
## over a map `map_height` tall.
static func view_center_range(map_height: float) -> Vector2:
	var half := TDWorld.world_view().y / 2.0
	return Vector2(half, maxf(half, map_height - half))

## World height (3D y) at depth z that appears `frac` of the way down the screen while the
## middle of the view is at game-y `center`.
static func screen_height_at(frac: float, z: float, center: float) -> float:
	var pitch := deg_to_rad(PITCH)
	var dist_ := view_distance()
	var cam_y := -center / PX + sin(pitch) * dist_
	var cam_z := cos(pitch) * dist_
	var rel := atan((0.5 - frac) * 2.0 * tan(deg_to_rad(FOV / 2.0)))
	return cam_y + tan(rel - pitch) * (cam_z - z)

## How far down the screen (0 top, 1 bottom) world height `h` at depth z appears while the
## middle of the view is at game-y `center`.
static func screen_frac_at(h: float, z: float, center: float) -> float:
	var pitch := deg_to_rad(PITCH)
	var dist_ := view_distance()
	var cam_y := -center / PX + sin(pitch) * dist_
	var cam_z := cos(pitch) * dist_
	var rel := atan((h - cam_y) / (cam_z - z)) + pitch
	return 0.5 - tan(rel) / (2.0 * tan(deg_to_rad(FOV / 2.0)))

func _process(delta: float) -> void:
	if backdrop:
		backdrop.drift(delta)
	if fade != _fade_target:
		fade = move_toward(fade, _fade_target, delta / FADE_TIME)
		post_material.set_shader_parameter(&"fade", fade)
	if _flash > 0.0:
		_flash = 0.0 if _flash < 0.01 else _flash * pow(0.01, delta / FLASH_TIME)
		post_material.set_shader_parameter(&"flash", _flash)
	var t := Time.get_ticks_msec() / 1000.0
	for l: OmniLight3D in get_tree().get_nodes_in_group(&"flicker"):
		var seed_ := float(l.get_instance_id() % 997)
		l.light_energy = float(l.get_meta(&"energy")) * (0.88 + 0.08 * sin(t * 7.0 + seed_) + 0.04 * sin(t * 13.0 + seed_ * 2.0))
	for glow: MeshInstance3D in get_tree().get_nodes_in_group(&"tear"):
		(glow.material_override as StandardMaterial3D).albedo_color.a = TEAR_COLOR.a * (0.75 + 0.25 * sin(t * 1.3))
	for beam: MeshInstance3D in get_tree().get_nodes_in_group(&"light_shaft"):
		var m := beam.material_override as StandardMaterial3D
		m.albedo_color.a = float(beam.get_meta(&"alpha")) * (0.7 + 0.3 * sin(t * 0.4 + float(beam.get_meta(&"phase"))))
