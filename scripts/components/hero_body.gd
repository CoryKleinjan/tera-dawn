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
## Worn places drawn behind his body, and over it under and over his top; the off-hand goes
## behind him, or under his top when he holds it in front of his rear arm (EquipDef.worn_in_front).
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
		var frames: SpriteFrames = stack[i] if i < stack.size() else null
		s.texture = frames.get_frame_texture(frame, 0) if frames and frames.has_animation(frame) else null
		s.visible = visible and s.texture != null
		if s.texture:
			s.offset = Vector2(0, s.texture.get_height() / 2.0)
			s.flip_h = face < 0
			s.position = TDStage.to3d(at, _z + i * LAYER_STEP)

## His layers back to front on `frame` for what he wears (place -> EquipDef): what hangs behind
## him, his body, his trousers and shoes, an off-hand held in front, his top, his face, his hair
## (unless a hat covers it on this frame), his hat and his weapon. On the frames in
## HeroLookDef.weapon_behind (a sword raised behind his head) the weapon goes behind him instead.
static func layers(worn: Dictionary, frame: StringName) -> Array[SpriteFrames]:
	var out: Array[SpriteFrames] = []
	var offhand: EquipDef = worn.get(&"shield")
	var hat: EquipDef = worn.get(&"hat")
	var weapon: EquipDef = worn.get(&"weapon")
	var behind := frame in LOOK.weapon_behind
	var back := BACK.map(func(p): return worn.get(p))
	if offhand and not offhand.worn_in_front:
		back.push_front(offhand)
	if behind:
		back.push_front(weapon)
	_add(out, back)
	out.append(LOOK.body)
	_add(out, UNDER.map(func(p): return worn.get(p)))
	if offhand and offhand.worn_in_front:
		_add(out, [offhand])
	_add(out, OVER.map(func(p): return worn.get(p)))
	out.append(LOOK.face)
	if not (hat and hat.hides_hair and hat.worn and hat.worn.has_animation(frame)):
		out.append(LOOK.hair)
	_add(out, [hat, null if behind else weapon])
	return out

static func _add(out: Array[SpriteFrames], gear: Array) -> void:
	for e in gear:
		if e and (e as EquipDef).worn:
			out.append((e as EquipDef).worn)

func _new_layer() -> Sprite3D:
	var s := Sprite3D.new()
	TDStage.style_sprite(s, TDStage.TEXEL / TDStage.frames_density(LOOK.body))
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_owner.add_child(s)
	return s
