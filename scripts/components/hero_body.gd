class_name HeroBody
extends RefCounted
## How a hero shows in the world, yours (TDPlayer) or another player's (TDAvatar): his look
## (HeroLookDef) wearing his set pieces (HeroOutfitDef), painted whole frame by frame, and the
## pet trotting after him (TDCompanion). Both kinds of hero draw the same way.
##
##   body = HeroBody.new(self, world, z)                       # in _ready: adds the companion
##   body.draw(face, pet, animation, look, armor, weapon)      # every frame

## What he is doing that shows him standing: these have no frames of their own.
const STANDING := [&"ready", &"turn"]
## What every attack and skill motion plays until the job sets paint their own (HeroLookDef).
const ATTACK := &"attack"
## The moves that last a set time (TDPlayer): their frames are spread over that time whatever
## speed they were cut at, so a longer Dash still plays the whole roll.
const TIMED := {
	&"dash": TDPlayer.DASH_TICKS, &"double_jump": TDPlayer.DOUBLE_JUMP_POSE_TICKS,
	&"slam_land": TDPlayer.SLAM_LAND_TICKS, &"surge_end": TDPlayer.SURGE_END_TICKS,
}

## The pet trotting after them.
var companion: TDCompanion
var visible := true:
	set(v):
		visible = v
		_sprite.visible = v and _sprite.texture != null
var _owner: Node2D
var _world: TDWorld
var _z: float
var _sprite: Sprite3D
## The animation showing and the physics tick it started on, so frames run from its start in
## game time (a slow frame doesn't skip or hold a step).
var _anim := &""
var _since := 0
## What was last shown (look and frame), so the sprite is set up again only when it changes.
var _shown: Array = []
## The look he had when last drawn, for muzzle().
var _look: HeroLookDef

## Adds the companion to `owner`, drawn at depth `z` (TDStage.Z_*).
func _init(owner: Node2D, world: TDWorld, z: float) -> void:
	_owner = owner
	_world = world
	_z = z
	companion = TDCompanion.new()
	owner.add_child(companion)
	_sprite = Sprite3D.new()
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	owner.add_child(_sprite)

## Holds the animation where it is for `ticks` physics ticks (hit-stop, TDPlayer.hit_stop):
## the frame clock starts that much later.
func hold(ticks: int) -> void:
	_since += ticks

## Draws the hero this frame, between his last two ticks (TDWorld.drawn), facing `face`, doing
## `anim` (TDPlayer._animation) in `look`, wearing `armor` and holding `weapon` (EquipDef ids,
## empty for none). His pet (an item id, or empty) follows him.
func draw(face: int, pet: StringName, anim: StringName, look: HeroLookDef, armor := &"", weapon := &"") -> void:
	var at := _world.drawn(_owner)
	companion.set_pet(pet, _owner.position)
	companion.follow(at, face, _z, _world.layout.ground_below(_owner.position))
	if anim != _anim:
		_anim = anim
		_since = Engine.get_physics_frames()
	_look = look
	var frames := look.frames_for(armor, weapon)
	var a := resolve(frames, anim)
	var i := frame_at(frames, a, float(Engine.get_physics_frames() - _since) / Engine.physics_ticks_per_second, TIMED.get(a, 0))
	var shown := [frames, a, i, face]
	if shown != _shown:
		_shown = shown
		var tex := frames.get_frame_texture(a, i)
		TDStage.style_sprite(_sprite, TDStage.TEXEL / TDStage.art_density(tex))
		_sprite.texture = tex
		_sprite.flip_h = face < 0
		_sprite.offset = Vector2(0, tex.get_height() / 2.0)  # his feet at the bottom middle
		_sprite.visible = visible
	_sprite.position = TDStage.to3d(at, _z)

## Where a shot of `anim` (SkillDef.animation) leaves from, from his feet in game pixels
## facing `face`: his punching fist (HeroLookDef.fist).
func muzzle(_anim_name: StringName, face: int) -> Variant:
	return muzzle_of(_look, face) if _look else null

## muzzle() for a hero in `look`.
static func muzzle_of(look: HeroLookDef, face: int) -> Vector2:
	var last := look.frames.get_frame_count(ATTACK) - 1
	var tex := look.frames.get_frame_texture(ATTACK, last)
	var size := tex.get_size()
	var texel := TDStage.TEXEL / TDStage.art_density(tex)
	return Vector2((look.fist.x - size.x / 2.0) * face, look.fist.y - size.y) * texel

## Which of `frames`' animations plays for `anim`: its own, standing for the poses with none
## (STANDING), else the attack (any skill's motion).
static func resolve(frames: SpriteFrames, anim: StringName) -> StringName:
	if frames.has_animation(anim):
		return anim
	return &"idle" if anim in STANDING else ATTACK

## The frame of `anim` showing `seconds` after it started: at its speed and each frame's
## duration (or spread over `ticks` physics ticks, TIMED), round again if it loops, else held
## on its last frame.
static func frame_at(frames: SpriteFrames, anim: StringName, seconds: float, ticks := 0) -> int:
	var n := frames.get_frame_count(anim)
	var total := 0.0
	for i in n:
		total += frames.get_frame_duration(anim, i)
	var speed := total * Engine.physics_ticks_per_second / ticks if ticks > 0 else frames.get_animation_speed(anim)
	var t := seconds * speed
	if frames.get_animation_loop(anim):
		t = fmod(t, total)
	for i in n:
		t -= frames.get_frame_duration(anim, i)
		if t < 0.0:
			return i
	return n - 1
