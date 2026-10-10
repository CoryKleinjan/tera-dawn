class_name SpriteRig
extends Node3D
## The 3D body of a 2D actor: an animated pixel-art sprite standing in the HD-2D stage,
## a soft shadow under it, and optionally a light and glowing particles. Heroes are also
## dressed (`dress`): their look and gear are drawn on them by a PaperdollSprite.
##
## Actors keep their logic in 2D game pixels and call `place()` every frame. Animations
## come from a SpriteFrames resource; when an actor only has a single image, the rig
## animates it procedurally (breathing, hopping, recoiling, flattening).

## The usual animation names. A SpriteFrames without one of these falls back along FALLBACK.
const FALLBACK := {
	&"move": &"idle", &"attack": &"move", &"hurt": &"idle", &"die": &"hurt",
	&"walk": &"move", &"run": &"walk", &"fall": &"jump", &"land": &"idle",
}

var body: SpriteBase3D
var shadow: Sprite3D
var light: OmniLight3D
var aura: CPUParticles3D
## Draws the character's look on the body (heroes only, see `dress`).
var paperdoll: PaperdollSprite
var current := &"idle"
## Procedural animation clock (seconds), for single-image actors.
var _t := randf() * 10.0
var _frames: SpriteFrames
var _flash := false
var _tint := Color.WHITE
var _lift := 0.0
## How squashed the body is right now by a hit (0 none, 1 most); see squash().
var _squash := 0.0
## A glow pulsing on the body (a monster winding up an attack), 0 for none.
var _glow := 0.0

## Builds the sprite. Pass `frames` for an animated actor or `texture` for a single image.
## `texel` is the size of one texture pixel in game pixels.
func setup(frames: SpriteFrames, texture: Texture2D, texel: float, shadow_width: float) -> void:
	_frames = frames
	if frames:
		var a := AnimatedSprite3D.new()
		a.sprite_frames = frames
		body = a
	else:
		var s := Sprite3D.new()
		s.texture = texture
		body = s
	TDStage.style_sprite(body, texel)
	add_child(body)
	_fit_offset()
	shadow = TDStage.shadow_sprite(shadow_width)
	add_child(shadow)
	play(&"idle")

## Draws a look (Character.look()) on the body, which must be the hero's animated sprite.
## Call again whenever the look changes; an unchanged look costs nothing.
func dress(look: Dictionary) -> void:
	if paperdoll == null:
		paperdoll = PaperdollSprite.new(body as AnimatedSprite3D, (body as AnimatedSprite3D).pixel_size * TDStage.PX)
		body.add_child(paperdoll)
	paperdoll.set_look(look)

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
## `shadow_y` is the ground under the actor, or NAN for no shadow (climbing, fainted).
func place(feet: Vector2, z: float, shadow_y := NAN) -> void:
	body.position = TDStage.to3d(feet + Vector2(0, -_lift), z)
	shadow.visible = not is_nan(shadow_y)
	if shadow.visible:
		# on the platform top, just behind its front edge
		shadow.position = TDStage.to3d(Vector2(feet.x, shadow_y), -0.25) + Vector3(0, 0.02, 0)
		var lift := clampf((shadow_y - feet.y) / 120.0, 0.0, 0.7)
		shadow.modulate.a = 1.0 - lift

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
	if body is AnimatedSprite3D:
		(body as AnimatedSprite3D).speed_scale = 0.0 if on else 1.0

## A warm pulsing glow (0 off .. 1 full), e.g. a monster about to strike.
func set_glow(amount: float) -> void:
	if not is_equal_approx(amount, _glow):
		_glow = amount
		_apply_modulate()

func _apply_modulate() -> void:
	if _flash:
		body.modulate = Color(2.2, 1.0, 1.0)
	else:
		body.modulate = _tint.lerp(Color(1.9, 1.35, 0.9), _glow * 0.6)

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
	var squash_xy := Vector2(1.0 + 0.18 * _squash, 1.0 - 0.15 * _squash)
	if _frames:
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
