class_name PaperdollView
extends Control
## The dressed hero in a menu (the character creator, the equipment window): the same
## Paperdoll as in the world, playing an animation, drawn as big as fits with his feet at
## the bottom middle.

const SHADER := preload("res://shaders/paperdoll_ui.gdshader")

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

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [_back, _body, _front]:
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_body.material = mat
	_back.draw.connect(_draw_around.bind(_back, true))
	_body.draw.connect(_draw_body)
	_front.draw.connect(_draw_around.bind(_front, false))
	set_look({})

func set_look(new_look: Dictionary) -> void:
	if doll and new_look == look:
		return
	look = new_look.duplicate(true)
	doll = Paperdoll.dress(look)
	doll.apply(_body.material as ShaderMaterial)
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
	for c in [_back, _body, _front]:
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

## The layers behind the body or in front of it, then (in front) the hat and weapon.
func _draw_around(on: Control, behind: bool) -> void:
	var rect := _frame_rect(on)
	for l in doll.layers:
		if l.behind == behind and l.frames.has_animation(animation):
			var lt := l.frames.get_frame_texture(animation, mini(frame(), l.frames.get_frame_count(animation) - 1))
			on.draw_texture_rect(lt, rect, false, l.tint)
	on.draw_set_transform(Vector2.ZERO)
	var index := Paperdoll.frame_index(_texture())
	var box := _frame_box()
	var s: float = box[0]
	for o in doll.overlays:
		if LookShapes.behind(o.shape) != behind:
			continue
		var at: Variant = Paperdoll.place_overlay(o.shape, index, facing < 0)
		if at == null:
			continue
		var tex := LookShapes.texture(o.shape, o.color)
		var scale: float = at["scale"] * s
		on.draw_set_transform(box[1] + at["centre"] * s, at["angle"], Vector2(-scale if facing < 0 else scale, scale))
		on.draw_texture(tex, -tex.get_size() / 2.0)
	on.draw_set_transform(Vector2.ZERO)
