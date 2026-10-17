class_name Keybinds
extends SettingsSection
## The player's keyboard controls. ACTIONS lists every input action: its name and group on
## the Controls tab, its default keys and its gamepad buttons (gamepad buttons can't be
## changed yet). Every action has SLOTS keys, and 0 is an empty slot. To add an action,
## add a line to ACTIONS; `apply` creates it in the InputMap.
##
## The pad has two pages: "pad"/"axis" work normally, "pad2"/"axis2" while the left trigger
## is held (PAGE_AXIS, see TDPad), which is how quickslots 4-8 fit on a pad. A button used on
## page 2 does only its page 2 action while the trigger is held.

const SLOTS := 2
## Groups in the order the Controls tab shows them.
const GROUPS: Array[String] = ["Movement", "Combat", "Quickslots", "Windows", "Other"]
## Actions the player can't change, so the menu can always be opened.
const FIXED: Array[String] = ["pause"]
## Holding this trigger turns the pad to its second page.
const PAGE_AXIS := JOY_AXIS_TRIGGER_LEFT
## What the pad's buttons and axes are called on screen (Xbox names, as on the Steam Deck).
const PAD_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_DPAD_UP: "Up", JOY_BUTTON_DPAD_DOWN: "Down", JOY_BUTTON_DPAD_LEFT: "Left", JOY_BUTTON_DPAD_RIGHT: "Right"}
const PAD_AXIS_NAMES := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}

const ACTIONS := [
	{"action": "move_left", "label": "Move left", "group": "Movement", "keys": [KEY_LEFT], "pad": [JOY_BUTTON_DPAD_LEFT], "axis": [JOY_AXIS_LEFT_X, -1.0]},
	{"action": "move_right", "label": "Move right", "group": "Movement", "keys": [KEY_RIGHT], "pad": [JOY_BUTTON_DPAD_RIGHT], "axis": [JOY_AXIS_LEFT_X, 1.0]},
	{"action": "move_up", "label": "Up, talk, portals", "group": "Movement", "keys": [KEY_UP], "pad": [JOY_BUTTON_DPAD_UP], "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	{"action": "move_down", "label": "Down, crouch", "group": "Movement", "keys": [KEY_DOWN], "pad": [JOY_BUTTON_DPAD_DOWN], "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	{"action": "jump", "label": "Jump", "group": "Movement", "keys": [KEY_SPACE, KEY_ALT], "pad": [JOY_BUTTON_A]},
	{"action": "dash", "label": "Dash", "group": "Movement", "keys": [KEY_R], "axis": [JOY_AXIS_TRIGGER_RIGHT, 1.0]},
	{"action": "sit", "label": "Sit", "group": "Movement", "keys": [KEY_C]},
	{"action": "attack", "label": "Attack", "group": "Combat", "keys": [KEY_X, KEY_CTRL], "pad": [JOY_BUTTON_X]},
	{"action": "loot", "label": "Pick up", "group": "Combat", "keys": [KEY_Z], "pad": [JOY_BUTTON_B]},
	{"action": "quick_1", "label": "Quickslot 1", "group": "Quickslots", "keys": [KEY_A, KEY_SHIFT], "pad": [JOY_BUTTON_Y]},
	{"action": "quick_2", "label": "Quickslot 2", "group": "Quickslots", "keys": [KEY_D], "pad": [JOY_BUTTON_RIGHT_SHOULDER]},
	{"action": "quick_3", "label": "Quickslot 3", "group": "Quickslots", "keys": [KEY_F], "pad": [JOY_BUTTON_LEFT_SHOULDER]},
	{"action": "quick_4", "label": "Quickslot 4", "group": "Quickslots", "keys": [KEY_G], "pad2": [JOY_BUTTON_Y]},
	{"action": "quick_5", "label": "Quickslot 5", "group": "Quickslots", "keys": [KEY_V], "pad2": [JOY_BUTTON_RIGHT_SHOULDER]},
	{"action": "quick_6", "label": "Quickslot 6", "group": "Quickslots", "keys": [KEY_B], "pad2": [JOY_BUTTON_LEFT_SHOULDER]},
	{"action": "quick_7", "label": "Quickslot 7", "group": "Quickslots", "keys": [KEY_N, KEY_DELETE], "axis2": [JOY_AXIS_TRIGGER_RIGHT, 1.0]},
	{"action": "quick_8", "label": "Quickslot 8", "group": "Quickslots", "keys": [KEY_M, KEY_END], "pad2": [JOY_BUTTON_B]},
	{"action": "inventory", "label": "Inventory", "group": "Windows", "keys": [KEY_I]},
	{"action": "equipment", "label": "Equipment", "group": "Windows", "keys": [KEY_E]},
	{"action": "stats", "label": "Character", "group": "Windows", "keys": [KEY_S]},
	{"action": "skills", "label": "Skills", "group": "Windows", "keys": [KEY_K]},
	{"action": "quests", "label": "Quests", "group": "Windows", "keys": [KEY_Q]},
	{"action": "worldmap", "label": "World map", "group": "Windows", "keys": [KEY_W]},
	{"action": "community", "label": "Community", "group": "Windows", "keys": [KEY_O]},
	{"action": "collection", "label": "Collection", "group": "Windows", "keys": [KEY_L]},
	{"action": "chat", "label": "Chat", "group": "Other", "keys": [KEY_ENTER, KEY_KP_ENTER]},
	{"action": "toggle_fullscreen", "label": "Fullscreen", "group": "Other", "keys": [KEY_F11]},
	{"action": "pause", "label": "Menu", "group": "Other", "keys": [KEY_ESCAPE], "pad": [JOY_BUTTON_START]},
]

## action -> Array of SLOTS physical keycodes (0 = empty).
var keys := {}

func section() -> String:
	return "keys"

## The ACTIONS entry for `action` ({} if there isn't one).
static func info(action: String) -> Dictionary:
	for a in ACTIONS:
		if a["action"] == action:
			return a
	return {}

## The actions of one group, in order.
static func in_group(group: String) -> Array[String]:
	var out: Array[String] = []
	for a in ACTIONS:
		if a["group"] == group:
			out.append(a["action"])
	return out

## What a key is called on screen ("" for an empty slot).
static func key_text(keycode: int) -> String:
	return OS.get_keycode_string(keycode) if keycode != 0 else ""

static func default_keys(action: String) -> Array[int]:
	var out: Array[int] = []
	for k in info(action).get("keys", []):
		out.append(k)
	while out.size() < SLOTS:
		out.append(0)
	return out

func reset() -> void:
	keys.clear()
	for a in ACTIONS:
		keys[a["action"]] = default_keys(a["action"])

func load_from(cfg: ConfigFile) -> void:
	for a in ACTIONS:
		var action: String = a["action"]
		# fixed actions are never saved, and asking for a missing key with a null default
		# makes Godot print an error
		if action in FIXED or not cfg.has_section_key(section(), action):
			continue
		var saved: Variant = cfg.get_value(section(), action)
		if not saved is Array or saved.size() != SLOTS:
			continue
		var codes: Array[int] = []
		for k in saved:
			codes.append(maxi(0, int(k)) if k is int or k is float else 0)
		keys[action] = codes

func save_to(cfg: ConfigFile) -> void:
	for action in keys:
		if not action in FIXED:
			cfg.set_value(section(), action, keys[action])

func key(action: String, slot: int) -> int:
	return keys[action][slot]

## True if `keycode` belongs to a fixed action (Esc), so it can't be given to another one.
func reserved(keycode: int) -> bool:
	for action in FIXED:
		if keycode in keys[action]:
			return true
	return false

## Puts `keycode` in `action`'s `slot`. If another slot had it, that slot gets the key
## `slot` had before (the two swap). Returns the other action, or "" if no other action
## lost the key.
func set_key(action: String, slot: int, keycode: int) -> String:
	if action in FIXED or reserved(keycode):
		return ""
	var old: int = keys[action][slot]
	var other := ""
	for a in keys:
		for s in SLOTS:
			if keys[a][s] == keycode and not (a == action and s == slot):
				keys[a][s] = old
				if a != action:
					other = a
	keys[action][slot] = keycode
	return other

func clear_key(action: String, slot: int) -> void:
	if not action in FIXED:
		keys[action][slot] = 0

## Writes every action's keys (and, the first time, its gamepad buttons) to the InputMap, and
## lets the pad's A press menu buttons.
func apply() -> void:
	# A presses the focused button in menus, as Enter does
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	if not InputMap.action_has_event("ui_accept", accept):
		InputMap.action_add_event("ui_accept", accept)
	for a in ACTIONS:
		var action: String = a["action"]
		if not InputMap.has_action(action):
			_add_action(a)
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				InputMap.action_erase_event(action, e)
		for k in keys[action]:
			if k != 0:
				var e := InputEventKey.new()
				e.physical_keycode = k
				InputMap.action_add_event(action, e)

static func _add_action(a: Dictionary) -> void:
	InputMap.add_action(a["action"], 0.4)
	_add_pad(a, pad_page)

## The pad page in use: 0 normally, 1 while PAGE_AXIS is held.
static var pad_page := 0

## Turns the pad to `page` (0 or 1): every action gets that page's buttons. Actions that lose
## a button are let go, so nothing stays held across the switch.
static func use_pad_page(page: int) -> void:
	if page == pad_page:
		return
	pad_page = page
	for a in ACTIONS:
		var action: String = a["action"]
		if not InputMap.has_action(action):
			continue
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
		Input.action_release(action)
		_add_pad(a, page)

## What a button or axis on page `page` does there: page 2 buttons override page 1's.
static func _pad_buttons(a: Dictionary, page: int) -> Array:
	if page == 0:
		return a.get("pad", [])
	var taken := _page2_buttons()
	return a.get("pad2", []) + a.get("pad", []).filter(func(b: int) -> bool: return not b in taken)

static func _pad_axis(a: Dictionary, page: int) -> Array:
	var axis: Array = a.get("axis2", []) if page == 1 else []
	if axis.is_empty():
		axis = a.get("axis", [])
		if page == 1 and axis.size() == 2 and axis[0] in _page2_axes():
			return []
	return axis

static func _page2_buttons() -> Array:
	var out := []
	for a in ACTIONS:
		out.append_array(a.get("pad2", []))
	return out

static func _page2_axes() -> Array:
	var out := []
	for a in ACTIONS:
		var axis: Array = a.get("axis2", [])
		if axis.size() == 2:
			out.append(axis[0])
	return out

static func _add_pad(a: Dictionary, page: int) -> void:
	var action: String = a["action"]
	for b in _pad_buttons(a, page):
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)
	var axis := _pad_axis(a, page)
	if axis.size() == 2:
		var m := InputEventJoypadMotion.new()
		m.axis = axis[0]
		m.axis_value = axis[1]
		InputMap.action_add_event(action, m)

## What `action`'s pad button is called on screen ("Y", "LT+Y"), "" if it has none.
static func pad_text(action: String) -> String:
	var a := info(action)
	for page in 2:
		var prefix: String = "" if page == 0 else PAD_AXIS_NAMES[PAGE_AXIS] + "+"
		var buttons: Array = a.get("pad" if page == 0 else "pad2", [])
		if not buttons.is_empty():
			return prefix + PAD_NAMES.get(buttons[0], "?")
		var axis: Array = a.get("axis" if page == 0 else "axis2", [])
		if axis.size() == 2 and PAD_AXIS_NAMES.has(axis[0]):
			return prefix + PAD_AXIS_NAMES[axis[0]]
	return ""

## Which pad page `action` is on (0 or 1), or -1 if it has no pad button.
static func pad_page_of(action: String) -> int:
	var a := info(action)
	if a.has("pad") or a.has("axis"):
		return 0
	if a.has("pad2") or a.has("axis2"):
		return 1
	return -1
