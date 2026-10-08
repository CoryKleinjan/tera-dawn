extends Node
## Autoload "Game": the character's progress, input bindings and save file.

var save_path := "user://save.json"

var level := 1
var xp := 0
var shards := 0
var hp := 0
var mp := 0
var map_id := "meadow"

var ui_font: Font
var num_font: Font

func _ready() -> void:
	ui_font = load("res://assets/fonts/Baloo2-Bold.ttf")
	num_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	_setup_input()
	load_game()
	hp = max_hp()
	mp = max_mp()

func max_hp() -> int:
	return 50 + level * 14

func max_mp() -> int:
	return 20 + level * 6

func attack_power() -> int:
	return 10 + level * 3

func xp_need(lvl := -1) -> int:
	if lvl < 0:
		lvl = level
	return int(floor(15.0 * pow(lvl, 1.6)))

## Adds EXP and returns how many levels were gained.
func gain_xp(n: int) -> int:
	xp += n
	var gained := 0
	while xp >= xp_need():
		xp -= xp_need()
		level += 1
		gained += 1
	if gained > 0:
		hp = max_hp()
		mp = max_mp()
		save_game()
	return gained

func save_game() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"level": level, "xp": xp, "shards": shards, "map_id": map_id}))

func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		level = maxi(1, int(data.get("level", 1)))
		xp = maxi(0, int(data.get("xp", 0)))
		shards = maxi(0, int(data.get("shards", 0)))
		var m := str(data.get("map_id", "meadow"))
		map_id = m if GameData.MAPS.has(m) else "meadow"

func _setup_input() -> void:
	_bind("move_left", [KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_bind("move_right", [KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_bind("move_up", [KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_bind("move_down", [KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_bind("jump", [KEY_SPACE, KEY_C, KEY_ALT], [JOY_BUTTON_A])
	_bind("attack", [KEY_X, KEY_Z, KEY_CTRL], [JOY_BUTTON_X])
	_bind("skill", [KEY_A, KEY_SHIFT], [JOY_BUTTON_Y])
	_bind("pause", [KEY_ESCAPE], [JOY_BUTTON_START])
	_bind("toggle_fullscreen", [KEY_F11], [])

func _bind(action: String, keys: Array, buttons: Array, axis := -1, axis_dir := 0.0) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.4)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)
	if axis >= 0:
		var m := InputEventJoypadMotion.new()
		m.axis = axis
		m.axis_value = axis_dir
		InputMap.action_add_event(action, m)
