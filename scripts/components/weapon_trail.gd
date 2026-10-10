class_name WeaponTrail
extends MeshInstance3D
## The streak a swung weapon leaves, and the flash of a bow or gun going off. When the hero's
## frame moves on mid-swing, the band his blade swept between the two frames glows and fades;
## when a bow or gun reaches its firing frame, a quick flash pops at the string or muzzle.
## PaperdollSprite drives it with the frames he shows; everything is in the body's own space,
## in frame pixels (the weapon's place comes from Paperdoll.hold).

## Animations whose frames sweep the blade.
const SWEEPS: Array[StringName] = [&"attack", &"slash", &"heavy"]
## Animations that fire, and on which of their frames.
const FIRES := {&"shoot": 1, &"gun": 1}
## Weapon kinds that leave a streak when swung.
const BLADES: Array[StringName] = [&"sword", &"wand", &"staff"]
## Seconds a streak or flash takes to fade.
const FADE := 0.18
const FLASH_FADE := 0.12
## The streak covers the blade from this share of its reach out to its tip.
const INNER := 0.3
## Slices across a streak (more is a smoother curve).
const STEPS := 10
## How bright a streak and a flash are (HDR, so they catch the bloom).
const GLOW := Color(1.7, 1.5, 1.2)
## A flash's size in frame pixels.
const FLASH_SIZE := 18.0

var _texel := 1.0
var _frame_size := Vector2.ONE
var _mesh := ImmediateMesh.new()
## Streaks still fading: {from: [grip, angle], to: [grip, angle], reach, colour, t}.
var _streaks: Array[Dictionary] = []
## Flashes still fading: {at: frame pixels, t}.
var _flashes: Array[Dictionary] = []
## Hit-stop holds the streak still too.
var paused := false

func _init(texel: float, frame_size: Vector2) -> void:
	_texel = texel
	_frame_size = frame_size
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := TDStage.additive_material(Color.WHITE)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m

## The hero's frame moved on from `prev` to `frame` (Paperdoll frame indices), as frame
## `index` of `anim`, holding a `kind` weapon in `tint`; `mirror` when he faces left.
func advance(anim: StringName, index: int, prev: int, frame: int, kind: StringName, tint: Color, mirror: bool) -> void:
	if anim in SWEEPS and kind in BLADES and index > 0:
		var a: Variant = Paperdoll.hold(prev, kind)
		var b: Variant = Paperdoll.hold(frame, kind)
		if a != null and b != null:
			_streaks.append({"from": _side(a, mirror), "to": _side(b, mirror), "reach": Paperdoll.weapon_reach(kind),
				"colour": GLOW * tint.lerp(Color.WHITE, 0.6), "t": 0.0})
	if FIRES.get(anim, -1) == index:
		var h: Variant = Paperdoll.hold(frame, kind)
		if h != null:
			var aim: Array = _side(h, mirror)
			var out := Paperdoll.weapon_reach(kind) if kind == &"gun" else 6.0
			_flashes.append({"at": aim[0] + Vector2.from_angle(aim[1]) * out, "t": 0.0})

## A hold [grip, angle] for the way he faces.
func _side(h: Dictionary, mirror: bool) -> Array:
	if not mirror:
		return [h["grip"], h["angle"]]
	return [Vector2(_frame_size.x - h["grip"].x, h["grip"].y), PI - h["angle"]]

func _process(delta: float) -> void:
	if not paused:
		for s in _streaks:
			s["t"] += delta
		for f in _flashes:
			f["t"] += delta
		_streaks = _streaks.filter(func(s: Dictionary) -> bool: return s["t"] < FADE)
		_flashes = _flashes.filter(func(f: Dictionary) -> bool: return f["t"] < FLASH_FADE)
	_mesh.clear_surfaces()
	if _streaks.is_empty() and _flashes.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in _streaks:
		_draw_streak(s)
	for f in _flashes:
		_draw_flash(f)
	_mesh.surface_end()

func _draw_streak(s: Dictionary) -> void:
	var fade: float = 1.0 - s["t"] / FADE
	var from: Array = s["from"]
	var to: Array = s["to"]
	var turn := angle_difference(from[1], to[1])
	var reach: float = s["reach"]
	var col: Color = s["colour"]
	var prev_in := Vector3.ZERO
	var prev_out := Vector3.ZERO
	for i in STEPS + 1:
		var k := float(i) / STEPS
		var grip: Vector2 = (from[0] as Vector2).lerp(to[0], k)
		var dir := Vector2.from_angle(from[1] + turn * k)
		var p_in := _local(grip + dir * reach * INNER)
		var p_out := _local(grip + dir * reach)
		if i > 0:
			# brightest at the leading edge, fading back along the sweep and in toward the hand
			var a0 := col * Color(1, 1, 1, fade * (k - 1.0 / STEPS))
			var a1 := col * Color(1, 1, 1, fade * k)
			var clear := Color(col, 0.0)
			_vertex(prev_in, clear)
			_vertex(prev_out, a0)
			_vertex(p_out, a1)
			_vertex(prev_in, clear)
			_vertex(p_out, a1)
			_vertex(p_in, clear)
		prev_in = p_in
		prev_out = p_out

func _draw_flash(f: Dictionary) -> void:
	var k: float = f["t"] / FLASH_FADE
	var r := FLASH_SIZE * (0.5 + k) / 2.0
	var col := GLOW * Color(1, 1, 1, 1.0 - k)
	var c: Vector2 = f["at"]
	var corners := [c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		_mesh.surface_set_color(col)
		_mesh.surface_set_uv(uvs[i])
		_mesh.surface_add_vertex(_local(corners[i]))

## A streak vertex: the middle of the soft-dot texture, so only the colour shows.
func _vertex(at: Vector3, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_set_uv(Vector2(0.5, 0.5))
	_mesh.surface_add_vertex(at)

## Frame pixels -> the body's space (origin at the frame's bottom middle).
func _local(px: Vector2) -> Vector3:
	return Vector3(px.x - _frame_size.x / 2.0, _frame_size.y - px.y, 0.0) * _texel
