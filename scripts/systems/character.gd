class_name Character
extends RefCounted
## One character: name, level, EXP, job, stats, Ability Points, skills and Skill Points,
## quickslots, buffs, inventory, equipment, quests, Dawnshards, HP, MP and the map they're on. Formulas live in CharacterStats; this only
## holds and changes state.
##
## The server owns the real Character of every player. Each client keeps a copy of its own
## (Game.me) that the server refreshes, so the UI can read it but never changes it directly.

## Base stats, gear or Ability Points changed: anything showing stats should refresh.
signal stats_changed

const START_MAP := &"meadow"
const START_JOB := &"beginner"
## Quickslots on the HUD, each bound to a key (quick_1 ... quick_8).
const QUICKSLOTS := 8
## The innate attack bound to the attack key.
const BASIC_ATTACK := &"basic_attack"
## What a storage keeper charges to store one stack.
const STORE_FEE := 10

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
## Kept by storage keepers in town.
var storage := Inventory.new()
var equipment := Equipment.new()
var quests := QuestLog.new()
## Skill id -> level learned.
var skills := {}
## Unspent Skill Points.
var sp := 0
## One per quickslot: [] (empty), ["skill", id] or ["item", id].
var quickslots: Array = []
## Buffs running: skill id -> [level, ticks left].
var buffs := {}
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
var pet_full := 100
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
	c.set_quickslot(QUICKSLOTS - 2, &"item", &"red_potion")
	c.set_quickslot(QUICKSLOTS - 1, &"item", &"blue_potion")
	c.recalc()
	c.refill()
	return c

## Works out the total stats again after base stats or gear change.
func recalc() -> void:
	if job == null:
		return
	stats = base.plus(equipment.bonus())
	stats.add(skill_bonus())
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

## The weapon worn, or null.
func weapon() -> EquipDef:
	var w := equipment.at(&"weapon")
	return w.equip_def() if w else null

## What the attack key does: the weapon's own attack (a bow shoots) or the plain swing.
func basic_attack() -> SkillDef:
	var w := weapon()
	if w and w.basic_attack:
		return w.basic_attack
	return Content.skill(BASIC_ATTACK)

## The Use-tab slot of the ammo the weapon fires (first in the bag), or -1.
func ammo_slot() -> int:
	var w := weapon()
	if w == null or w.ammo == &"":
		return -1
	for i in Inventory.SLOTS:
		var s := inventory.at(ItemDef.Tab.USE, i)
		if s and s.item is AmmoDef and (s.item as AmmoDef).kind == w.ammo:
			return i
	return -1

## The extra Weapon Attack of the ammo that would be fired next.
func ammo_attack() -> int:
	var i := ammo_slot()
	return (inventory.at(ItemDef.Tab.USE, i).item as AmmoDef).attack if i >= 0 else 0

## How much of the weapon's ammo is in the bag.
func ammo_count() -> int:
	var w := weapon()
	if w == null or w.ammo == &"":
		return 0
	var n := 0
	for s in inventory.tabs[ItemDef.Tab.USE]:
		if s and s.item is AmmoDef and (s.item as AmmoDef).kind == w.ammo:
			n += s.count
	return n

## Spends `n` of the weapon's ammo, first stacks first.
func spend_ammo(n: int) -> void:
	while n > 0:
		var i := ammo_slot()
		if i < 0:
			return
		var taken := inventory.take(ItemDef.Tab.USE, i, mini(n, inventory.at(ItemDef.Tab.USE, i).count))
		n -= taken.count if taken else n

func xp_need(lvl := -1) -> int:
	if lvl < 0:
		lvl = level
	# a few kills a level at first, climbing to a few dozen by the 30s, like MapleStory
	return int(floor(15.0 * pow(lvl, 1.6) * (1.0 + lvl / 8.0)))

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
		sp += gained * job.sp_per_level
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

# ---------- skills ----------

## The jobs whose skills this character may learn: their own and every job before it.
func job_line() -> Array[StringName]:
	var out: Array[StringName] = []
	var j := job
	while j and not j.id in out:
		out.append(j.id)
		j = Content.jobs.get(j.advances_from)
	return out

## The level the character has in a skill (innate skills are always at least 1).
func skill_level(skill: SkillDef) -> int:
	if skill == null:
		return 0
	var n: int = skills.get(skill.id, 0)
	return maxi(n, 1) if skill.innate else n

## Why one more level of `skill` can't be learned now, or "".
func learn_problem(skill: SkillDef) -> String:
	if skill.innate or not skill.job in job_line():
		return "You can't learn %s." % skill.display_name
	if skill_level(skill) >= skill.max_level:
		return "%s is already at its highest level." % skill.display_name
	if sp <= 0:
		return "You have no Skill Points left."
	if skill.requires != &"":
		var need: SkillDef = Content.skills.get(skill.requires)
		if need and skill_level(need) < skill.requires_level:
			return "Learn %s to level %d first." % [need.display_name, skill.requires_level]
	return ""

## Spends a Skill Point on `skill`. A newly learned skill goes on the first free quickslot.
## Returns why not, or "".
func learn(skill: SkillDef) -> String:
	var problem := learn_problem(skill)
	if problem != "":
		return problem
	sp -= 1
	skills[skill.id] = skill_level(skill) + 1
	if skills[skill.id] == 1 and skill.is_active() and _quickslot_of(&"skill", skill.id) < 0:
		var free := quickslots.find([])
		if free >= 0:
			set_quickslot(free, &"skill", skill.id)
	recalc()
	return ""

## Why `skill` can't be used right now, or "".
func use_problem(skill: SkillDef) -> String:
	if skill == null or not skill.is_active() or skill_level(skill) <= 0:
		return "You don't know that skill."
	if skill.innate and skill != basic_attack():
		return "You can't attack like that with this weapon."
	var w := weapon()
	if not skill.weapons.is_empty() and (w == null or not w.weapon_kind in skill.weapons):
		return "%s needs a %s." % [skill.display_name, " or ".join(skill.weapons)]
	if skill.uses_ammo and ammo_count() < skill.hits:
		return "You're out of %ss." % (w.ammo if w and w.ammo != &"" else &"arrow")
	if mp < skill.mp_at(skill_level(skill)):
		return "Not enough MP for %s." % skill.display_name
	return ""

## Starts (or refreshes) a buff from `skill`.
func add_buff(skill: SkillDef) -> void:
	var lvl := skill_level(skill)
	buffs[skill.id] = [lvl, skill.duration_ticks(lvl)]
	recalc()

## Counts buffs down by `ticks`. Returns the skills whose buffs just ran out.
func tick_buffs(ticks := 1) -> Array[SkillDef]:
	var ended: Array[SkillDef] = []
	for id in buffs.keys():
		buffs[id][1] -= ticks
		if buffs[id][1] <= 0:
			buffs.erase(id)
			var s: SkillDef = Content.skills.get(id)
			if s:
				ended.append(s)
	if not ended.is_empty():
		recalc()
	return ended

## What passives and running buffs add to the stats.
func skill_bonus() -> StatBlock:
	var out := StatBlock.new()
	for id in skills:
		var s: SkillDef = Content.skills.get(id)
		if s and s.kind == SkillDef.Kind.PASSIVE:
			out.add(s.stats_at(skills[id]))
	for id in buffs:
		var s: SkillDef = Content.skills.get(id)
		if s:
			out.add(s.stats_at(buffs[id][0]))
	return out

## Extra HP and MP restored each time HP and MP regenerate, from passives.
func regen_bonus() -> Vector2i:
	var out := Vector2i.ZERO
	for id in skills:
		var s: SkillDef = Content.skills.get(id)
		if s and s.kind == SkillDef.Kind.PASSIVE:
			out += Vector2i(s.regen_hp_at(skills[id]), s.regen_mp_at(skills[id]))
	return out

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

## Puts a skill or an item (`kind` "skill" or "item") on quickslot `i`, or clears it with
## an empty kind. A skill or item already on another slot swaps with what's here.
func set_quickslot(i: int, kind: StringName, id: StringName) -> void:
	if i < 0 or i >= QUICKSLOTS:
		return
	if kind == &"":
		quickslots[i] = []
		return
	var before := _quickslot_of(kind, id)
	if before >= 0:
		quickslots[before] = quickslots[i]
	quickslots[i] = [kind, id]

func _quickslot_of(kind: StringName, id: StringName) -> int:
	for i in QUICKSLOTS:
		var q: Array = quickslots[i]
		if q.size() == 2 and StringName(q[0]) == kind and StringName(q[1]) == id:
			return i
	return -1

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

## Becomes `next` (see advance_problem) and receives its gifts. Returns why not, or "".
func advance(next: JobDef) -> String:
	var problem := advance_problem(next)
	if problem != "":
		return problem
	job = next
	for g in next.advance_gifts:
		if g.item is EquipDef:
			inventory.add_stack(ItemStack.unrolled(g.item, 1))
		elif g.item:
			inventory.add(g.item, g.min_amount)
	recalc()
	refill()
	return ""

## Whether this job can use gear meant for `families` (empty means anyone).
func can_use(families: Array[StringName]) -> bool:
	return families.is_empty() or job.family in families

## Why the character can't wear this, or "" if they can.
func equip_problem(e: EquipDef) -> String:
	if not can_use(e.jobs):
		return "Only %s can use the %s." % [EquipDef.families_text(e.jobs), e.display_name]
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

## Why the scroll in Use slot `use_slot` can't go on the gear in Equip slot `equip_slot`, or "".
func scroll_problem(use_slot: int, equip_slot: int) -> String:
	var held := inventory.at(ItemDef.Tab.USE, use_slot)
	var gear := inventory.at(ItemDef.Tab.EQUIP, equip_slot)
	if held == null or not held.item is ScrollDef or gear == null:
		return "Pick a piece of gear in your bag to use the scroll on."
	var scroll := held.item as ScrollDef
	if not scroll.fits(gear.equip_def()):
		return "The %s only works on %s gear." % [scroll.display_name, scroll.slot_text()]
	if gear.slots_left() <= 0:
		return "The %s has no upgrades left." % gear.display_name()
	return ""

## Uses the scroll in Use slot `use_slot` on the gear in Equip slot `equip_slot`: it spends
## an upgrade slot and works if `roll` is under the scroll's chance. Returns
## {"problem": why it couldn't, or "", "worked": whether the gear got the stats}.
func use_scroll(use_slot: int, equip_slot: int, roll := randf()) -> Dictionary:
	var problem := scroll_problem(use_slot, equip_slot)
	if problem != "":
		return {"problem": problem, "worked": false}
	var scroll := inventory.at(ItemDef.Tab.USE, use_slot).item as ScrollDef
	var gear := inventory.at(ItemDef.Tab.EQUIP, equip_slot)
	inventory.take(ItemDef.Tab.USE, use_slot, 1)
	gear.slots_used += 1
	var worked := roll < scroll.chance
	if worked:
		gear.upgrades += 1
		if scroll.stats:
			gear.stats.add(scroll.stats)
	return {"problem": "", "worked": worked}

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

## Everything about the character, for the save file and for sending to its client (see
## CharacterCodec).
func to_dict() -> Dictionary:
	return CharacterCodec.to_dict(self)

## Loads what to_dict() wrote. Missing or bad values keep the current ones, so older saves
## still load.
func load_dict(data: Dictionary) -> void:
	CharacterCodec.load_dict(self, data)
