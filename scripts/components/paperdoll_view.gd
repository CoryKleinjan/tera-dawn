class_name PaperdollView
extends Control
## The dressed hero in a menu (the character creator, character select, the equipment
## window), drawn by the game itself so he looks exactly as he does in the world: the same rig
## (HeroBody.make_rig: his layers, shaders and light) standing in a little 3D stage of its own,
## lit like the map showing now (TDStage.light_portrait), seen from the world camera's angle,
## and colour graded like the map. He plays an animation, drawn as big as fits with his feet
## at the bottom middle.

const GRADE_SHADER := preload("res://shaders/portrait.gdshader")
## Seconds between catching up with the map's light (it changes with the map).
const RELIGHT_EVERY := 1.0

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
var _grade := ShaderMaterial.new()
var _relight_in := 0.0

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
	_rig.freeze(true) # the clock here (`time`) picks his frame
	_viewport.add_child(_rig)
	_grade.shader = GRADE_SHADER
	_picture.texture = _viewport.get_texture()
	_picture.material = _grade
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_picture)
	set_look({})

func set_look(new_look: Dictionary) -> void:
	if _rig.paperdoll and new_look == look:
		return
	look = new_look.duplicate(true)
	_rig.dress(look)
	_relight_in = 0.0

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
		_relight_in = 0.0
		return
	if playing:
		time += delta
	var body := _rig.body as AnimatedSprite3D
	if body.animation != animation:
		_rig.play(animation, true)
	body.frame = frame()
	_relight_in -= delta
	if _relight_in <= 0.0:
		TDStage.light_portrait(_environment, _sun, _grade)
		_relight_in = RELIGHT_EVERY
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
