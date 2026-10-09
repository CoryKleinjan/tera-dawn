class_name TDEffect
extends Node2D
## A running EffectDef: a glowing flipbook in the stage, with an optional flash of light,
## a burst of sparks and a caption. Removes itself when done.

var world: TDWorld
var def: EffectDef
var face := 1
## The actor it moves with (def.follow_player effects), or null.
var follow: Node2D
var t := 0
var sprite: Sprite3D
var flash: OmniLight3D

static func create(w: TDWorld, d: EffectDef, at: Vector2, facing: int, follows: Node2D = null) -> TDEffect:
	var e := TDEffect.new()
	e.follow = follows
	e.world = w
	e.def = d
	e.position = at
	e.face = facing
	return e

func _ready() -> void:
	if not def.frames.is_empty():
		sprite = TDStage.glow_sprite(def.frames[0], Color(def.energy, def.energy, def.energy), def.texel)
		sprite.flip_h = face < 0
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

func step() -> void:
	t += 1
	if is_instance_valid(follow):
		position = follow.position
	if t > def.duration():
		queue_free()
		return
	_sync()

func _sync() -> void:
	var k := float(t) / def.duration()
	var at := position + Vector2(def.offset.x * face, def.offset.y)
	if sprite:
		var i := mini(int(t / 60.0 * def.fps), def.frames.size() - 1)
		if def.lifetime > 0:
			i = int(t / 60.0 * def.fps) % def.frames.size()  # long effects loop their frames
		sprite.texture = def.frames[i]
		sprite.position = TDStage.to3d(at, TDStage.Z_EFFECT)
		if def.fade_out:
			sprite.transparency = clampf((k - 0.6) / 0.4, 0.0, 1.0)
	if flash:
		flash.position = TDStage.to3d(at, TDStage.Z_EFFECT + 0.6)
		flash.light_energy = def.light_energy * (1.0 - k)

## The caption ("LEVEL UP!"), drawn by the overlay so it stays sharp.
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
