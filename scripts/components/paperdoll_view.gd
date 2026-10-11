class_name PaperdollView
extends Control
## The dressed hero in a menu (the character creator, the equipment window): the same
## Paperdoll as in the world, playing an animation, drawn as big as fits with his feet at
## the bottom middle.

const SHADER := preload("res://shaders/paperdoll_ui.gdshader")
const LAYER_SHADER := preload("res://shaders/paperdoll_ui_layer.gdshader")

var doll: Paperdoll
var look := {}
var animation := &"idle"
## 1 faces right, -1 faces left.
var facing := 1:
	set(v):
		facing = v
		_redraw()
## Animation clock in seconds; `playing` false holds the current frame.
var time := 0.0
var playing := true
## The largest the hero is drawn, in screen pixels per hero pixel (Paperdoll.ART_SCALE strip
## pixels).
var max_zoom := 4.0

var _back := Control.new()
var _body := Control.new()
var _front := Control.new()
## One per layer of the doll (each with its own colour), under _back or _front.
var _layer_views: Array[Control] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [_back, _body, _front]:
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_body.material = mat
	_body.draw.connect(_draw_body)
	set_look({})

func set_look(new_look: Dictionary) -> void:
	if doll and new_look == look:
		return
	look = new_look.duplicate(true)
	doll = Paperdoll.dress(look)
	doll.apply(_body.material as ShaderMaterial)
	for v in _layer_views:
		v.queue_free()
	_layer_views.clear()
	for l in doll.layers:
		var v := Control.new()
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = LAYER_SHADER
		l.apply(mat)
		v.material = mat
		v.draw.connect(_draw_layer.bind(v, l))
		(_back if l.behind else _front).add_child(v)
		_layer_views.append(v)
	_redraw()

func play(anim: StringName) -> void:
	if Paperdoll.FRAMES.has_animation(anim) and anim != animation:
		animation = anim
		time = 0.0
		_redraw()

func _process(delta: float) -> void:
	if playing and is_visible_in_tree():
		var before := frame()
		time += delta
		if frame() != before:
			_redraw()

## The frame of the animation showing now.
func frame() -> int:
	var f := Paperdoll.FRAMES
	var n := f.get_frame_count(animation)
	var i := int(time * f.get_animation_speed(animation))
	return i % n if f.get_animation_loop(animation) else mini(i, n - 1)

func _redraw() -> void:
	for c in [_back, _body, _front] + _layer_views:
		c.queue_redraw()

## Hero pixels -> this control's pixels: [scale, top-left of the frame].
func _frame_box() -> Array:
	var s := minf(minf(size.x / Paperdoll.FRAME_SIZE.x, size.y / Paperdoll.FRAME_SIZE.y), max_zoom / Paperdoll.ART_SCALE)
	var origin := Vector2((size.x - Paperdoll.FRAME_SIZE.x * s) / 2.0, size.y - Paperdoll.FRAME_SIZE.y * s)
	return [s, origin]

func _texture() -> AtlasTexture:
	return Paperdoll.FRAMES.get_frame_texture(animation, frame()) as AtlasTexture

## Where the frame is drawn, and mirrors `on` for facing left.
func _frame_rect(on: Control) -> Rect2:
	var box := _frame_box()
	if facing < 0: # mirrored about the middle (the frame is centred)
		on.draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-1, 1))
	return Rect2(box[1], Paperdoll.FRAME_SIZE * box[0])

func _draw_body() -> void:
	var tex := _texture()
	_body.draw_texture_rect_region(tex.atlas, _frame_rect(_body), tex.region)
	_body.draw_set_transform(Vector2.ZERO)

## One layer of the doll, in its own colour (its material).
func _draw_layer(on: Control, l: Paperdoll.Layer) -> void:
	if not l.frames.has_animation(animation):
		return
	var rect := _frame_rect(on)
	on.draw_texture_rect(l.frames.get_frame_texture(animation, mini(frame(), l.frames.get_frame_count(animation) - 1)), rect, false)
	on.draw_set_transform(Vector2.ZERO)
