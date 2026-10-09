extends Node
## Autoload "Game": the character (level, EXP, job, stats, Ability Points, inventory,
## equipment, Dawnshards, HP, MP), which skills are on which buttons, input bindings, fonts
## and the save file. Formulas live in CharacterStats; this only holds and changes state.

## Which skill each attack button uses (ids from data/skills/).
const SKILL_BINDINGS := {"attack": &"basic_attack", "skill": &"dawn_slash"}
const START_MAP := &"meadow"
const START_JOB := &"warrior"

## Base stats, gear or Ability Points changed: anything showing stats should refresh.
signal stats_changed

var save_path := "user://save.json"

var level := 1
var xp := 0
var shards := 0
var mp := 0
var map_id: StringName = START_MAP
var health := Health.new()
var job: JobDef
## Stats from the job and Ability Points, before gear.
var base := StatBlock.new()
## Unspent Ability Points.
var ap := 0
var inventory := Inventory.new()
var equipment := Equipment.new()
## Base stats plus everything worn. Kept up to date by recalc().
var stats := StatBlock.new()

var ui_font: Font
var num_font: Font

func _ready() -> void:
	ui_font = load("res://assets/fonts/Baloo2-Bold.ttf")
	num_font = load("res://assets/fonts/LilitaOne-Regular.ttf")
	_setup_input()
	equipment.changed.connect(recalc)
	new_character()
	load_game()
	refill()

## A fresh level 1 character with the job's starting stats, gear and items.
func new_character() -> void:
	job = Content.job(START_JOB)
	level = 1
	xp = 0
	shards = 0
	ap = 0
	map_id = START_MAP
	base = job.starting_stats.copy() if job.starting_stats else StatBlock.new()
	inventory.clear()
	equipment.clear()
	for e in job.starting_gear:
		equipment.put(equipment.place_for(e), ItemStack.exact(e))
	for entry in job.starting_items:
		var n := entry.roll()
		if n > 0:
			inventory.add(entry.item, n)
	recalc()
	refill()

## Works out the total stats again after base stats or gear change.
func recalc() -> void:
	if job == null:
		return
	stats = base.plus(equipment.bonus())
	health.set_max(max_hp())
	mp = mini(mp, max_mp())
	stats_changed.emit()

## Full HP and MP.
func refill() -> void:
	health.reset(max_hp())
	mp = max_mp()

func max_hp() -> int:
	return CharacterStats.max_hp(job, level, stats)

func max_mp() -> int:
	return CharacterStats.max_mp(job, level, stats)

func damage_range() -> Vector2i:
	return CharacterStats.damage_range(job, stats)

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
		ap += gained * job.ap_per_level
		recalc()
		refill()
		save_game()
	return gained

func spend_mp(n: int) -> bool:
	if mp < n:
		return false
	mp -= n
	return true

## Spends one Ability Point on STR, DEX, INT or LUK.
func add_ap(stat: StringName) -> bool:
	if ap <= 0 or not stat in StatBlock.BASE:
		return false
	ap -= 1
	base.set(stat, base.value(stat) + 1)
	recalc()
	return true

## Why the character can't wear this, or "" if they can.
func equip_problem(e: EquipDef) -> String:
	if level < e.required_level:
		return "You need to be level %d to wear the %s." % [e.required_level, e.display_name]
	var reqs := e.requirements()
	for stat in StatBlock.BASE:
		if reqs.has(stat) and stats.value(stat) < reqs[stat]:
			return "You need %d %s to wear the %s." % [reqs[stat], StatBlock.LABELS[stat], e.display_name]
	return ""

## Wears the gear in Equip slot `i`, putting whatever it replaces back in that slot.
## Returns why it couldn't, or "".
func equip(i: int, place: StringName = &"") -> String:
	var stack := inventory.at(ItemDef.Tab.EQUIP, i)
	if stack == null:
		return ""
	var e := stack.equip_def()
	var problem := equip_problem(e)
	if problem != "":
		return problem
	if place == &"" or not Equipment.fits(e, place):
		place = equipment.place_for(e)
	inventory.take(ItemDef.Tab.EQUIP, i)
	var old := equipment.put(place, stack)
	if old:
		inventory.put(ItemDef.Tab.EQUIP, i, old)
	return ""

## Takes off what's worn in `place` and puts it in the bag (at slot `i` if given and free).
func unequip(place: StringName, i := -1) -> String:
	var stack := equipment.at(place)
	if stack == null:
		return ""
	var row: Array = inventory.tabs[ItemDef.Tab.EQUIP]
	if i < 0 or row[i] != null:
		i = inventory.first_free(ItemDef.Tab.EQUIP)
	if i < 0:
		return "Your Equip inventory is full."
	equipment.take(place)
	inventory.put(ItemDef.Tab.EQUIP, i, stack)
	return ""

func save_game() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"level": level, "xp": xp, "shards": shards, "map_id": map_id,
		"job": job.id, "base": base.to_dict(), "ap": ap,
		"inventory": inventory.to_dict(), "equipment": equipment.to_dict(),
	}))

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
		var m := StringName(str(data.get("map_id", START_MAP)))
		map_id = m if Content.maps.has(m) else START_MAP
		var j := StringName(str(data.get("job", START_JOB)))
		if Content.jobs.has(j):
			job = Content.jobs[j]
		if data.get("base") is Dictionary:
			base = StatBlock.from_dict(data["base"])
			ap = maxi(0, int(data.get("ap", 0)))
		else:
			# a save from before stats existed: hand out the points for the levels it has
			ap = (level - 1) * job.ap_per_level
		if data.get("inventory") is Dictionary:
			inventory.load_dict(data["inventory"])
		if data.get("equipment") is Dictionary:
			equipment.load_dict(data["equipment"])
		recalc()

func _setup_input() -> void:
	_bind("move_left", [KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_bind("move_right", [KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_bind("move_up", [KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_bind("move_down", [KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_bind("jump", [KEY_SPACE, KEY_C, KEY_ALT], [JOY_BUTTON_A])
	_bind("attack", [KEY_X, KEY_CTRL], [JOY_BUTTON_X])
	_bind("skill", [KEY_A, KEY_SHIFT], [JOY_BUTTON_Y])
	_bind("loot", [KEY_Z], [JOY_BUTTON_B])
	_bind("inventory", [KEY_I], [JOY_BUTTON_BACK])
	_bind("equipment", [KEY_E], [])
	_bind("stats", [KEY_S], [])
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
