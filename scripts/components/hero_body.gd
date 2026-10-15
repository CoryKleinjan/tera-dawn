class_name HeroBody
extends RefCounted
## How a hero shows in the world, yours (TDPlayer) or another player's (TDAvatar): his painted
## layers stacked frame by frame (HeroLookDef: body, face and hair, then each piece of gear's
## EquipDef.worn), the chair he sits on and the pet trotting after him (TDCompanion). Both kinds
## of hero draw the same way.
##
##   body = HeroBody.new(self, world, z)               # in _ready: adds the companion
##   body.draw(face, chair, pet, animation, worn)      # every frame

const LOOK: HeroLookDef = preload("res://data/hero/look.tres")
## How far in front of the one below it each layer sits (3D units), so the layers stack in
## order without fighting over depth.
const LAYER_STEP := 0.002
## Worn places drawn behind his body, and over it under and over his top (a held weapon or
## off-hand goes where its pin says, HeldDef.Layer).
const BACK := [&"cape"]
const UNDER := [&"bottom", &"shoes"]
const OVER := [&"top", &"gloves"]

## The chair they sit on and the pet trotting after them.
var companion: TDCompanion
var visible := true:
	set(v):
		visible = v
		for s in _layers:
			s.visible = v and s.texture != null
var _owner: Node2D
var _world: TDWorld
var _z: float
## One sprite per layer, back to front, made as needed.
var _layers: Array[Sprite3D] = []
## The animation showing and the physics tick it started on, so frames run from its start in
## game time (a slow frame doesn't skip or hold a step).
var _anim := &""
var _since := 0

## Adds the companion to `owner`, drawn at depth `z` (TDStage.Z_*).
func _init(owner: Node2D, world: TDWorld, z: float) -> void:
	_owner = owner
	_world = world
	_z = z
	companion = TDCompanion.new()
	owner.add_child(companion)

## Draws the hero this frame, between his last two ticks (TDWorld.drawn), facing `face`, doing
## `anim` (TDPlayer._animation) and wearing `worn` (place -> EquipDef). His chair and pet (item
## ids, or empty) follow him.
func draw(face: int, chair: StringName, pet: StringName, anim: StringName, worn: Dictionary) -> void:
	var at := _world.drawn(_owner)
	companion.set_chair(chair)
	companion.set_pet(pet, _owner.position)
	companion.follow(at, face, _z, _world.layout.ground_below(_owner.position))
	if anim != _anim:
		_anim = anim
		_since = Engine.get_physics_frames()
	var weapon: EquipDef = worn.get(&"weapon")
	var frame := LOOK.frame_at(anim, weapon.weapon_kind if weapon else &"", float(Engine.get_physics_frames() - _since) / Engine.physics_ticks_per_second)
	var stack := layers(worn, frame)
	while _layers.size() < stack.size():
		_layers.append(_new_layer())
	for i in _layers.size():
		var s := _layers[i]
		var layer: Variant = stack[i] if i < stack.size() else null
		s.texture = null
		s.rotation = Vector3.ZERO
		if layer is HeldDef:
			_hold(s, layer, frame, face, at, _z + i * LAYER_STEP)
		elif layer is SpriteFrames and layer.has_animation(frame):
			s.texture = layer.get_frame_texture(frame, 0)
			s.offset = Vector2(0, s.texture.get_height() / 2.0)
			s.flip_h = face < 0
			s.position = TDStage.to3d(at, _z + i * LAYER_STEP)
		s.visible = visible and s.texture != null

## Puts `s` showing a held painting pinned on `frame`: its anchor on the pin, turned, mirrored
## when he faces left. Pins are in the pixels of his frames, whose bottom middle is at his feet.
func _hold(s: Sprite3D, held: HeldDef, frame: StringName, face: int, at: Vector2, z: float) -> void:
	var tex := held.texture()
	var size := LOOK.body.get_frame_texture(frame, 0).get_size() if LOOK.body.has_animation(frame) else Vector2.ZERO
	if tex == null or size == Vector2.ZERO:
		return
	var pin: Vector4 = held.pins[frame]
	var texel := TDStage.TEXEL / TDStage.frames_density(LOOK.body)
	s.texture = tex
	s.flip_h = face < 0
	s.offset = Vector2((tex.get_width() / 2.0 - held.anchor.x) * face, held.anchor.y - tex.get_height() / 2.0)
	s.position = TDStage.to3d(at + Vector2((pin.x - size.x / 2.0) * face, pin.y - size.y) * texel, z)
	s.rotation.z = -deg_to_rad(pin.z) * face

## His layers back to front on `frame` for what he wears (place -> EquipDef), each a SpriteFrames
## or a pinned HeldDef: a held piece set behind him, what hangs behind him, his body, his trousers
## and shoes, held pieces under his top, his top, his face, his hair (unless a hat covers it on
## this frame), his hat, held pieces over his clothes, his fists over the grip, held pieces over
## his hands. Each held piece's pin says its layer on that frame. The off-hand only shows while the
## weapon does. Under long sleeves the fists painted with bare forearms are left off.
static func layers(worn: Dictionary, frame: StringName) -> Array:
	var out := []
	var offhand: EquipDef = worn.get(&"shield")
	var hat: EquipDef = worn.get(&"hat")
	var weapon: EquipDef = worn.get(&"weapon")
	var top: EquipDef = worn.get(&"top")
	var shown := weapon != null and _shows(weapon, frame)
	if weapon and not shown:
		offhand = null  # put away with the weapon (sitting, lying down)
	var held := {}  # HeldDef.Layer -> [HeldDef]
	for e: EquipDef in [offhand, weapon]:
		if e and e.held and e.held.shows(frame):
			held.get_or_add(e.held.layer(frame), []).append(e.held)
	out.append_array(held.get(HeldDef.Layer.BEHIND, []))
	_add(out, [offhand] + BACK.map(func(p): return worn.get(p)))
	out.append(LOOK.body)
	_add(out, UNDER.map(func(p): return worn.get(p)))
	out.append_array(held.get(HeldDef.Layer.UNDER_TOP, []))
	_add(out, OVER.map(func(p): return worn.get(p)))
	out.append(LOOK.face)
	if not (hat and hat.hides_hair and hat.worn and hat.worn.has_animation(frame)):
		out.append(LOOK.hair)
	_add(out, [hat, weapon])
	out.append_array(held.get(HeldDef.Layer.OVER_CLOTHES, []))
	if shown and not (top and top.long_sleeves and frame in LOOK.bare_arm_frames):
		out.append(LOOK.hands)
	out.append_array(held.get(HeldDef.Layer.OVER_HANDS, []))
	return out

static func _shows(e: EquipDef, frame: StringName) -> bool:
	return e.held.shows(frame) if e.held else e.worn != null and e.worn.has_animation(frame)

static func _add(out: Array, gear: Array) -> void:
	for e in gear:
		if e and (e as EquipDef).worn:
			out.append((e as EquipDef).worn)

func _new_layer() -> Sprite3D:
	var s := Sprite3D.new()
	TDStage.style_sprite(s, TDStage.TEXEL / TDStage.frames_density(LOOK.body))
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_owner.add_child(s)
	return s
