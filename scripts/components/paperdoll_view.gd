class_name PaperdollView
extends Control
## The dressed hero in a menu (the character creator, character select, the equipment
## window), drawn by the game itself so he looks exactly as he does in the world: the same rig
## (HeroBody.make_rig: his layers, the one hero shader and his light) standing in a little 3D
## stage of its own, seen from the world camera's angle. The menus light him with a fixed
## near-white light (not the map's), so he shows his painted colours there. He plays an
## animation, drawn as big as fits with his feet at the bottom middle.

## The menus' light: a near-white sun from the world sun's direction and a near-white fill.
const LIGHT := Color(1.0, 0.98, 0.95)
const SUN_ENERGY := 0.8
const FILL_ENERGY := 0.5

var look := {}
var animation := &"idle"
## 1 faces right, -1 faces left.
var facing := 1:
	set(v):
		facing = v
		_rig.face(facing)
## Animation clock in seconds; `playing` false holds the current frame.
var time := 0.0
var playing := true
## The largest the hero is drawn, in this control's pixels per hero pixel (Paperdoll.ART_SCALE
## strip pixels).
var max_zoom := 4.0

var _viewport := SubViewport.new()
var _picture := TextureRect.new()
var _camera := Camera3D.new()
var _environment := WorldEnvironment.new()
var _sun := DirectionalLight3D.new()
var _rig := HeroBody.make_rig(TDStage.PRIORITY_PLAYER)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X # as the world's (TDStage)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_camera.fov = TDStage.FOV
	_camera.near = 0.1
	_camera.rotation_degrees = Vector3(-TDStage.PITCH, 0, 0)
	_camera.current = true
	_viewport.add_child(_camera)
	_viewport.add_child(_environment)
	_viewport.add_child(_sun)
	_light()
	# the clock here (`time`) picks his frame; the rig still blinks and breathes at idle
	_rig.set_speed(0.0)
	_viewport.add_child(_rig)
	_picture.texture = _viewport.get_texture()
	# his soft edges were blended over a clear background, so the picture is premultiplied
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_picture.material = blend
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_picture)
	set_look({})

## The fixed menu light: no haze, glow or colour grade, a plain tone curve so the light adds
## no colour of its own, and no shadows (characters cast none).
func _light() -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = LIGHT
	e.ambient_light_energy = FILL_ENERGY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_environment.environment = e
	_sun.basis = Basis.looking_at(Vector3(-0.75, -0.48, -0.45).normalized(), Vector3.UP)
	_sun.light_color = LIGHT
	_sun.light_energy = SUN_ENERGY
	_sun.shadow_enabled = false

func set_look(new_look: Dictionary) -> void:
	if _rig.paperdoll and new_look == look:
		return
	look = new_look.duplicate(true)
	_rig.dress(look)

func play(anim: StringName) -> void:
	if Paperdoll.FRAMES.has_animation(anim) and anim != animation:
		animation = anim
		time = 0.0

## The frame of the animation showing now.
func frame() -> int:
	var f := Paperdoll.FRAMES
	var n := f.get_frame_count(animation)
	var i := int(time * f.get_animation_speed(animation))
	return i % n if f.get_animation_loop(animation) else mini(i, n - 1)

func _process(delta: float) -> void:
	var shown := is_visible_in_tree()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	if not shown:
		return
	if playing:
		time += delta
	var body := _rig.body as AnimatedSprite3D
	if body.animation != animation and not (animation == &"idle" and body.animation == &"blink"):
		_rig.play(animation, true)
	body.frame = frame()
	_fit()

## Sizes the picture to this control in screen pixels (so it's drawn 1:1, as the world is)
## and aims the camera so the frame fits with his feet at the bottom middle.
func _fit() -> void:
	# the window stretches the canvas to the screen (canvas_items): undo that and any scaling
	var to_screen := get_global_transform_with_canvas().get_scale() * get_viewport().get_final_transform().get_scale()
	var px := (size * to_screen).ceil()
	var pixels := Vector2i(maxi(1, int(px.x)), maxi(1, int(px.y)))
	if _viewport.size != pixels:
		_viewport.size = pixels
	if size.y <= 0.0:
		return
	# control pixels per strip pixel, and the world height the control shows at his feet
	var frame_size := Paperdoll.FRAME_SIZE
	var k := minf(minf(size.x / frame_size.x, size.y / frame_size.y), max_zoom / Paperdoll.ART_SCALE)
	var shown := size.y * _rig.body.pixel_size / k
	# camera pitched down like the world's, far enough to show `shown` at his distance ahead
	# of it, and high enough that his feet (the rig's origin) sit on the bottom edge
	var t := tan(deg_to_rad(TDStage.FOV) / 2.0)
	var p := deg_to_rad(TDStage.PITCH)
	var rise := (sin(p) + t * cos(p)) / (cos(p) - t * sin(p))
	var back := shown / (2.0 * t) / (rise * sin(p) + cos(p))
	_camera.position = Vector3(0.0, rise * back, back)
