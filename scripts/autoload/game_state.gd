extends Node
## Autoload "Game": this player's side of the game. It keeps a copy of the player's own
## Character (`me`) that the server refreshes, the input bindings (including the eight
## quickslot keys), fonts and the player's settings (name, last server address).
## The real Character lives on the server (see TDServer); to change it, ask through Net.

## The input action of each quickslot (Character.quickslots), in order.
const QUICKSLOT_ACTIONS: Array[String] = ["quick_1", "quick_2", "quick_3", "quick_4", "quick_5", "quick_6", "quick_7", "quick_8"]
const SETTINGS_PATH := "user://settings.cfg"

## The server sent a new copy of the whole character (inventory, gear, stats).
signal character_changed

## The player's character as the server last described it. Read it; don't change it.
var me: Character
## Buddies, party and guild as the server last described them (TDSocial.summary).
var social := {}
## The name typed on the title screen and the last server joined.
var player_name := "Dawnling"
var last_address := "127.0.0.1"

var ui_font: Font
var num_font: Font

func _ready() -> void:
	ui_font = load("res://assets/fonts/Baloo2-Bold.ttf")
	num_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	_setup_input()
	_load_settings()
	me = Character.create(player_name)

func apply_character(data: Dictionary) -> void:
	if me == null or me.name != str(data.get("name", "")):
		me = Character.create(str(data.get("name", player_name)))
	me.load_dict(data)
	character_changed.emit()

func apply_vitals(hp: int, mp: int, xp: int, level: int, shards: int) -> void:
	if level != me.level:
		me.level = level
		me.recalc()
	me.health.set_hp(hp)
	me.mp = mp
	me.xp = xp
	me.shards = shards

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "address", last_address)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		player_name = str(cfg.get_value("player", "name", player_name))
		last_address = str(cfg.get_value("player", "address", last_address))

func _setup_input() -> void:
	_bind("move_left", [KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_bind("move_right", [KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_bind("move_up", [KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_bind("move_down", [KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_bind("jump", [KEY_SPACE, KEY_C, KEY_ALT], [JOY_BUTTON_A])
	_bind("attack", [KEY_X, KEY_CTRL], [JOY_BUTTON_X])
	_bind("quick_1", [KEY_A, KEY_SHIFT], [JOY_BUTTON_Y])
	_bind("quick_2", [KEY_D], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("quick_3", [KEY_F], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("quick_4", [KEY_G], [])
	_bind("quick_5", [KEY_V], [])
	_bind("quick_6", [KEY_B], [])
	_bind("quick_7", [KEY_N, KEY_DELETE], [])
	_bind("quick_8", [KEY_M, KEY_END], [])
	_bind("loot", [KEY_Z], [JOY_BUTTON_B])
	_bind("inventory", [KEY_I], [JOY_BUTTON_BACK])
	_bind("equipment", [KEY_E], [])
	_bind("stats", [KEY_S], [])
	_bind("quests", [KEY_Q], [])
	_bind("skills", [KEY_K], [])
	_bind("worldmap", [KEY_W], [])
	_bind("community", [KEY_O], [])
	_bind("chat", [KEY_ENTER, KEY_KP_ENTER], [])
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
