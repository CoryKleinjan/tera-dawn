class_name Character
extends RefCounted
## One character: name, level, EXP, job, stats, quickslots, inventory, storage, quests,
## Dawnshards, HP, MP, the map they're on and what they've done. Formulas live in
## CharacterStats; this only holds and changes state. Three parts keep their own state and
## rules: `skills` (SkillBook: skills, Skill Points, buffs), `ap` (AbilityPoints) and `gear`
## (Gear: wearing gear, scrolls, ammo; what's worn is `equipment`).
##
## The server owns the real Character of every player. Each client keeps a copy of its own
## (Game.me) that the server refreshes, so the UI can read it but never changes it directly.

## Base stats, gear or Ability Points changed: anything showing stats should refresh.
signal stats_changed

const START_MAP := &"dawnrise_village"
const START_JOB := &"beginner"
## Quickslots on the HUD, each bound to a key (quick_1 ... quick_8).
const QUICKSLOTS := 8
## The innate attack bound to the attack key.
const BASIC_ATTACK := &"basic_attack"
## The level cap: EXP stops here, as there are no fields for higher levels yet.
const MAX_LEVEL := 35
## What a storage keeper charges to store one stack.
const STORE_FEE := 10

var name := ""
## Skin, face, eyes and hair, picked in the character creator.
var appearance := Appearance.new()
var level := 1
var xp := 0
var shards := 0
var mp := 0
var map_id: StringName = START_MAP
var health := Health.new()
var job: JobDef
## Stats from the job and Ability Points, before gear.
var base := StatBlock.new()
## Unspent Ability Points and the free reset.
var ap := AbilityPoints.new(self)
var inventory := Inventory.new()
## Kept by storage keepers in town.
var storage := Inventory.new()
## What's worn.
var equipment := Equipment.new()
## Putting gear on and off, upgrade scrolls and ammo.
var gear := Gear.new(self)
var quests := QuestLog.new()
## Skills learned, Skill Points and buffs running.
var skills := SkillBook.new(self)
## One per quickslot: [] (empty), ["skill", id] or ["item", id].
var quickslots: Array = []
## Base stats plus everything worn. Kept up to date by recalc().
var stats := StatBlock.new()
## Names of this character's buddies (the server keeps them both ways).
var buddies: Array[String] = []
## Fame other players gave (or took). `fame_day` is the day (days since 1970) this
## character last gave fame, and `fame_given` the day they last gave each name fame.
var fame := 0
var fame_day := -1
var fame_given := {}
## The guild's name, or "". The server's guild list is the real record.
var guild := ""
## Kills and cards of every monster met.
var book := MonsterBook.new()
## The pet that's out (a PetDef id, or empty) and how full it is (0 to 100).
var pet: StringName = &""
var pet_full := PetDef.FULL
## Every map visited, for the world map and achievements.
var visited: Array[String] = []
## Achievement ids reached (see Achievements).
var achievements: Array[String] = []
## Tallies achievements count that aren't kept anywhere else: "bosses", "scrolls", "sat", "pets", "deals".
var counters := {}

func _init() -> void:
	equipment.changed.connect(recalc)
	quickslots.resize(QUICKSLOTS)
	quickslots.fill([])

## A fresh level 1 character of `job_id` with the job's starting stats, gear and items, and
## the look and outfit picked in the character creator (`made`, null for the defaults).
static func create(char_name: String, job_id := START_JOB, made: NewCharacter = null) -> Character:
	var c := Character.new()
	c.name = char_name
	c.job = Content.job(job_id)
	c.base = c.job.starting_stats.copy() if c.job.starting_stats else StatBlock.new()
	if made == null:
		made = NewCharacter.new(job_id)
	c.appearance = made.appearance.copy()
	for e in made.starting_gear(c.job):
		c.equipment.put(c.equipment.place_for(e), ItemStack.exact(e))
	for entry in c.job.starting_items:
		var n := entry.roll()
		if n > 0:
			c.inventory.add(entry.item, n)
	c.put_starting_quickslots()
	c.recalc()
	c.refill()
	return c

## How the character looks to everyone: their appearance and the worn gear that shows
## (Paperdoll draws it). Sent in the player info other clients get (ev_player_info).
func look() -> Dictionary:
	var gear := {}
	for place in Paperdoll.SHOWN_PLACES:
		var s := equipment.at(place)
		if s:
			gear[String(place)] = String(s.item.id)
	return {"appearance": appearance.to_dict(), "gear": gear}

## Works out the total stats again after base stats or gear change.
func recalc() -> void:
	if job == null:
		return
	stats = base.plus(equipment.bonus())
	stats.add(skills.bonus())
	stats.add(book.bonus())
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

func damage_range(extra_attack := 0) -> Vector2i:
	return CharacterStats.damage_range(job, stats, extra_attack)

func magic_range() -> Vector2i:
	return CharacterStats.magic_range(job, stats)

func xp_need(lvl := -1) -> int:
	if lvl < 0:
		lvl = level
	# Intended pace, quests included, for a player hunting monsters near their level: about
	# 2 hours to Lv 10 (the first job) and 40 to the Lv 35 cap. Up to JOB_LEVEL a level takes
	# SCALE * lvl^GROWTH EXP; after it, the Lv 10 amount times (lvl / JOB_LEVEL)^JOB_GROWTH.
	# The island quests pay most of the EXP to Lv 10 (about 85,000 of 110,000), so the early
	# levels are steep enough that hunting still fills the 2 hours. Tuned with the pace bot
	# (playtest/pace-run-3.md in the project files): Lv 10 in 82-119 minutes without any EXP
	# boost, Lv 35 in 250-300 bot minutes at 10x kill EXP (about 31-49 hours; Magicians are
	# slower). Quest EXP rewards are left as they were, so quests stay worth doing; change
	# them together.
	const SCALE := 55.0
	const GROWTH := 3.0
	const JOB_LEVEL := 10
	const JOB_GROWTH := 1.8
	if lvl <= JOB_LEVEL:
		return int(floor(SCALE * pow(lvl, GROWTH)))
	return int(floor(SCALE * pow(JOB_LEVEL, GROWTH) * pow(float(lvl) / JOB_LEVEL, JOB_GROWTH)))

## Whether the character is at MAX_LEVEL, where EXP stops.
func at_max_level() -> bool:
	return level >= MAX_LEVEL

## Adds EXP and returns how many levels were gained. At MAX_LEVEL EXP stops (kept at 0).
func gain_xp(n: int) -> int:
	if at_max_level():
		xp = 0
		return 0
	xp += n
	var gained := 0
	while not at_max_level() and xp >= xp_need():
		xp -= xp_need()
		level += 1
		gained += 1
	if at_max_level():
		xp = 0
	if gained > 0:
		ap.points += gained * job.ap_per_level
		skills.points += gained * job.sp_per_level
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

# ---------- what they've done ----------

## Adds to one of the achievement tallies.
func count(kind: String, n := 1) -> void:
	counters[kind] = int(counters.get(kind, 0)) + n

## Notes a map as visited. True the first time.
func visit(id: StringName) -> bool:
	if visited.has(String(id)):
		return false
	visited.append(String(id))
	return true

## The pet that's out, or null.
func pet_def() -> PetDef:
	return Content.items.get(pet) as PetDef

# ---------- quickslots ----------

## Puts a skill or an item (`kind` "skill" or "item") on quickslot `i`, or clears it with
## an empty kind. A skill or item already on another slot swaps with what's here.
func set_quickslot(i: int, kind: StringName, id: StringName) -> void:
	if i < 0 or i >= QUICKSLOTS:
		return
	if kind == &"":
		quickslots[i] = []
		return
	var before := quickslot_of(kind, id)
	if before >= 0:
		quickslots[before] = quickslots[i]
	quickslots[i] = [kind, id]

## The quickslot holding this skill or item, or -1.
func quickslot_of(kind: StringName, id: StringName) -> int:
	for i in QUICKSLOTS:
		var q: Array = quickslots[i]
		if q.size() == 2 and StringName(q[0]) == kind and StringName(q[1]) == id:
			return i
	return -1

## Puts the job's starting items (JobDef.starting_quickslots) on the last quickslots.
func put_starting_quickslots() -> void:
	var items := job.starting_quickslots
	for i in items.size():
		set_quickslot(QUICKSLOTS - items.size() + i, &"item", items[i].id)

# ---------- storage ----------

## Puts bag slot `i` of `tab` into storage. Returns why not, or "".
func store(tab: int, i: int) -> String:
	var stack := inventory.at(tab, i)
	if stack == null:
		return ""
	if stack.item.quest_item:
		return "Quest items can't be stored."
	if shards < STORE_FEE:
		return "Storing costs %d Dawnshards." % STORE_FEE
	if not storage.has_room(stack.item, stack.count):
		return "Your storage is full."
	shards -= STORE_FEE
	inventory.take(tab, i)
	storage.add_stack(stack)
	return ""

## Takes storage slot `i` of `tab` back into the bag. Returns why not, or "".
func retrieve(tab: int, i: int) -> String:
	var stack := storage.at(tab, i)
	if stack == null:
		return ""
	if not inventory.has_room(stack.item, stack.count):
		return "Make room in your %s inventory first." % ItemDef.TAB_NAMES[tab]
	storage.take(tab, i)
	inventory.add_stack(stack)
	return ""

# ---------- jobs ----------

## The base stats still short of what advancing to `next` asks for, as {stat: amount needed}
## (empty when the stats are there; the level isn't counted).
func stats_short_of(next: JobDef) -> Dictionary:
	var out := {}
	if next.advance_requirements:
		for stat in StatBlock.BASE:
			var need := next.advance_requirements.value(stat)
			if base.value(stat) < need:
				out[stat] = need
	return out

## The jobs whose skills this character may learn: their own and every job before it.
func job_line() -> Array[StringName]:
	var out: Array[StringName] = []
	var j := job
	while j and not j.id in out:
		out.append(j.id)
		j = Content.jobs.get(j.advances_from)
	return out

## Why the character can't advance to `next`, or "" if they can.
func advance_problem(next: JobDef) -> String:
	if next.advances_from != job.id:
		return "A %s can't become a %s." % [job.display_name, next.display_name]
	if level < next.advance_level:
		return "You need to be level %d to become a %s." % [next.advance_level, next.display_name]
	if next.advance_requirements:
		for stat in StatBlock.BASE:
			if base.value(stat) < next.advance_requirements.value(stat):
				return "You need %d %s to become a %s." % [next.advance_requirements.value(stat), StatBlock.LABELS[stat], next.display_name]
	var full := inventory.tab_without_room(next.advance_gifts.map(func(g: DropEntry) -> Array: return [g.item, 1 if g.item is EquipDef else g.min_amount]))
	if full >= 0:
		return "Make room in your %s inventory first." % ItemDef.TAB_NAMES[full]
	return ""

## Becomes `next` (see advance_problem) and receives its gifts and SP. Returns why not, or "".
func advance(next: JobDef) -> String:
	var problem := advance_problem(next)
	if problem != "":
		return problem
	job = next
	skills.points += next.advance_sp
	for g in next.advance_gifts:
		if g.item is EquipDef:
			inventory.add_stack(ItemStack.unrolled(g.item, 1))
		elif g.item:
			inventory.add(g.item, g.min_amount)
	recalc()
	_wear_advance_weapon(next)
	refill()
	return ""

## Wears the first weapon among `next`'s gifts when the one worn isn't made for the new job
## (the Beginner's Training Sword), so a new Magician casts with the wand just handed over.
## A weapon of the job's own line that the player found stays on.
func _wear_advance_weapon(next: JobDef) -> void:
	var worn := gear.weapon()
	if worn and next.family in worn.jobs:
		return
	for g in next.advance_gifts:
		var e := g.item as EquipDef
		if e == null or e.slot != EquipDef.Slot.WEAPON:
			continue
		for i in Inventory.SLOTS:
			var s := inventory.at(ItemDef.Tab.EQUIP, i)
			if s and s.item == e:
				gear.equip(i)
				return

## Everything about the character, for the save file and for sending to its client (see
## CharacterCodec).
func to_dict() -> Dictionary:
	return CharacterCodec.to_dict(self)

## Loads what to_dict() wrote. Missing or bad values keep the current ones, so older saves
## still load.
func load_dict(data: Dictionary) -> void:
	CharacterCodec.load_dict(self, data)
