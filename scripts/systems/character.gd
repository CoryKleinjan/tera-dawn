class_name Character
extends RefCounted
## One character: name, level, EXP, job, stats, Ability Points, inventory, equipment,
## quests, Dawnshards, HP, MP and the map they're on. Formulas live in CharacterStats; this only
## holds and changes state.
##
## The server owns the real Character of every player. Each client keeps a copy of its own
## (Game.me) that the server refreshes, so the UI can read it but never changes it directly.

## Base stats, gear or Ability Points changed: anything showing stats should refresh.
signal stats_changed

const START_MAP := &"meadow"
const START_JOB := &"warrior"

var name := ""
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
var quests := QuestLog.new()
## Base stats plus everything worn. Kept up to date by recalc().
var stats := StatBlock.new()

func _init() -> void:
	equipment.changed.connect(recalc)

## A fresh level 1 character of `job_id` with the job's starting stats, gear and items.
static func create(char_name: String, job_id := START_JOB) -> Character:
	var c := Character.new()
	c.name = char_name
	c.job = Content.job(job_id)
	c.base = c.job.starting_stats.copy() if c.job.starting_stats else StatBlock.new()
	for e in c.job.starting_gear:
		c.equipment.put(c.equipment.place_for(e), ItemStack.exact(e))
	for entry in c.job.starting_items:
		var n := entry.roll()
		if n > 0:
			c.inventory.add(entry.item, n)
	c.recalc()
	c.refill()
	return c

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
	return gained

func spend_mp(n: int) -> bool:
	if mp < n:
		return false
	mp -= n
	return true

func restore_mp(n: int) -> void:
	mp = clampi(mp + n, 0, max_mp())

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
	if i < 0 or i >= Inventory.SLOTS or row[i] != null:
		i = inventory.first_free(ItemDef.Tab.EQUIP)
	if i < 0:
		return "Your Equip inventory is full."
	equipment.take(place)
	inventory.put(ItemDef.Tab.EQUIP, i, stack)
	return ""

## Everything about the character, for the save file and for sending to its client.
func to_dict() -> Dictionary:
	return {
		"name": name, "level": level, "xp": xp, "shards": shards, "map_id": map_id,
		"job": job.id, "base": base.to_dict(), "ap": ap,
		"hp": health.hp, "mp": mp,
		"inventory": inventory.to_dict(), "equipment": equipment.to_dict(),
		"quests": quests.to_dict(),
	}

## Loads what to_dict() wrote. Missing or bad values keep the current ones, so older saves
## still load.
func load_dict(data: Dictionary) -> void:
	name = str(data.get("name", name))
	level = maxi(1, int(data.get("level", level)))
	xp = maxi(0, int(data.get("xp", xp)))
	shards = maxi(0, int(data.get("shards", shards)))
	var m := StringName(str(data.get("map_id", map_id)))
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
	if data.get("quests") is Dictionary:
		quests.load_dict(data["quests"])
	recalc()
	health.set_hp(maxi(1, int(data.get("hp", max_hp()))))
	mp = clampi(int(data.get("mp", max_mp())), 0, max_mp())
