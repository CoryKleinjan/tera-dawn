extends Control
## Poses the hero by hand, frame by frame: open scenes/dev/hero_pose_editor.tscn in Godot and play
## it (F6). It draws him the way the game does (HeroBody.layers) in one job's starter gear (pick
## the job, his face and hairstyle, the pose and piece from the dropdowns). Click any piece (his body, face, hair, fists, a piece of clothing, a weapon or off-hand) to pick it,
## drag to move it, the mouse wheel turns it, Shift+wheel or [ ] makes it bigger or smaller, and Save writes it back (held pieces to their pins in
## data/hero/held/, clothes to their item, his face or hairstyle to its file in data/hero/faces/ or
## data/hero/hairs/, his body and fists to data/hero/look.tres), so each save
## replaces the last.
##
##   Left/Right  pose          Tab        next piece       Wheel or Q/E (Shift+Q/E: fine)  turn
##   Shift+wheel or [ ]  smaller/bigger (Shift+[ ]: fine)
##   PgUp/PgDn   up/down stack H          add here / delete here
##   A or Insert  add the piece to this frame (another frame's painting if it has none here)
##   Delete or Backspace  delete the piece from this frame
##   C           copy the previous frame's place           R    reset the piece on this frame
##   Arrow Up/Down  move 0.5 px (with Shift: left/right)   Space  play the walk   Ctrl+S  save

## How big he is drawn, at most (smaller when the window is short).
const MAX_ZOOM := 3.0
## Frames in the order they are stepped through (then the rest, A to Z).
const ORDER := [&"idle1", &"idle2", &"walk1", &"walk2", &"walk3", &"jump", &"hurt", &"crouch", &"sit", &"faint"]
const BG := Color(0.86, 0.83, 0.77)
const LAYER_NAMES := ["behind him", "under his top", "over his clothes", "over his hands"]
## Places he can wear something in the editor, as dropdowns (Equipment.PLACES_FOR).
const PLACES := [&"weapon", &"shield", &"hat", &"top", &"bottom", &"shoes", &"gloves", &"cape"]
## How much one step of Smaller/Bigger changes a piece's size (Shift: a fine step).
const SIZE_STEP := 0.05
const SIZE_FINE := 0.01
const PART_NAMES := {&"body": "his body", &"face": "his face", &"hair": "his hair", &"hair_under": "his hair under the hat", &"hands": "his fists"}

var _jobs: Array[StringName] = []
var _job := 0
var _outfit: Dictionary = {}  # place -> EquipDef
var _pieces: Array[HeroBody.Layer] = []
var _piece := 0
var _frames: Array[StringName] = []
var _frame := 0
var _dirty := {}  # Resource to save -> true
var _saved_pins := {}  # HeldDef -> [its pins, its sizes] as last saved, what Reset puts it back to
var _drag := false
var _grab := Vector2.ZERO
var _playing := false
var _play_t := 0.0
var _images := {}  # Texture2D -> Image, for picking by click
var _rows: VBoxContainer
var _info: Label
var _status: Label
var _job_menu: OptionButton
var _face := 0  # which of HeroBody.LOOK.faces he has
var _hair := 0  # which of HeroBody.LOOK.hairs he has
var _face_menu: OptionButton
var _hair_menu: OptionButton
var _pose_menu: OptionButton
var _piece_menu: OptionButton
var _wear_menus := {}  # place -> OptionButton
var _choices := {}  # place -> [null, EquipDef...] the job can wear there, in its dropdown's order

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
		if e and (e.worn or e.held):
			for j in e.jobs:
				if j not in _jobs:
					_jobs.append(j)
	_jobs.sort()
	_jobs.push_front(&"")  # no job yet: the plain hero, and gear anyone can wear
	_build_ui()
	_pick_job(maxi(_jobs.find(&"warrior"), 0))

func _build_ui() -> void:
	var rows := VBoxContainer.new()
	add_child(rows)
	rows.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	rows.resized.connect(queue_redraw)
	_rows = rows
	var bar := HBoxContainer.new()
	rows.add_child(bar)
	_job_menu = _menu(bar, "Job", _jobs.map(_job_name), _pick_job)
	_face_menu = _menu(bar, "Face", HeroBody.LOOK.faces.map(_style_name), func(i): _face = i; _pieces_changed())
	_hair_menu = _menu(bar, "Hair", HeroBody.LOOK.hairs.map(_style_name), func(i): _hair = i; _pieces_changed())
	_pose_menu = _menu(bar, "Pose", _frames.map(func(f): return String(f)), func(i): _frame = i; _playing = false; _sync())
	_piece_menu = _menu(bar, "Piece", [], func(i): _piece = i; _sync())
	var wear := HFlowContainer.new()
	rows.add_child(wear)
	for place in PLACES:
		_wear_menus[place] = _menu(wear, String(place).capitalize(), [], func(i): _wear(place, i))
	var tools := HFlowContainer.new()
	rows.add_child(tools)
	for b in [["< Pose", func(): _step(-1)], ["Pose >", func(): _step(1)], ["Turn left", func(): _turn(-2.0)], ["Turn right", func(): _turn(2.0)], ["Smaller", func(): _resize(-SIZE_STEP)],
			["Bigger", func(): _resize(SIZE_STEP)], ["Down the stack", func(): _restack(-1)],
			["Up the stack", func(): _restack(1)], ["Add here", _add_here], ["Delete here", _delete_here], ["Copy previous", _copy_prev],
			["Reset piece", _reset], ["Reset pose", _reset_pose], ["Play walk", _play], ["Save", _save]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		tools.add_child(btn)
	_info = Label.new()
	rows.add_child(_info)
	_status = Label.new()
	rows.add_child(_status)

## A labelled dropdown of `items` on `bar`, calling `picked` with the index chosen.
func _menu(bar: Container, label: String, items: Array, picked: Callable) -> OptionButton:
	var pair := HBoxContainer.new()  # label and dropdown wrap onto a new row together
	bar.add_child(pair)
	var l := Label.new()
	l.text = label
	pair.add_child(l)
	var m := OptionButton.new()
	m.focus_mode = Control.FOCUS_NONE
	for t in items:
		m.add_item(t)
	m.item_selected.connect(picked)
	pair.add_child(m)
	return m

## Shows the job, face, hair, pose and piece picked in the dropdowns and redraws.
func _sync() -> void:
	_job_menu.select(_job)
	_face_menu.select(_face)
	_hair_menu.select(_hair)
	_pose_menu.select(_frame)
	_piece_menu.select(_piece)
	queue_redraw()

## Shows `i` of the job list in his starter gear: in each place, the first thing (lowest level)
## the job can wear there that has a look.
func _job_name(job: StringName) -> String:
	return String(job).capitalize() if job else "No job"

func _style_name(style: HeroStyleDef) -> String:
	return style.display_name if style.display_name else String(style.id)

## His face and hairstyle as picked.
func _face_style() -> HeroStyleDef:
	return HeroBody.LOOK.faces[_face]

func _hair_style() -> HeroStyleDef:
	return HeroBody.LOOK.hairs[_hair]

## His layers on this frame, the way the game stacks them.
func _stack() -> Array[HeroBody.Layer]:
	return HeroBody.layers(_outfit, _f(), _face_style(), _hair_style())

func _pick_job(i: int) -> void:
	_job = i
	var job := _jobs[i] if i < _jobs.size() else &""
	var gear := Content.items.values().filter(func(e): return e is EquipDef and (e.worn or e.held) and (job in e.jobs or e.jobs.is_empty()))
	gear.sort_custom(func(a, b): return [a.required_level, a.id] < [b.required_level, b.id])
	_outfit.clear()
	for place in PLACES:
		_choices[place] = [null] + gear.filter(func(e): return place in Equipment.PLACES_FOR[e.slot])
		var m: OptionButton = _wear_menus[place]
		m.clear()
		m.add_item("Nothing")
		for e in _choices[place].slice(1):
			m.add_item(e.display_name)
		if _choices[place].size() > 1:
			_outfit[place] = _choices[place][1]
		m.select(mini(1, _choices[place].size() - 1))
	_pieces_changed()

## Wears choice `i` of `place`'s dropdown (0: nothing).
func _wear(place: StringName, i: int) -> void:
	if _choices[place][i]:
		_outfit[place] = _choices[place][i]
	else:
		_outfit.erase(place)
	_pieces_changed()

## The pieces to pick from: what he wears (the weapon first), then his own parts.
func _pieces_changed() -> void:
	var picked := _sel()
	_pieces.clear()
	for place in PLACES:
		if _outfit.has(place):
			_pieces.append(HeroBody.Layer.new(_outfit[place]))
			var h: HeldDef = _outfit[place].held
			if h and not _saved_pins.has(h):
				_saved_pins[h] = [h.pins.duplicate(), h.sizes.duplicate()]
	var hat: EquipDef = _outfit.get(&"hat")
	var under: HeroStyleDef = _hair_style().under_hats.get(hat.id) if hat else null
	for part in PART_NAMES:
		var owner: Resource = {&"face": _face_style(), &"hair": _hair_style(), &"hair_under": under}.get(part, HeroBody.LOOK)
		if owner:
			_pieces.append(HeroBody.Layer.new(owner, part))
	_piece = 0
	_piece_menu.clear()
	for i in _pieces.size():
		_piece_menu.add_item(_name(_pieces[i]))
		if _same(_pieces[i], picked):
			_piece = i
	_sync()

func _sel() -> HeroBody.Layer:
	return _pieces[_piece] if _piece < _pieces.size() else null

func _same(a: HeroBody.Layer, b: HeroBody.Layer) -> bool:
	return a != null and b != null and a.owner == b.owner and a.part == b.part

func _name(l: HeroBody.Layer) -> String:
	return PART_NAMES[l.part] if l.part else (l.owner as EquipDef).display_name

func _f() -> StringName:
	return _frames[_frame]

## Where his frame's top left corner is drawn: centred under the buttons.
func _origin() -> Vector2:
	return Vector2(size.x / 2.0 - _frame_size().x * _zoom() / 2.0, _rows.get_rect().end.y + 12.0)

func _zoom() -> float:
	return clampf((size.y - _rows.get_rect().end.y - 24.0) / _frame_size().y, 1.0, MAX_ZOOM)

func _frame_size() -> Vector2:
	return HeroBody.LOOK.body.get_frame_texture(_f(), 0).get_size()

func _process(delta: float) -> void:
	if _playing:
		_play_t += delta
		var walk: Array = HeroBody.LOOK.animations[&"walk"]["frames"]
		var i := int(_play_t * float(HeroBody.LOOK.animations[&"walk"]["fps"])) % walk.size()
		_frame = _frames.find(walk[i])
		_sync()
	var l := _sel()
	var text := "no piece"
	if l and l.shows(_f()):
		var p := l.pin(_f())
		var stack: String = LAYER_NAMES[int(l.held().layer(_f()))] if l.held() else "%+d places in the stack" % l.steps(_f())
		var moved: Vector2 = Vector2(p.x, p.y) - l.anchor(_f()) if not l.held() else Vector2(p.x, p.y)
		text = "%s: %s %.1f, %.1f  turned %.1f°  size %d%%  %s" % [_name(l), "moved" if not l.held() else "at", moved.x, moved.y, p.z, roundi(l.size(_f()) * 100), stack]
	elif l:
		text = "%s: not on this frame%s" % [_name(l), " (H shows it)" if l.held() else ""]
	_info.text = "%s   pose %s (%d/%d)   %s" % [_job_name(_jobs[_job]), _f(), _frame + 1, _frames.size(), text]

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var o := _origin()
	draw_rect(Rect2(o, _frame_size() * _zoom()), Color(0, 0, 0, 0.06), false)
	for l in _stack():
		var p := l.pin(_f())
		var a := l.anchor(_f())
		var k := l.size(_f())
		draw_set_transform(o + Vector2(p.x, p.y) * _zoom(), deg_to_rad(p.z), Vector2.ONE * _zoom() * k)
		draw_texture(l.texture(_f()), -a)
		if _same(l, _sel()):
			draw_circle(Vector2.ZERO, 1.0 / k, Color(1, 0.2, 0.6, 0.8))  # what it turns around
		draw_set_transform(Vector2.ZERO)

## The topmost piece with paint under `at` (screen position), or null.
func _piece_at(at: Vector2) -> HeroBody.Layer:
	var stack := _stack()
	stack.reverse()
	for l in stack:
		var p := l.pin(_f())
		var tex := l.texture(_f())
		var px := ((at - _origin()) / _zoom() - Vector2(p.x, p.y)).rotated(-deg_to_rad(p.z)) / l.size(_f()) + l.anchor(_f())
		if not _images.has(tex):
			_images[tex] = tex.get_image()
		var img: Image = _images[tex]
		if Rect2(Vector2.ZERO, img.get_size()).has_point(px) and img.get_pixelv(Vector2i(px)).a > 0.3:
			return l
	return null

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var up: int = 1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		if ev.shift_pressed:
			_resize(SIZE_STEP * up)
		else:
			_turn(-2.0 * up)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = false
		if ev.pressed:
			var hit := _piece_at(ev.position)
			if hit:
				for i in _pieces.size():
					if _same(_pieces[i], hit):
						_piece = i
				var p := hit.pin(_f())
				_grab = (ev.position - _origin()) / _zoom() - Vector2(p.x, p.y)
				_drag = true
				_sync()
	elif ev is InputEventMouseMotion and _drag:
		var at: Vector2 = (ev.position - _origin()) / _zoom() - _grab
		var p := _sel().pin(_f())
		_move_to(Vector2(snappedf(at.x, 0.1), snappedf(at.y, 0.1)), p.z)

func _unhandled_key_input(ev: InputEvent) -> void:
	if not ev.pressed:
		return
	match ev.keycode:
		KEY_LEFT: _step(-1)
		KEY_RIGHT: _step(1)
		KEY_UP: _nudge(Vector2(-0.5, 0) if ev.shift_pressed else Vector2(0, -0.5))
		KEY_DOWN: _nudge(Vector2(0.5, 0) if ev.shift_pressed else Vector2(0, 0.5))
		KEY_TAB: _next_piece()
		KEY_PAGEUP: _restack(1)
		KEY_PAGEDOWN: _restack(-1)
		KEY_H: _toggle()
		KEY_A, KEY_INSERT: _add_here()
		KEY_DELETE, KEY_BACKSPACE: _delete_here()
		KEY_C: _copy_prev()
		KEY_R: _reset()
		KEY_Q: _turn(-0.5 if ev.shift_pressed else -2.0)
		KEY_E: _turn(0.5 if ev.shift_pressed else 2.0)
		KEY_BRACKETLEFT: _resize(-(SIZE_FINE if ev.shift_pressed else SIZE_STEP))
		KEY_BRACKETRIGHT: _resize(SIZE_FINE if ev.shift_pressed else SIZE_STEP)
		KEY_SPACE: _play()
		KEY_S:
			if ev.ctrl_pressed or ev.meta_pressed:
				_save()

## Puts the picked piece's anchor at `at` (frame pixels), turned `deg`, keeping its stack place.
func _move_to(at: Vector2, deg: float) -> void:
	var l := _sel()
	if l == null or not l.shows(_f()):
		return
	var h := l.held()
	if h:
		h.pins[_f()] = Vector4(at.x, at.y, deg, (h.pins[_f()] as Vector4).w)
		_changed(h)
	else:
		var off := at - l.anchor(_f())
		l.set_nudge(_f(), Vector4(off.x, off.y, deg, l.steps(_f())))
		_changed(l.owner)

func _changed(res: Resource) -> void:
	_dirty[res] = true
	_status.text = "Changed (not saved yet)"
	queue_redraw()

func _nudge(d: Vector2) -> void:
	var l := _sel()
	if l and l.shows(_f()):
		var p := l.pin(_f())
		_move_to(Vector2(p.x, p.y) + d, p.z)

func _turn(deg: float) -> void:
	var l := _sel()
	if l and l.shows(_f()):
		var p := l.pin(_f())
		_move_to(Vector2(p.x, p.y), snappedf(p.z + deg, 0.1))

## Makes the picked piece `d` bigger (negative: smaller) on this frame, as a share of its
## painted size. Bigger than painted looks softer, so the editor says so.
func _resize(d: float) -> void:
	var l := _sel()
	if l == null or not l.shows(_f()):
		return
	var k := clampf(snappedf(l.size(_f()) + d, 0.01), 0.1, 3.0)
	l.set_size(_f(), k)
	_changed(l.held() if l.held() else l.owner)
	if k > 1.0:
		_status.text = "Changed (not saved yet). Bigger than painted, so it will look a little softer"

## Moves the picked piece `d` places up (or down) the stack on this frame: a held piece to the
## next of its layers, anything else past the piece above (or below) it.
func _restack(d: int) -> void:
	var l := _sel()
	if l == null or not l.shows(_f()):
		return
	var h := l.held()
	if h:
		var p: Vector4 = h.pins[_f()]
		h.pins[_f()] = Vector4(p.x, p.y, p.z, clampi(int(p.w) + d, 0, LAYER_NAMES.size() - 1))
		_changed(h)
	else:
		var n: Vector4 = l.nudges().get(_f(), Vector4.ZERO)
		l.set_nudge(_f(), Vector4(n.x, n.y, n.z, n.w + d))
		_changed(l.owner)

## Deletes the picked piece from this frame if it shows here, else adds it.
func _toggle() -> void:
	var l := _sel()
	if l and l.shows(_f()) and _drawn(l):
		_delete_here()
	else:
		_add_here()

## Whether the picked piece is drawn on this frame (the stack can leave a piece off: the
## off-hand with the weapon put away, hair under a hat, fists with no weapon out).
func _drawn(l: HeroBody.Layer) -> bool:
	return _stack().any(func(o): return _same(o, l))

## Takes the picked piece off this frame entirely.
func _delete_here() -> void:
	var l := _sel()
	if l == null:
		return
	var h := l.held()
	if h:
		h.pins.erase(_f())
		h.sizes.erase(_f())
		_changed(h)
	else:
		l.set_frame_art(_f(), &"")
		l.set_nudge(_f(), Vector4.ZERO)
		l.set_size(_f(), 1.0)
		_changed(l.owner)

## Puts the picked piece on this frame: its own painting for this frame if it has one, else the
## painting (and place) of the nearest earlier frame that shows it, to move into place.
func _add_here() -> void:
	var l := _sel()
	if l == null:
		return
	var h := l.held()
	if h:
		if not h.shows(_f()):
			_copy_prev()
			if not h.shows(_f()):
				h.pins[_f()] = Vector4(_frame_size().x / 2.0, _frame_size().y / 2.0, 0, HeldDef.Layer.OVER_CLOTHES)
				_changed(h)
		if not _drawn(l):
			_status.text = "Added, but the off-hand only shows when the weapon does: add the weapon here too"
		return
	var f := l.frames()
	if f == null:
		return
	if f.has_animation(_f()):
		l.set_frame_art(_f(), _f())
	else:
		for i in range(_frame - 1, _frame - _frames.size(), -1):
			var g := _frames[posmod(i, _frames.size())]
			if l.shows(g):
				l.set_frame_art(_f(), l.art(g))
				l.set_nudge(_f(), l.nudges().get(g, Vector4.ZERO))
				l.set_size(_f(), l.size(g))
				break
	_changed(l.owner)

## Puts the picked piece back on this frame: where it is painted, or a held piece where it was
## last saved.
func _reset() -> void:
	if _sel():
		_reset_piece(_sel())

## Puts every piece he has on back on this frame (see _reset).
func _reset_pose() -> void:
	for l in _pieces:
		_reset_piece(l)

func _reset_piece(l: HeroBody.Layer) -> void:
	var h := l.held()
	if h:
		var saved: Array = _saved_pins.get_or_add(h, [h.pins.duplicate(), h.sizes.duplicate()])
		if saved[0].has(_f()):
			h.pins[_f()] = saved[0][_f()]
		else:
			h.pins.erase(_f())
		l.set_size(_f(), saved[1].get(_f(), 1.0))
		_changed(h)
	elif l.nudges().has(_f()) or l.sizes().has(_f()):
		l.set_nudge(_f(), Vector4.ZERO)
		l.set_size(_f(), 1.0)
		_changed(l.owner)

## The place of the nearest earlier frame that has one, copied onto this frame.
func _copy_prev() -> void:
	var l := _sel()
	if l == null:
		return
	var h := l.held()
	var places: Dictionary = h.pins if h else l.nudges()
	if places.is_empty():
		return
	for i in range(_frame - 1, _frame - _frames.size(), -1):
		var f := _frames[posmod(i, _frames.size())]
		if places.has(f):
			if h:
				h.pins[_f()] = h.pins[f]
				l.set_size(_f(), l.size(f))
				_changed(h)
			elif l.shows(_f()):
				l.set_nudge(_f(), places[f])
				l.set_size(_f(), l.size(f))
				_changed(l.owner)
			return

func _step(d: int) -> void:
	_playing = false
	_frame = posmod(_frame + d, _frames.size())
	_sync()

func _next_piece() -> void:
	_piece = (_piece + 1) % maxi(_pieces.size(), 1)
	_sync()

func _play() -> void:
	_playing = not _playing
	_play_t = 0.0

func _save() -> void:
	var saved := []
	for res: Resource in _dirty:
		var err := ResourceSaver.save(res, res.resource_path)
		if res is HeldDef and err == OK:
			_saved_pins[res] = [(res as HeldDef).pins.duplicate(), (res as HeldDef).sizes.duplicate()]
		saved.append("%s %s" % [res.resource_path.get_file(), "saved" if err == OK else "FAILED (%s)" % error_string(err)])
	_dirty.clear()
	_status.text = ", ".join(saved) if saved else "Nothing changed"
