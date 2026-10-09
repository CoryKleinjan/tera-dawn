class_name PaperdollSprite
extends Node3D
## The dressed hero in the 3D stage. It goes on the hero's AnimatedSprite3D (SpriteRig's
## body): it recolours and hides parts of him with the paperdoll shader, and keeps the
## stand-ins (LookShapes) and layered art in step with whatever frame he is showing.
## SpriteRig.dress() makes one; give it a look with `set_look`.

const SHADER := preload("res://shaders/paperdoll_sprite.gdshader")
## How far stand-ins and layers sit in front of (or behind) the body, in 3D units.
const DEPTH := 0.01

var body: AnimatedSprite3D
var doll: Paperdoll
var look := {}
var _material: ShaderMaterial
var _texel := 1.0
var _overlays: Array[Sprite3D] = []
var _layers: Array[AnimatedSprite3D] = []

func _init(sprite: AnimatedSprite3D, texel: float) -> void:
	body = sprite
	_texel = texel
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"strip", Paperdoll.STRIP)
	body.material_override = _material
	set_look({})

## Dresses the hero in a look (Character.look()). Does nothing if it hasn't changed.
func set_look(new_look: Dictionary) -> void:
	if doll and new_look == look:
		return
	look = new_look.duplicate(true)
	doll = Paperdoll.dress(look)
	doll.apply(_material)
	for n in _overlays + _layers:
		n.queue_free()
	_overlays.clear()
	_layers.clear()
	for o in doll.overlays:
		var s := Sprite3D.new()
		s.texture = LookShapes.texture(o.shape, o.color)
		TDStage.style_sprite(s, _texel)
		add_child(s)
		_overlays.append(s)
	for l in doll.layers:
		var a := AnimatedSprite3D.new()
		a.sprite_frames = l.frames
		TDStage.style_sprite(a, _texel)
		a.position.z = -DEPTH if l.behind else DEPTH * 0.5
		add_child(a)
		_layers.append(a)
	sync()

func _process(_delta: float) -> void:
	sync()

## Moves every stand-in and layer to the frame the body is showing.
func sync() -> void:
	if body.sprite_frames == null:
		return
	var tex := body.sprite_frames.get_frame_texture(body.animation, body.frame)
	var frame := Paperdoll.frame_index(tex)
	var mirror := body.flip_h
	for i in _overlays.size():
		var s := _overlays[i]
		var shape := doll.overlays[i].shape
		var at: Variant = Paperdoll.place_overlay(shape, frame, mirror)
		s.visible = at != null
		if at == null:
			continue
		s.position = _to_local(at["centre"]) + Vector3(0, 0, -DEPTH if LookShapes.behind(shape) else DEPTH)
		s.rotation.z = -at["angle"]
		s.scale = Vector3(at["scale"], at["scale"], 1.0)
		s.flip_h = mirror
		s.modulate = body.modulate
	for a in _layers:
		if a.sprite_frames.has_animation(body.animation):
			a.animation = body.animation
			a.frame = mini(body.frame, a.sprite_frames.get_frame_count(body.animation) - 1)
		a.offset = body.offset
		a.flip_h = mirror
		a.modulate = body.modulate

## A point of the frame (pixels from its top-left) in the body's own space, whose origin
## is the bottom middle of the frame.
func _to_local(px: Vector2) -> Vector3:
	return Vector3(px.x - Paperdoll.FRAME_SIZE.x / 2.0, Paperdoll.FRAME_SIZE.y - px.y, 0.0) * body.pixel_size
