class_name TDEffect
extends Node2D
## A running EffectDef: a glowing flipbook in the stage, with an optional flash of light,
## a burst of sparks and a caption. Removes itself when done.

var world: TDWorld
var def: EffectDef
var face := 1
## The actor it moves with (def.follow_player effects), or null.
var follow: Node2D
## Which way it points (Hitbox.Aim): aimed swings turn it up or down.
var aim := Hitbox.Aim.AHEAD
## A buff's aura: how many ticks it lasts (0: the def's own length) and, round you, the buff
## it ends with (it fades out early when that runs out or is taken off).
var lasts := 0
var buff: StringName
var _had_buff := false
var t := 0
## Ticks a buff's aura takes to fade in and out.
const AURA_FADE_IN := 8
const AURA_FADE_OUT := 24
var sprite: Sprite3D
var flash: OmniLight3D

static func create(w: TDWorld, d: EffectDef, at: Vector2, facing: int, follows: Node2D = null, aiming := Hitbox.Aim.AHEAD) -> TDEffect:
	var e := TDEffect.new()
	e.aim = aiming
	e.follow = follows
	e.world = w
	e.def = d
	e.position = at
	e.face = facing
	return e

func _ready() -> void:
	if not def.frames.is_empty():
		sprite = TDStage.effect_sprite(def.frames[0], Color(def.energy, def.energy, def.energy), def.texel)
		sprite.flip_h = face < 0
		sprite.rotation.z = -_turn()  # the stage's y points up, the game's down
		add_child(sprite)
	if def.light_color.a > 0.0:
		flash = TDStage.light(def.light_color, def.light_energy, def.light_range)
		add_child(flash)
	if def.burst_color.a > 0.0:
		var burst := TDStage.particles(def.burst_color, def.burst_amount, 0.16)
		burst.one_shot = true
		burst.explosiveness = 1.0
		burst.lifetime = 0.35
		burst.direction = Vector3.UP
		burst.spread = 180.0
		burst.gravity = Vector3.ZERO
		burst.initial_velocity_min = 4.0
		burst.initial_velocity_max = 8.0
		burst.damping_min = 12.0
		burst.damping_max = 16.0
		burst.scale_amount_min = 0.5
		burst.scale_amount_max = 1.3
		burst.position = TDStage.to3d(position, TDStage.Z_EFFECT)
		burst.emitting = true
		add_child(burst)
	_sync()

## How far it's turned in game space (y down): a quarter turn from ahead to up or down.
func _turn() -> float:
	match aim:
		Hitbox.Aim.UP:
			return -face * PI / 2.0
		Hitbox.Aim.DOWN:
			return face * PI / 2.0
	return 0.0

func step() -> void:
	t += 1
	if is_instance_valid(follow):
		position = follow.position
	if buff != &"" and Game.me:
		# your copy of the buff can land a moment after its aura does
		var has := Game.me.skills.buffs.has(buff)
		if _had_buff and not has:
			t = maxi(t, lasts - AURA_FADE_OUT)
		_had_buff = _had_buff or has
	if t > length():
		queue_free()
		return
	_sync()

## Its length in ticks.
func length() -> int:
	return lasts if lasts > 0 else def.duration()

## Ends a buff's aura now with a short fade (the buff was cast again).
func fade() -> void:
	lasts = mini(lasts, t + AURA_FADE_OUT)

func _sync() -> void:
	var k := float(t) / length()
	var at := position + Vector2(def.offset.x * face, def.offset.y).rotated(_turn())
	if sprite:
		var i := mini(int(t / 60.0 * def.fps), def.frames.size() - 1)
		if def.lifetime > 0 or lasts > 0:
			i = int(t / 60.0 * def.fps) % def.frames.size()  # long effects loop their frames
		sprite.texture = def.frames[i]
		sprite.position = TDStage.to3d(at, TDStage.Z_EFFECT)
		if lasts > 0:
			sprite.transparency = 1.0 - clampf(minf(float(t) / AURA_FADE_IN, float(lasts - t) / AURA_FADE_OUT), 0.0, 1.0)
		elif def.fade_out:
			sprite.transparency = clampf((k - 0.6) / 0.4, 0.0, 1.0)
	if flash:
		flash.position = TDStage.to3d(at, TDStage.Z_EFFECT + 0.6)
		flash.light_energy = def.light_energy * (1.0 - k)

## The caption, drawn by the overlay so it stays sharp.
func draw_caption(ci: CanvasItem, at: Vector2) -> void:
	if def.caption == "" and def.caption_art == null:
		return
	var k := float(t) / def.duration()
	if def.caption_art:
		var size := def.caption_art.get_size() * def.caption_art_width / def.caption_art.get_width()
		var pop := minf(1.0, t / 8.0)  # springs up from small in the first few frames
		var c := at + Vector2(0, -120 - k * 40)
		ci.draw_texture_rect(def.caption_art, Rect2(c - size * pop / 2.0, size * pop), false, Color(1, 1, 1, 1.0 - k * k))
		return
	DrawUtil.text(ci, Game.num_font, at + Vector2(0, -110 - k * 40), def.caption, 40,
		Color(Palette.SUN, 1.0 - k), 0, 10, Color(Palette.PLUM, 1.0 - k))
