class_name PaperdollSprite
extends Node3D
## The dressed hero in the 3D stage. It goes on the hero's AnimatedSprite3D (SpriteRig's
## body): it recolours his skin and clothes with the paperdoll shader, and keeps the layers
## (hair, face, gear) in step with whatever frame he is showing, and drawn back to front.
## SpriteRig.dress() makes one; give it a look with `set_look`.

const SHADER := preload("res://shaders/paperdoll_sprite.gdshader")
## The layers' own: lit and drawn like the body (paperdoll_stage.gdshaderinc).
const LAYER_SHADER := preload("res://shaders/paperdoll_layer.gdshader")
## How far layers sit in front of (or behind) the body, in 3D units. Layers are spread
## within that, in drawing order.
const DEPTH := 0.01

var body: AnimatedSprite3D
## His layers have soft edges, so they're drawn like any see-through thing, after what's behind
## them; the stage would sort them by distance, which puts a tall building's middle nearer than
## his feet and a piece on his head nearer or further than his body. So each layer gets its
## own render priority from this one up (TDStage.PRIORITY_PLAYER or PRIORITY_OTHER_PLAYER), in
## drawing order: he's drawn over the scenery and his layers stack the way they do in menus.
var priority := TDStage.PRIORITY_PLAYER
var doll: Paperdoll
var look := {}
var _material: ShaderMaterial
var _texel := 1.0
## One per layer of the doll: an AnimatedSprite3D playing with the body, or for a piece a
## Sprite3D placed on each frame.
var _layers: Array[SpriteBase3D] = []
## The streak his weapon leaves and the flash of a shot.
var trail: WeaponTrail
## The animation and frame showing last time (the trail sweeps between frames).
var _anim := &""
var _index := -1
var _frame := -1

func _init(sprite: AnimatedSprite3D, texel: float, priority_: int) -> void:
	body = sprite
	_texel = texel
	priority = priority_
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"strip", Paperdoll.STRIP)
	body.material_override = _material
	trail = WeaponTrail.new(body.pixel_size, Paperdoll.FRAME_SIZE)
	(trail.material_override as Material).render_priority = priority + TDStage.HERO_PRIORITIES - 1
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
	_material.render_priority = _priority(-1, false)
	for n in _layers:
		n.queue_free()
	_layers.clear()
	var count := doll.layers.size()
	for i in count:
		var l := doll.layers[i]
		var a: SpriteBase3D
		if l.piece:
			a = Sprite3D.new()
		else:
			a = AnimatedSprite3D.new()
			(a as AnimatedSprite3D).sprite_frames = l.frames
		TDStage.style_sprite(a, _texel)
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.material_override = _layer_material(l)
		a.position.z = _depth(i, l.behind)
		(a.material_override as Material).render_priority = _priority(i, l.behind)
		add_child(a)
		_layers.append(a)
	sync()

## Back to front: behind ones under the body (z < 0), the rest between it and the pictures.
func _depth(i: int, behind: bool) -> float:
	var count := doll.layers.size()
	return DEPTH * (0.8 * (i + 1) / (count + 1) - (1.0 if behind else 0.0))

## Layer `i`'s render priority (-1 is the body), in the order _depth stacks them.
func _priority(i: int, behind: bool) -> int:
	var count := doll.layers.size()
	assert(2 * count + 2 < TDStage.HERO_PRIORITIES, "more hero layers than render priorities")
	return priority + i + 1 + (0 if behind else count + 1)

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
	for i in _layers.size():
		var l := doll.layers[i]
		if l.piece:
			_place(_layers[i] as Sprite3D, l, i, frame, mirror)
			continue
		var a := _layers[i] as AnimatedSprite3D
		if a.sprite_frames.has_animation(body.animation):
			a.animation = body.animation
			a.frame = mini(body.frame, a.sprite_frames.get_frame_count(body.animation) - 1)
		a.offset = body.offset
		a.flip_h = mirror
		a.modulate = body.modulate

## Puts a piece where its pose for `frame` says (Paperdoll.Piece), or hides it.
func _place(s: Sprite3D, l: Paperdoll.Layer, i: int, frame: int, mirror: bool) -> void:
	var p: Variant = l.piece.pose(frame)
	s.visible = p != null
	if p == null:
		return
	var pic := l.piece.picture(p)
	var anchor: Vector2 = l.piece.views[p["view"]]["anchor"]
	var side := -1.0 if mirror else 1.0
	s.texture = pic
	(s.material_override as ShaderMaterial).set_shader_parameter(&"strip", pic)
	s.flip_h = mirror
	# the anchor on the node's origin (Sprite3D offsets are in pixels, y up)
	s.offset = Vector2((pic.get_width() / 2.0 - anchor.x) * side, anchor.y - pic.get_height() / 2.0)
	var at: Vector2 = p["at"]
	# frame pixels -> the body's space: its origin is the frame's bottom middle
	s.position = Vector3((at.x - Paperdoll.FRAME_SIZE.x / 2.0) * side, Paperdoll.FRAME_SIZE.y - at.y, 0.0) * body.pixel_size
	s.position.z = _depth(i, p["behind"])
	(s.material_override as Material).render_priority = _priority(i, p["behind"])
	s.rotation.z = -float(p["angle"]) * side
	s.scale = Vector3.ONE * float(p["scale"])
	s.modulate = body.modulate
	l.apply_pose(s.material_override as ShaderMaterial, frame, p)

## A layer's material: its frames are regions of one strip, which the shader samples, in
## the layer's colour.
static func _layer_material(l: Paperdoll.Layer) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = LAYER_SHADER
	if l.piece:
		mat.set_shader_parameter(&"strip", null)  # set per frame (_place): the pose's picture
	else:
		var tex := l.frames.get_frame_texture(&"idle", 0) if l.frames.has_animation(&"idle") else null
		mat.set_shader_parameter(&"strip", tex.atlas if tex is AtlasTexture else tex)
	l.apply(mat)
	return mat
