class_name TDCompanion
extends Node2D
## What comes along with a player (yours or someone else's): the chair they're sitting on
## and the pet trotting after them. The player moves it each frame with `follow`.
## Pets with `sprite_frames` play idle, walk, jump and happy; pets and chairs without art
## of their own use their item icon as their body.

## How far behind its owner a pet keeps, in game pixels.
const PET_GAP := 72.0

var chair: ChairDef
var pet: PetDef
## Where the pet is, in game pixels (its feet).
var pet_pos := Vector2.ZERO
var pet_face := 1
var speech := ""
var speech_t := 0
var _walk := 0.0
var _seat: Sprite3D
var _body: SpriteBase3D

func set_chair(id: StringName) -> void:
	var c := Content.items.get(id) as ChairDef
	if c == chair:
		return
	chair = c
	if _seat:
		_seat.queue_free()
		_seat = null
	if chair and chair.icon:
		_seat = TDStage.sprite(chair.icon, TDStage.TEXEL * chair.seat_scale)
		add_child(_seat)

## Brings out a pet (or puts it away with an empty id) next to `at`.
func set_pet(id: StringName, at: Vector2) -> void:
	var p := Content.items.get(id) as PetDef
	if p == pet:
		return
	pet = p
	if _body:
		_body.queue_free()
	_body = null
	speech_t = 0
	if pet and pet.sprite_frames:
		pet_pos = at
		var a := AnimatedSprite3D.new()
		a.sprite_frames = pet.sprite_frames
		TDStage.style_sprite(a, TDStage.TEXEL * pet.frames_scale)
		_body = a
		add_child(_body)
		_play(&"idle")
	elif pet and pet.icon:
		pet_pos = at
		_body = TDStage.sprite(pet.icon, TDStage.TEXEL * pet.body_scale)
		add_child(_body)
	if _body:
		_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func say(text: String) -> void:
	speech = text
	speech_t = 240

## Puts the chair under the owner's feet and moves the pet toward its spot behind them.
## `ground` is the top of whatever is under the owner (for the pet to walk on).
func follow(owner_feet: Vector2, owner_face: int, z: float, ground: float) -> void:
	if speech_t > 0:
		speech_t -= 1
	if _seat:
		_seat.position = TDStage.to3d(owner_feet + Vector2(0, 2), z - 0.03)
		_seat.flip_h = owner_face < 0
	if _body == null:
		return
	var want := Vector2(owner_feet.x - owner_face * PET_GAP, ground)
	if pet_pos.distance_to(want) > 500.0:
		pet_pos = want # left far behind (a portal, a fall): catch up at once
	var step := (want - pet_pos) * Vector2(0.08, 0.2)
	pet_pos += step
	if absf(step.x) > 0.2:
		pet_face = 1 if step.x > 0 else -1
		_walk += 0.3
	else:
		_walk = 0.0
	var hop := 0.0
	if _body is AnimatedSprite3D:
		if absf(ground - pet_pos.y) > 4.0:
			_play(&"jump") # still dropping or climbing to the owner's ground
		elif _walk > 0.0:
			_play(&"walk")
		else:
			_play(&"happy" if speech_t > 0 else &"idle")
	else:
		hop = absf(sin(_walk)) * 6.0
	_body.position = TDStage.to3d(pet_pos + Vector2(0, -hop), z + 0.01)
	_body.flip_h = pet_face < 0

## How far the sitter is raised to sit on the chair, in game pixels.
func seat_lift() -> float:
	return chair.icon.get_height() * TDStage.TEXEL * chair.seat_scale * 0.45 if chair and chair.icon else 0.0

## The top of the pet's head, for its name tag and speech bubble.
func pet_head() -> Vector2:
	if _body is AnimatedSprite3D:
		var a := _body as AnimatedSprite3D
		var tex := a.sprite_frames.get_frame_texture(a.animation, 0)
		return pet_pos + Vector2(0, -(tex.get_height() * TDStage.TEXEL * pet.frames_scale if tex else 30.0))
	return pet_pos + Vector2(0, -(pet.icon.get_height() * TDStage.TEXEL * pet.body_scale if pet and pet.icon else 30.0))

## Plays one of the pet's animations (or idle, if it hasn't got that one), keeping the
## feet at the bottom of the frame.
func _play(anim: StringName) -> void:
	var a := _body as AnimatedSprite3D
	if not a.sprite_frames.has_animation(anim):
		anim = &"idle"
	if a.animation == anim and a.is_playing():
		return
	a.play(anim)
	var tex := a.sprite_frames.get_frame_texture(anim, 0)
	if tex:
		a.offset = Vector2(0, tex.get_height() / 2.0)
