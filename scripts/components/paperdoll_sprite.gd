class_name PaperdollSprite
extends Node3D
## The dressed hero in the 3D stage. It goes on the hero's AnimatedSprite3D (SpriteRig's
## body): it recolours his skin and clothes with the paperdoll shader, and keeps the layers
## (hair, face, gear) and the hat and weapon pictures (LookShapes) in step with whatever
## frame he is showing.
## SpriteRig.dress() makes one; give it a look with `set_look`.

const SHADER := preload("res://shaders/paperdoll_sprite.gdshader")
## The layers' own: lit like the body, with the same light floor (character_light.gdshaderinc).
const LAYER_SHADER := preload("res://shaders/paperdoll_layer.gdshader")
## How far pictures sit in front of (or behind) the body, in 3D units. Layers are spread
## within that, in drawing order.
const DEPTH := 0.01

var body: AnimatedSprite3D
var doll: Paperdoll
var look := {}
var _material: ShaderMaterial
var _texel := 1.0
var _overlays: Array[Sprite3D] = []
var _layers: Array[AnimatedSprite3D] = []
## The streak his weapon leaves and the flash of a shot.
var trail: WeaponTrail
## The animation and frame showing last time (the trail sweeps between frames).
var _anim := &""
var _index := -1
var _frame := -1

func _init(sprite: AnimatedSprite3D, texel: float) -> void:
	body = sprite
	_texel = texel
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"strip", Paperdoll.STRIP)
	body.material_override = _material
	trail = WeaponTrail.new(body.pixel_size, Paperdoll.FRAME_SIZE)
	trail.position.z = DEPTH * 1.2
	add_child(trail)
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
	var count := doll.layers.size()
	for i in count:
		var l := doll.layers[i]
		var a := AnimatedSprite3D.new()
		a.sprite_frames = l.frames
		TDStage.style_sprite(a, _texel)
		a.material_override = _layer_material(l)
		# back to front: behind ones under the body (z < 0), the rest between it and the pictures
		a.position.z = DEPTH * (0.8 * (i + 1) / (count + 1) - (1.0 if l.behind else 0.0))
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
	if body.animation != _anim or body.frame != _index:
		# one frame on in the same animation: the weapon swept from the last frame to this one
		var prev := _frame if body.animation == _anim and body.frame == _index + 1 else -1
		trail.advance(body.animation, body.frame, prev, frame, doll.weapon_kind, doll.weapon_tint, mirror)
		_anim = body.animation
		_index = body.frame
		_frame = frame
	trail.paused = body.speed_scale == 0.0
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
	for i in _layers.size():
		var a := _layers[i]
		if a.sprite_frames.has_animation(body.animation):
			a.animation = body.animation
			a.frame = mini(body.frame, a.sprite_frames.get_frame_count(body.animation) - 1)
		a.offset = body.offset
		a.flip_h = mirror
		a.modulate = body.modulate

## A layer's material: its frames are regions of one strip, which the shader samples, in
## the layer's colour.
static func _layer_material(l: Paperdoll.Layer) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = LAYER_SHADER
	var tex := l.frames.get_frame_texture(&"idle", 0) if l.frames.has_animation(&"idle") else null
	mat.set_shader_parameter(&"strip", tex.atlas if tex is AtlasTexture else tex)
	l.apply(mat)
	return mat

## A point of the frame (pixels from its top-left) in the body's own space, whose origin
## is the bottom middle of the frame.
func _to_local(px: Vector2) -> Vector3:
	return Vector3(px.x - Paperdoll.FRAME_SIZE.x / 2.0, Paperdoll.FRAME_SIZE.y - px.y, 0.0) * body.pixel_size
