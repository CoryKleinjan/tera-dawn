class_name SpriteRig
extends Node3D
## The 3D body of a 2D actor: an animated painted sprite standing in the stage,
## and optionally a light and glowing particles. Characters cast no shadows.
##
## Actors keep their logic in 2D game pixels and call `place()` every frame. Animations
## come from a SpriteFrames resource; when an actor only has a single image, the rig
## animates it procedurally (breathing, hopping, recoiling, flattening).

## The usual animation names. A SpriteFrames without one of these falls back along FALLBACK.
const FALLBACK := {
	&"move": &"idle", &"attack": &"move", &"hurt": &"idle", &"die": &"hurt",
	&"walk": &"move", &"run": &"walk", &"fall": &"jump", &"land": &"idle",
}
## How long a flash of colour (pulse(), a monster's rage) takes to fade, in seconds.
const PULSE_TIME := 0.45

var body: SpriteBase3D
var light: OmniLight3D
var aura: CPUParticles3D
var current := &"idle"
## Procedural animation clock (seconds), for single-image actors.
var _t := randf() * 10.0
var _frames: SpriteFrames
var _flash := false
var _tint := Color.WHITE
var _lift := 0.0
## How fast the animation plays (a walk matched to the walking speed), and whether hit-stop
## holds it still.
var _speed := 1.0
var _frozen := false
## How squashed the body is right now by a hit (0 none, 1 most); see squash().
var _squash := 0.0
## A glow pulsing on the body (a monster winding up an attack), 0 for none.
var _glow := 0.0
## A flash of colour fading off the body (see pulse), and how much of it is left (1 to 0).
var _pulse_color := Color.WHITE
var _pulse := 0.0
## Stands perfectly still (see hold_still): no animation or procedural breathing.
var _still := false

## Builds the sprite. Pass `frames` for an animated actor or `texture` for a single image.
## `texel` is the size of one art pixel in game pixels (TDStage.art_density texels each).
func setup(frames: SpriteFrames, texture: Texture2D, texel: float) -> void:
	_frames = frames
	if frames:
		var a := AnimatedSprite3D.new()
		a.sprite_frames = frames
		body = a
	else:
		var s := Sprite3D.new()
		s.texture = texture
		body = s
	TDStage.style_sprite(body, texel / (TDStage.frames_density(frames) if frames else TDStage.art_density(texture)))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	_fit_offset()
	play(&"idle")

## Keeps the actor standing perfectly still on its first idle frame, with no breathing
## (NPCs, whose idle frames are separate drawings that shift them around). Hits still squash.
func hold_still() -> void:
	_still = true
	if body is AnimatedSprite3D:
		var a := body as AnimatedSprite3D
		a.stop()
		a.frame = 0
	body.scale = Vector3.ONE
	body.rotation.z = 0.0
	_lift = 0.0

func add_light(col: Color, energy: float, height_px: float) -> void:
	light = TDStage.light(col, energy, 3.5)
	light.position = Vector3(0, height_px / TDStage.PX, 0.4)
	body.add_child(light)

func add_aura(col: Color, height_px: float) -> void:
	aura = TDStage.particles(col, 18, 0.12)
	aura.lifetime = 1.2
	aura.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	aura.emission_box_extents = Vector3(0.5, 0.25, 0.1)
	aura.direction = Vector3.UP
	aura.spread = 25.0
	aura.gravity = Vector3(0, 0.8, 0)
	aura.initial_velocity_min = 0.6
	aura.initial_velocity_max = 1.4
	aura.position = Vector3(0, height_px / TDStage.PX, 0.1)
	body.add_child(aura)

func has_animation(anim: StringName) -> bool:
	return _frames != null and _frames.has_animation(anim)

## Plays an animation (or the closest one this sprite has). Calling it again with the
## same name keeps it going; `from_start` restarts it (a second swing of the same attack).
func play(anim: StringName, from_start := false) -> void:
	if _still:
		return
	var a := anim
	if _frames:
		while not _frames.has_animation(a) and FALLBACK.has(a):
			a = FALLBACK[a]
		if not _frames.has_animation(a):
			a = &"idle"
		var s := body as AnimatedSprite3D
		if s.animation != a or from_start:
			s.play(a)
			s.frame = 0
			_fit_offset()
		elif not s.is_playing() and _frames.get_animation_loop(a):
			s.play(a)
	elif a != current or from_start:
		_t = 0.0
	current = anim

## 1 faces right, -1 faces left (the art faces right).
func face(dir: int) -> void:
	body.flip_h = dir < 0

## Puts the feet at a 2D game position, `z` units in front of (+) or behind (-) the play line.
func place(feet: Vector2, z: float) -> void:
	body.position = TDStage.to3d(feet + Vector2(0, -_lift), z)

## Tints the sprite bright red-white while it is hit.
func set_flash(on: bool) -> void:
	if on != _flash:
		_flash = on
		_apply_modulate()

## Squashes the body for a moment (taking a hit); it springs back by itself.
func squash(amount := 1.0) -> void:
	_squash = maxf(_squash, amount)

## Freezes the animation for a few frames (hit-stop) or lets it run again.
func freeze(on: bool) -> void:
	_frozen = on
	_apply_speed()

## Plays the animation faster or slower (1 is as drawn), e.g. the walk cycle matched to how
## fast the actor moves so the feet don't slide.
func set_speed(scale: float) -> void:
	_speed = scale
	_apply_speed()

func _apply_speed() -> void:
	if body is AnimatedSprite3D:
		(body as AnimatedSprite3D).speed_scale = 0.0 if _frozen else _speed

## A warm pulsing glow (0 off .. 1 full), e.g. a monster about to strike.
func set_glow(amount: float) -> void:
	if not is_equal_approx(amount, _glow):
		_glow = amount
		_apply_modulate()

func _apply_modulate() -> void:
	if _flash:
		body.modulate = Color(2.2, 1.0, 1.0)
	else:
		var col := _tint.lerp(Color(1.9, 1.35, 0.9), _glow * 0.6)
		if _pulse > 0.0:
			# brighter than white, so it reads as light on it rather than paint
			var bright := Color(_pulse_color.r * 2.2, _pulse_color.g * 2.2, _pulse_color.b * 2.2)
			col = col.lerp(bright, _pulse * _pulse_color.a * 0.7)
		body.modulate = col

## A flash of `col` over the body that fades out (a monster's rage). Transparent does
## nothing.
func pulse(col: Color) -> void:
	if col.a > 0.0:
		_pulse_color = col
		_pulse = 1.0
		_apply_modulate()

## A colour the sprite is always tinted with (NPCs and monsters that share art).
func set_tint(col: Color) -> void:
	_tint = col
	_apply_modulate()

## 1 is solid, 0 is invisible.
func set_opacity(alpha: float) -> void:
	body.transparency = 1.0 - alpha
	body.visible = alpha > 0.01
	if light:
		light.visible = body.visible
	if aura:
		aura.emitting = alpha > 0.5

func _fit_offset() -> void:
	var tex: Texture2D
	if body is AnimatedSprite3D:
		var a := body as AnimatedSprite3D
		tex = a.sprite_frames.get_frame_texture(a.animation, 0)
	else:
		tex = (body as Sprite3D).texture
	if tex:
		body.offset = Vector2(0, tex.get_height() / 2.0)  # origin at the bottom centre

func _process(delta: float) -> void:
	if body == null:
		return
	_squash = move_toward(_squash, 0.0, delta * 6.0)
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta / PULSE_TIME)
		_apply_modulate()
	var squash_xy := Vector2(1.0 + 0.18 * _squash, 1.0 - 0.15 * _squash)
	if _frames or _still:
		body.scale = Vector3(squash_xy.x, squash_xy.y, 1.0)
		return
	# single-image actors: move the sprite procedurally
	_t += delta
	var sx := 1.0
	var sy := 1.0
	var rot := 0.0
	var lift := 0.0
	match current:
		&"move", &"walk", &"run", &"attack":
			var hop := absf(sin(_t * 7.0))
			lift = hop * 5.0
			sy = 1.0 + hop * 0.06
			sx = 1.0 - hop * 0.04
		&"hurt":
			rot = 0.18 * (1.0 if body.flip_h else -1.0)
			sx = 0.94
			sy = 1.04
		&"die":
			sy = maxf(0.25, 1.0 - _t * 3.0)
			sx = 1.0 + (1.0 - sy) * 0.4
		_:
			var breath := sin(_t * 2.6)
			sy = 1.0 + breath * 0.035
			sx = 1.0 - breath * 0.025
	body.scale = Vector3(sx * squash_xy.x, sy * squash_xy.y, 1.0)
	body.rotation.z = rot
	_lift = lift
