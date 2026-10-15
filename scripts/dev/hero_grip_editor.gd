extends Control
## Places the hero's held pieces (weapons and off-hands, HeldDef) by hand, frame by frame: open
## scenes/dev/hero_grip_editor.tscn in Godot and play it (F6). It draws him the way the game does
## (HeroBody.layers) in one job's starter gear. Drag the piece to move it, the mouse wheel turns
## it, and Save writes the pins back to data/hero/held/, so each save replaces the last.
##
##   Left/Right  frame         Tab        next piece       Wheel (Shift: fine)  turn
##   PgUp/PgDn   layer         H          show/hide here   C    copy the previous frame's pin
##   Space       play the walk Ctrl+S     save

const ZOOM := 3.0
## Frames in the order they are stepped through (then the rest, A to Z).
const ORDER := [&"idle1", &"idle2", &"walk1", &"walk2", &"walk3", &"jump", &"hurt", &"crouch", &"sit", &"faint"]
const BG := Color(0.86, 0.83, 0.77)
const LAYER_NAMES := ["behind him", "under his top", "over his clothes", "over his hands"]

var _jobs: Array[StringName] = []
var _job := 0
var _outfit: Dictionary = {}  # place -> EquipDef
var _pieces: Array[EquipDef] = []
var _piece := 0
var _frames: Array[StringName] = []
var _frame := 0
var _dirty := {}  # HeldDef -> true
var _drag := false
var _grab := Vector2.ZERO
var _playing := false
var _play_t := 0.0
var _info: Label
var _status: Label

func _ready() -> void:
	var rest: Array[StringName] = []
	for anim in HeroBody.LOOK.body.get_animation_names():
		if anim not in ORDER:
			rest.append(anim)
	rest.sort()
	for f in ORDER + rest:
		if HeroBody.LOOK.body.has_animation(f):
			_frames.append(f)
	for item in Content.items.values():
		var e := item as EquipDef
		if e and e.held:
			for j in e.jobs:
				if j not in _jobs:
					_jobs.append(j)
	_jobs.sort()
	_build_ui()
	_pick_job(maxi(_jobs.find(&"warrior"), 0))

func _build_ui() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 12)
	add_child(bar)
	for b in [["Job", _next_job], ["< Frame", func(): _step(-1)], ["Frame >", func(): _step(1)],
			["Piece", _next_piece], ["Layer down", func(): _layer(-1)], ["Layer up", func(): _layer(1)],
			["Show/Hide here", _toggle], ["Copy previous", _copy_prev], ["Play walk", _play], ["Save", _save]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		bar.add_child(btn)
	_info = Label.new()
	_info.position = Vector2(12, 52)
	add_child(_info)
	_status = Label.new()
	_status.position = Vector2(12, 76)
	add_child(_status)

func _pick_job(i: int) -> void:
	_job = i
	_outfit.clear()
	_pieces.clear()
	var job := _jobs[i] if i < _jobs.size() else &""
	for item in Content.items.values():
		var e := item as EquipDef
		var place: StringName = Equipment.PLACES_FOR[e.slot][0] if e else &""
		if e and job in e.jobs and (e.worn or e.held) and not _outfit.has(place):
			_outfit[place] = e
			if e.held:
				_pieces.append(e)
	_pieces.sort_custom(func(a, b): return a.slot < b.slot)  # the weapon first
	_piece = 0
	queue_redraw()

func _held() -> HeldDef:
	return _pieces[_piece].held if _piece < _pieces.size() else null

func _f() -> StringName:
	return _frames[_frame]

func _origin() -> Vector2:
	return size / 2.0 - _frame_size() * ZOOM / 2.0 + Vector2(0, 30)

func _frame_size() -> Vector2:
	return HeroBody.LOOK.body.get_frame_texture(_f(), 0).get_size()

func _process(delta: float) -> void:
	if _playing:
		_play_t += delta
		var walk: Array = HeroBody.LOOK.animations[&"walk"]["frames"]
		var i := int(_play_t * float(HeroBody.LOOK.animations[&"walk"]["fps"])) % walk.size()
		_frame = _frames.find(walk[i])
		queue_redraw()
	var h := _held()
	var pin_text := "not shown on this frame (H shows it)"
	if h and h.shows(_f()):
		var p: Vector4 = h.pins[_f()]
		pin_text = "at %.1f, %.1f  turned %.1f°  %s" % [p.x, p.y, p.z, LAYER_NAMES[int(p.w)]]
	_info.text = "%s   frame %s (%d/%d)   %s: %s" % [_jobs[_job] if _jobs else "", _f(), _frame + 1,
		_frames.size(), _pieces[_piece].display_name if h else "no piece", pin_text]

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var o := _origin()
	draw_rect(Rect2(o, _frame_size() * ZOOM), Color(0, 0, 0, 0.06), false)
	for layer in HeroBody.layers(_outfit, _f()):
		if layer is SpriteFrames and layer.has_animation(_f()):
			draw_texture_rect(layer.get_frame_texture(_f(), 0), Rect2(o, _frame_size() * ZOOM), false)
		elif layer is HeldDef:
			var p: Vector4 = layer.pins[_f()]
			draw_set_transform(o + Vector2(p.x, p.y) * ZOOM, deg_to_rad(p.z), Vector2(ZOOM, ZOOM))
			draw_texture(layer.texture(), -layer.anchor)
			if layer == _held():
				draw_circle(Vector2.ZERO, 1.0, Color(1, 0.2, 0.6, 0.8))  # the pin
			draw_set_transform(Vector2.ZERO)

func _gui_input(ev: InputEvent) -> void:
	var h := _held()
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_turn((0.5 if ev.shift_pressed else 2.0) * (1 if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1))
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed and h != null and h.shows(_f())
		if _drag:
			var p: Vector4 = h.pins[_f()]
			_grab = (ev.position - _origin()) / ZOOM - Vector2(p.x, p.y)
	elif ev is InputEventMouseMotion and _drag:
		var at: Vector2 = (ev.position - _origin()) / ZOOM - _grab
		var p: Vector4 = h.pins[_f()]
		_set_pin(Vector4(snappedf(at.x, 0.1), snappedf(at.y, 0.1), p.z, p.w))

func _unhandled_key_input(ev: InputEvent) -> void:
	if not ev.pressed:
		return
	match ev.keycode:
		KEY_LEFT: _step(-1)
		KEY_RIGHT: _step(1)
		KEY_TAB: _next_piece()
		KEY_PAGEUP: _layer(1)
		KEY_PAGEDOWN: _layer(-1)
		KEY_H: _toggle()
		KEY_C: _copy_prev()
		KEY_SPACE: _play()
		KEY_S:
			if ev.ctrl_pressed or ev.meta_pressed:
				_save()

func _set_pin(p: Vector4) -> void:
	var h := _held()
	h.pins[_f()] = p
	_dirty[h] = true
	_status.text = "Changed (not saved yet)"
	queue_redraw()

func _turn(deg: float) -> void:
	var h := _held()
	if h and h.shows(_f()):
		var p: Vector4 = h.pins[_f()]
		_set_pin(Vector4(p.x, p.y, snappedf(p.z + deg, 0.1), p.w))

func _layer(d: int) -> void:
	var h := _held()
	if h and h.shows(_f()):
		var p: Vector4 = h.pins[_f()]
		_set_pin(Vector4(p.x, p.y, p.z, clampi(int(p.w) + d, 0, LAYER_NAMES.size() - 1)))

func _toggle() -> void:
	var h := _held()
	if h == null:
		return
	if h.shows(_f()):
		h.pins.erase(_f())
		_dirty[h] = true
		queue_redraw()
	else:
		_copy_prev()

## The pin of the nearest earlier frame that shows the piece (or any frame), copied onto this one.
func _copy_prev() -> void:
	var h := _held()
	if h == null or h.pins.is_empty():
		return
	for i in range(_frame - 1, _frame - _frames.size(), -1):
		var f := _frames[posmod(i, _frames.size())]
		if h.shows(f):
			_set_pin(h.pins[f])
			return

func _step(d: int) -> void:
	_playing = false
	_frame = posmod(_frame + d, _frames.size())
	queue_redraw()

func _next_piece() -> void:
	_piece = (_piece + 1) % maxi(_pieces.size(), 1)
	queue_redraw()

func _next_job() -> void:
	_pick_job((_job + 1) % maxi(_jobs.size(), 1))

func _play() -> void:
	_playing = not _playing
	_play_t = 0.0

func _save() -> void:
	var saved := []
	for h: HeldDef in _dirty:
		var err := ResourceSaver.save(h, h.resource_path)
		saved.append("%s %s" % [h.resource_path.get_file(), "saved" if err == OK else "FAILED (%s)" % error_string(err)])
	_dirty.clear()
	_status.text = ", ".join(saved) if saved else "Nothing changed"
