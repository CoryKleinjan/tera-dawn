class_name TDStage
extends Node3D
## The HD-2D view of the map: pixel-art sprites standing in a lit 3D diorama.
## Gameplay stays 2D (pixels, y down); this node turns map data into 3D terrain,
## props, lights, sky and post effects, and moves a tilted perspective camera.
## One 3D unit is PX game pixels, and one sprite texel is 1.25 game pixels.

const PX := 32.0
const PIXEL := 1.25 / PX
const FOV := 30.0
const PITCH := 9.0 # degrees the camera looks down

const GROUND_BACK := -9.0
const GROUND_FRONT := 3.0
const PLAT_BACK := -2.4
const PLAT_FRONT := 0.1 # characters stand in front of it so platforms above never hide them
const PLAT_THICK := 0.8
const TREE_SCALE := 1.8 # tree sprites are drawn at about half size; scale them back up

var world: TDWorld
var camera: Camera3D
var env: Environment
var sun: DirectionalLight3D
var map_root: Node3D
var motes: CPUParticles3D
var clouds: Array[Sprite3D] = []
var dist := 0.0

static var _tex_cache := {}

static func to3d(p: Vector2, z := 0.0) -> Vector3:
	return Vector3(p.x / PX, -p.y / PX, z)

static func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load("res://assets/sprites/%s.png" % name)
	return _tex_cache[name]

## A pixel-art sprite whose origin is the bottom centre of its frame.
static func sprite(texture: Texture2D, hframes := 1, shaded := true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = texture
	s.hframes = hframes
	s.pixel_size = PIXEL
	s.centered = true
	s.offset = Vector2(0, texture.get_height() / 2.0)
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = shaded
	s.double_sided = true
	return s

## Unshaded sprite drawn additively with HDR color so it blooms.
static func glow_sprite(texture: Texture2D, col: Color, hframes := 1) -> Sprite3D:
	var s := sprite(texture, hframes, false)
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.offset = Vector2.ZERO
	s.modulate = col
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
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	m.albedo_texture = tex("soft_dot")
	m.disable_receive_shadows = true
	return m

## Glowing particles (sparks, embers, dust motes). Colors may be HDR.
static func particles(col: Color, amount: int, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = additive_material(col)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

func _ready() -> void:
	dist = (TDWorld.VIEW.y / PX) / 2.0 / tan(deg_to_rad(FOV / 2.0))
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 1.0
	camera.far = 400.0
	camera.rotation_degrees = Vector3(-PITCH, 0, 0)
	add_child(camera)
	camera.make_current()

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
	env.fog_depth_end = dist + 110.0
	env.fog_depth_curve = 1.4
	env.fog_density = 0.85
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = dist + 3.0
	attrs.dof_blur_far_transition = 14.0
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = dist - 6.0
	attrs.dof_blur_near_transition = 5.0
	attrs.dof_blur_amount = 0.14
	we.camera_attributes = attrs
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3(-0.75, -0.48, -0.45).normalized(), Vector3.UP)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.3
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = dist + 30.0
	add_child(sun)

	motes = particles(Color.WHITE, 70, 0.14)
	motes.lifetime = 7.0
	motes.preprocess = 7.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(18, 10, 5)
	motes.gravity = Vector3(0, 0.05, 0)
	motes.direction = Vector3(0.3, 1, 0)
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

	var post_layer := CanvasLayer.new()
	post_layer.layer = 5
	var post := ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post_mat := ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	post.material = post_mat
	post_layer.add_child(post)
	add_child(post_layer)

## Rebuilds terrain, props and lighting for the world's current map.
func build() -> void:
	if map_root:
		remove_child(map_root)
		map_root.queue_free()
	map_root = Node3D.new()
	add_child(map_root)
	clouds.clear()
	var th := world.colors
	var art: String = th["art"]
	var map := world.map
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world.map_id)

	var sky: Array = th["sky"]
	var sky_mat := env.sky.sky_material as ShaderMaterial
	sky_mat.set_shader_parameter("top_color", sky[0])
	sky_mat.set_shader_parameter("mid_color", sky[1])
	sky_mat.set_shader_parameter("low_color", sky[2])
	sky_mat.set_shader_parameter("horizon_color", sky[3])
	sky_mat.set_shader_parameter("sun_color", th["sun"])
	env.ambient_light_color = th["ambient"]
	env.ambient_light_energy = th["ambient_energy"]
	env.fog_light_color = th["fog"]
	sun.light_color = th["light"]
	sun.light_energy = th["light_energy"]
	(motes.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = th["motes"]
	if art == "ember":
		motes.gravity = Vector3(0, 0.35, 0)
		motes.direction = Vector3(0.2, 1, 0)
	else:
		motes.gravity = Vector3(0, 0.05, 0)
		motes.direction = Vector3(0.3, 1, 0)

	_build_terrain(art)
	_build_backdrop(th, rng)
	_dress_ground(art, rng)
	for i in range(1, world.plats.size()):
		_dress_platform(world.plats[i], art, rng)
	for r in world.ropes:
		_build_rope(r)
	for p in map["portals"]:
		_build_portal(p)
	_build_sign()
	_build_lanterns(th, rng)
	follow(world.cam)

# ---------- camera ----------

func follow(cam: Vector2) -> void:
	var target := to3d(cam + TDWorld.VIEW / 2.0)
	var pitch := deg_to_rad(PITCH)
	camera.position = target + Vector3(0, sin(pitch), cos(pitch)) * dist
	motes.position = Vector3(target.x, target.y, 1.0)

## Where a gameplay point appears in the 960x540 canvas.
func screen(p: Vector2, z := 0.0) -> Vector2:
	return camera.unproject_position(to3d(p, z)) * TDWorld.VIEW / get_viewport().get_visible_rect().size

func in_view(p: Vector2, z := 0.0) -> bool:
	return not camera.is_position_behind(to3d(p, z)) and Rect2(Vector2(-80, -80), TDWorld.VIEW + Vector2(160, 160)).has_point(screen(p, z))

func _process(delta: float) -> void:
	if world == null or world.map.is_empty():
		return
	for c in clouds:
		c.position.x += delta * float(c.get_meta("speed"))
		if c.position.x > float(c.get_meta("x1")):
			c.position.x = float(c.get_meta("x0"))

# ---------- terrain ----------

func _tile_material(name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 1.0
	return m

func _quad(st: SurfaceTool, pts: Array, uvs: Array, n: Vector3) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])

## A block of earth: grass on top, a grass lip on the front face, soil elsewhere.
func _block(top_st: SurfaceTool, side_st: SurfaceTool, soil_st: SurfaceTool,
		x0: float, x1: float, y_top: float, y_bot: float, z0: float, z1: float) -> void:
	var t := 2.0 # texture repeats every 2 units (32 texels)
	_quad(top_st, [Vector3(x0, y_top, z0), Vector3(x1, y_top, z0), Vector3(x1, y_top, z1), Vector3(x0, y_top, z1)],
		[Vector2(x0, z0) / t, Vector2(x1, z0) / t, Vector2(x1, z1) / t, Vector2(x0, z1) / t], Vector3.UP)
	var lip_bot := maxf(y_bot, y_top - 2.0)
	for face in [[z1, Vector3.BACK], [z0, Vector3.FORWARD]]:
		var z: float = face[0]
		var a := x0 if face[1] == Vector3.BACK else x1
		var b := x1 if face[1] == Vector3.BACK else x0
		_quad(side_st, [Vector3(a, y_top, z), Vector3(b, y_top, z), Vector3(b, lip_bot, z), Vector3(a, lip_bot, z)],
			[Vector2(a / t, 0), Vector2(b / t, 0), Vector2(b / t, (y_top - lip_bot) / t), Vector2(a / t, (y_top - lip_bot) / t)], face[1])
		if lip_bot > y_bot:
			_quad(soil_st, [Vector3(a, lip_bot, z), Vector3(b, lip_bot, z), Vector3(b, y_bot, z), Vector3(a, y_bot, z)],
				[Vector2(a, lip_bot) / t, Vector2(b, lip_bot) / t, Vector2(b, y_bot) / t, Vector2(a, y_bot) / t], face[1])
	for end in [[x0, Vector3.LEFT, z0, z1], [x1, Vector3.RIGHT, z1, z0]]:
		var x: float = end[0]
		var za: float = end[2]
		var zb: float = end[3]
		_quad(side_st, [Vector3(x, y_top, za), Vector3(x, y_top, zb), Vector3(x, lip_bot, zb), Vector3(x, lip_bot, za)],
			[Vector2(za / t, 0), Vector2(zb / t, 0), Vector2(zb / t, (y_top - lip_bot) / t), Vector2(za / t, (y_top - lip_bot) / t)], end[1])
		if lip_bot > y_bot:
			_quad(soil_st, [Vector3(x, lip_bot, za), Vector3(x, lip_bot, zb), Vector3(x, y_bot, zb), Vector3(x, y_bot, za)],
				[Vector2(za, lip_bot) / t, Vector2(zb, lip_bot) / t, Vector2(zb, y_bot) / t, Vector2(za, y_bot) / t], end[1])
	_quad(soil_st, [Vector3(x0, y_bot, z1), Vector3(x1, y_bot, z1), Vector3(x1, y_bot, z0), Vector3(x0, y_bot, z0)],
		[Vector2(x0, z1) / t, Vector2(x1, z1) / t, Vector2(x1, z0) / t, Vector2(x0, z0) / t], Vector3.DOWN)

func _build_terrain(art: String) -> void:
	var sts: Array[SurfaceTool] = []
	for i in 3:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
	var w := float(world.map["w"]) / PX
	var h := float(world.map["h"]) / PX
	for pl in world.plats:
		var top := -pl.y / PX
		if pl.solid:
			_block(sts[0], sts[1], sts[2], -40.0, w + 40.0, top, -h - 20.0, GROUND_BACK, GROUND_FRONT)
		else:
			_block(sts[0], sts[1], sts[2], pl.x / PX, (pl.x + pl.w) / PX, top, top - PLAT_THICK, PLAT_BACK, PLAT_FRONT)
	var mesh := ArrayMesh.new()
	var names := ["ground_%s_top" % art, "ground_%s_side" % art, "ground_%s_soil" % art]
	for i in 3:
		sts[i].generate_tangents()
		sts[i].commit(mesh)
		mesh.surface_set_material(i, _tile_material(names[i]))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	map_root.add_child(mi)

func _build_rope(r: Dictionary) -> void:
	var x: float = r["x"] / PX
	var top: float = -float(r["top"]) / PX
	var bot: float = -float(r["bottom"]) / PX
	var z := -0.45
	var node := Node3D.new()
	map_root.add_child(node)
	if r["kind"] == "ladder":
		var rail := StandardMaterial3D.new()
		rail.albedo_color = Color("6b4433")
		var rung := StandardMaterial3D.new()
		rung.albedo_color = Color("a77a5a")
		for side in [-1, 1]:
			_box(node, Vector3(x + side * 0.31, (top + 0.2 + bot) / 2.0, z), Vector3(0.12, top + 0.2 - bot, 0.12), rail)
		var y := top - 0.2
		while y > bot:
			_box(node, Vector3(x, y, z), Vector3(0.62, 0.09, 0.09), rung)
			y -= 0.5
	else:
		var rope := StandardMaterial3D.new()
		rope.albedo_color = Color("c9a77a")
		_box(node, Vector3(x, (top + bot) / 2.0, z), Vector3(0.1, top - bot, 0.1), rope)
		var knot := StandardMaterial3D.new()
		knot.albedo_color = Color("8e6c4a")
		var y := top - 0.3
		while y > bot + 0.2:
			_box(node, Vector3(x, y, z), Vector3(0.2, 0.14, 0.2), knot)
			y -= 0.7

func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)

# ---------- backdrop ----------

func _ridge(seed_: float, x: float) -> float:
	return sin(x * 0.13 + seed_) * 1.3 + sin(x * 0.35 + seed_ * 2.3) * 0.6 + sin(x * 0.86 + seed_ * 5.1) * 0.22

## Height (world y) at depth z that appears `frac` of the way down the screen
## when the camera is in the middle of its vertical range.
func _screen_height(frac: float, z: float) -> float:
	var cam_mid := (float(world.map["h"]) - TDWorld.VIEW.y) / 2.0
	var target_y := -(cam_mid + TDWorld.VIEW.y / 2.0) / PX
	var pitch := deg_to_rad(PITCH)
	var cam_y := target_y + sin(pitch) * dist
	var cam_z := cos(pitch) * dist
	var rel := atan((0.5 - frac) * 2.0 * tan(deg_to_rad(FOV / 2.0)))
	return cam_y + tan(rel - pitch) * (cam_z - z)

func _build_backdrop(th: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(world.map["w"]) / PX
	var layers := [[th["far"], -95.0, 0.6, 1.3], [th["mid"], -60.0, 0.71, 4.1], [th["near"], -32.0, 0.8, 7.7]]
	for l in layers:
		var z: float = l[1]
		var r := dist - z
		var scale := r / dist * 2.2
		var x0 := -r * 0.6 - 10.0
		var x1 := w + r * 0.6 + 10.0
		var base := _screen_height(l[2], z)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var col: Color = l[0]
		var x := x0
		while x < x1:
			var nx := x + 1.0 * scale
			var ya := base + _ridge(l[3], x / scale) * scale
			var yb := base + _ridge(l[3], nx / scale) * scale
			var bot := base - 120.0
			for v in [Vector3(x, ya, z), Vector3(nx, yb, z), Vector3(nx, bot, z), Vector3(x, ya, z), Vector3(nx, bot, z), Vector3(x, bot, z)]:
				st.set_color(col)
				st.set_normal(Vector3.BACK)
				st.add_vertex(v)
			x = nx
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		map_root.add_child(mi)
		# silhouettes of trees along the nearest ridge
		if z > -40.0:
			var art: String = th["art"]
			var tx := x0
			while tx < x1:
				var t := sprite(tex("tree_%s" % art), 1, false)
				t.modulate = col.darkened(0.1)
				t.pixel_size = PIXEL * r / dist * 0.55 * TREE_SCALE
				t.position = Vector3(tx, base + _ridge(l[3], tx / scale) * scale - 1.0, z + 0.5)
				t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				map_root.add_child(t)
				tx += rng.randf_range(2.0, 9.0) * scale * 0.5
	for i in 7:
		var c := sprite(tex("cloud"), 1, false)
		c.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var z := -120.0 - i * 6.0
		var r := dist - z
		c.pixel_size = PIXEL * rng.randf_range(3.5, 6.0)
		c.modulate = Color(th["sun"], 0.35).lerp(Color(1, 1, 1, 0.3), 0.5)
		c.set_meta("x0", -r * 0.7)
		c.set_meta("x1", w + r * 0.7)
		c.set_meta("speed", rng.randf_range(0.3, 0.8))
		c.position = Vector3(rng.randf_range(-r * 0.6, w + r * 0.6), _screen_height(rng.randf_range(0.08, 0.32), z), z)
		map_root.add_child(c)
		clouds.append(c)

# ---------- set dressing ----------

func _prop(name: String, pos: Vector3, hframes := 1, frame := 0, scale := 1.0) -> Sprite3D:
	var s := sprite(tex(name), hframes)
	s.frame = frame
	s.pixel_size = PIXEL * scale
	s.position = pos
	s.flip_h = pos.x * 7.3 - floorf(pos.x * 7.3) < 0.5
	map_root.add_child(s)
	return s

func _dress_ground(art: String, rng: RandomNumberGenerator) -> void:
	var w := float(world.map["w"]) / PX
	var y := -float(world.map["ground"]) / PX
	var x := -12.0
	while x < w + 12.0:
		var tree_name := "tree_%s" % art
		if art == "dawn" and rng.randf() < 0.35:
			tree_name = "tree_dawn_pink"
		_prop(tree_name, Vector3(x, y, rng.randf_range(GROUND_BACK + 0.5, -5.0)), 1, 0, rng.randf_range(0.9, 1.4) * TREE_SCALE)
		x += rng.randf_range(4.0, 9.0)
	x = -12.0
	while x < w + 12.0:
		_prop("bush_%s" % art, Vector3(x, y, rng.randf_range(-4.0, -2.2)), 1, 0, rng.randf_range(0.9, 1.3))
		if rng.randf() < 0.4:
			_prop("rock_%s" % art, Vector3(x + rng.randf_range(1, 3), y, rng.randf_range(-3.0, -1.5)))
		x += rng.randf_range(4.0, 8.0)
	x = -12.0
	while x < w + 12.0:
		_prop("tufts_%s" % art, Vector3(x, y, rng.randf_range(-7.0, GROUND_FRONT - 0.1)), 4, rng.randi_range(0, 3))
		x += rng.randf_range(0.6, 1.6)
	# grass fringe along the front edge
	x = -12.0
	while x < w + 12.0:
		_prop("tufts_%s" % art, Vector3(x, y, GROUND_FRONT - 0.02), 4, rng.randi_range(0, 3))
		x += rng.randf_range(0.6, 1.1)

func _dress_platform(pl: Plat, art: String, rng: RandomNumberGenerator) -> void:
	var y := -pl.y / PX
	var x := pl.x / PX + 0.3
	while x < (pl.x + pl.w) / PX - 0.3:
		_prop("tufts_%s" % art, Vector3(x, y, PLAT_FRONT - 0.02), 4, rng.randi_range(0, 3))
		if rng.randf() < 0.3:
			_prop("tufts_%s" % art, Vector3(x + 0.3, y, rng.randf_range(PLAT_BACK + 0.1, -0.6)), 4, rng.randi_range(0, 3))
		x += rng.randf_range(0.9, 1.8)
	if pl.w > 250 and rng.randf() < 0.6:
		_prop("bush_%s" % art, Vector3(rng.randf_range(pl.x + 40, pl.x + pl.w - 40) / PX, y, PLAT_BACK + 0.4))

func _build_portal(p: Dictionary) -> void:
	var base := Vector2(float(p["x"]), world.plats[int(p["plat"])].y)
	var root := Node3D.new()
	root.position = to3d(base, -0.3)
	map_root.add_child(root)
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 3.6)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/portal.gdshader")
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = Vector3(0, 1.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var l := light(Color("b49aff"), 3.0, 7.0)
	l.position = Vector3(0, 1.5, 0.8)
	root.add_child(l)
	var sparks := particles(Color(2.0, 1.6, 3.0), 30, 0.12)
	sparks.lifetime = 2.0
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(0.8, 0.2, 0.3)
	sparks.gravity = Vector3(0, 0.6, 0)
	sparks.initial_velocity_min = 0.2
	sparks.initial_velocity_max = 0.6
	sparks.direction = Vector3.UP
	root.add_child(sparks)

func _build_sign() -> void:
	if not world.map.has("sign"):
		return
	var s: Dictionary = world.map["sign"]
	var pos := to3d(Vector2(float(s["x"]), float(world.map["ground"])), -0.9)
	var post := _prop("signpost", pos, 1, 0, 1.2)
	post.flip_h = false
	var l := Label3D.new()
	l.text = s["text"]
	l.font = Game.ui_font
	l.font_size = 26
	l.pixel_size = 1.0 / (PX * 2.0)
	l.modulate = Color("2b1a14")
	l.outline_size = 0
	l.position = pos + Vector3(0, 2.68, 0.06)
	l.shaded = true
	map_root.add_child(l)

func _build_lanterns(th: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(world.map["w"])
	var x := 320.0
	while x < w - 120.0:
		var pos := to3d(Vector2(x, float(world.map["ground"])), -1.3)
		_prop("lantern", pos, 1, 0, 1.2).flip_h = false
		var g := glow_sprite(tex("glow"), Color(th["lantern"], 0.5) * 1.5)
		g.pixel_size = PIXEL * 1.2
		g.position = pos + Vector3(0, 3.8, 0.05)
		map_root.add_child(g)
		var l := light(th["lantern"], 2.2, 6.0)
		l.position = pos + Vector3(0, 4.0, 0.5)
		map_root.add_child(l)
		x += rng.randf_range(560.0, 760.0)
