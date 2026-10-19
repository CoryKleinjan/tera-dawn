class_name CharacterCodec
extends RefCounted
## Turns a Character into a Dictionary (for the save file and for sending to its client)
## and back. Character.to_dict() and Character.load_dict() call these.

## Older saves carry base stats (STR, DEX, INT, LUK, CHA) bought with Dawn Essence or Ability
## Points, until 2026-10-17: they started at OLD_START, and every point bought comes back as the
## essence it cost (OLD_STAT_PRICE × (1 + bought / OLD_STAT_STEP) ^ PRICE_GROWTH). A save from
## the days without levels gets a level for every OLD_POINTS_PER_LEVEL points.
const OLD_START := {"strength": 12, "dexterity": 5, "intelligence": 4, "luck": 4, "charisma": 4}
const OLD_STAT_PRICE := 17.0
const OLD_STAT_STEP := 5.0
const OLD_POINTS_PER_LEVEL := 5

## Everything about the character.
static func to_dict(c: Character) -> Dictionary:
	return {
		"name": c.name, "level": c.level, "xp": c.xp, "essence": c.essence, "shards": c.shards, "map_id": c.map_id,
		"job": c.job.id, "came_from": String(c.came_from), "jobs_passed": c.jobs_passed.duplicate(),
		"hp": c.health.hp, "mp": c.mp, "heart_shards": c.heart_shards, "mana_shards": c.mana_shards,
		"inventory": c.inventory.to_dict(), "equipment": c.equipment.to_dict(), "storage": c.storage.to_dict(),
		"quests": c.quests.to_dict(),
		"skills": _string_keys(c.skills.learned), "skills_paid": _string_keys(c.skills.paid), "buffs": _string_keys(c.skills.buffs),
		"quickslots": c.quickslots.map(func(q: Array) -> Array: return q.map(func(v) -> String: return String(v))),
		"buddies": c.buddies.duplicate(), "fame": c.fame, "fame_day": c.fame_day, "fame_given": c.fame_given.duplicate(), "guild": c.guild,
		"book": c.book.to_dict(), "pet": String(c.pet), "pet_full": c.pet_full, "visited": c.visited.duplicate(),
		"achievements": c.achievements.duplicate(), "counters": c.counters.duplicate(),
		"scenes_seen": c.scenes_seen.duplicate(), "secrets": c.secrets.duplicate(),
		"relics": c.relics.duplicate(), "rest_map": String(c.rest_map), "rest_spot": c.rest_spot,
	}

static func _string_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = d[k]
	return out

## Loads what to_dict() wrote into `c`. Missing or bad values keep the current ones, so
## older saves still load (and what they carry that's gone, such as an "appearance" or base
## stats, is left out).
static func load_dict(c: Character, data: Dictionary) -> void:
	c.name = str(data.get("name", c.name))
	c.level = clampi(int(data.get("level", c.level)), 1, Character.MAX_LEVEL)
	c.xp = maxi(0, int(data.get("xp", c.xp)))
	c.essence = maxi(0, int(data.get("essence", c.essence)))
	c.shards = maxi(0, int(data.get("shards", c.shards)))
	var m := StringName(str(data.get("map_id", c.map_id)))
	c.map_id = m if Content.maps.has(m) else Character.START_MAP
	var j := StringName(str(data.get("job", Character.START_JOB)))
	if Content.jobs.has(j):
		c.job = Content.jobs[j]
	var from := StringName(str(data.get("came_from", "")))
	c.came_from = from if c.job and c.job.opens_from(from) else &""
	if data.get("inventory") is Dictionary:
		c.inventory.load_dict(data["inventory"])
	if data.get("equipment") is Dictionary:
		c.equipment.load_dict(data["equipment"])
	if data.get("storage") is Dictionary:
		c.storage.load_dict(data["storage"])
	if data.get("quests") is Dictionary:
		c.quests.load_dict(data["quests"])
	var skills := c.skills
	skills.learned.clear()
	if data.get("skills") is Dictionary:
		for k in data["skills"]:
			var s: SkillDef = Content.skills.get(StringName(k))
			if s:
				skills.learned[s.id] = clampi(int(data["skills"][k]), 0, s.max_level)
	skills.paid.clear()
	var gone: Array[StringName] = []
	if data.get("skills_paid") is Dictionary:
		for k in data["skills_paid"]:
			if skills.learned.has(StringName(k)):
				skills.paid[StringName(k)] = maxi(0, int(data["skills_paid"][k]))
			elif data.get("skills") is Dictionary and data["skills"].has(k):
				# a skill gone from the game (the job movement skills) pays back what it cost
				c.essence += maxi(0, int(data["skills_paid"][k]))
				gone.append(StringName(k))
	skills.buffs.clear()
	if data.get("buffs") is Dictionary:
		for k in data["buffs"]:
			var b: Variant = data["buffs"][k]
			if Content.skills.has(StringName(k)) and b is Array and b.size() == 2:
				skills.buffs[StringName(k)] = [int(b[0]), int(b[1])]
	if data.get("quickslots") is Array:
		var saved: Array = data["quickslots"]
		for i in Character.QUICKSLOTS:
			var q: Variant = saved[i] if i < saved.size() else []
			var slot: Array = [StringName(q[0]), StringName(q[1])] if q is Array and q.size() == 2 else []
			# a skill gone from the game leaves its quickslot empty
			if not slot.is_empty() and slot[0] == &"skill" and slot[1] in gone:
				slot = []
			c.quickslots[i] = slot
	elif not data.has("skills"):
		# a save from before skills and quickslots existed: the job's starting potions
		c.put_starting_quickslots()
	if data.get("buddies") is Array:
		c.buddies.clear()
		for b in data["buddies"]:
			c.buddies.append(str(b))
	c.fame = int(data.get("fame", c.fame))
	c.fame_day = int(data.get("fame_day", c.fame_day))
	if data.get("fame_given") is Dictionary:
		c.fame_given = {}
		for k in data["fame_given"]:
			c.fame_given[str(k)] = int(data["fame_given"][k])
	c.guild = str(data.get("guild", c.guild))
	if data.get("book") is Dictionary:
		c.book.load_dict(data["book"])
	var pet_id := StringName(str(data.get("pet", "")))
	c.pet = pet_id if Content.items.get(pet_id) is PetDef else &""
	c.pet_full = clampi(int(data.get("pet_full", c.pet_full)), 0, PetDef.FULL)
	var rest := StringName(str(data.get("rest_map", "")))
	c.rest_map = rest if Content.maps.has(rest) else &""
	c.rest_spot = maxi(0, int(data.get("rest_spot", 0)))
	for key in ["visited", "achievements", "scenes_seen", "secrets", "relics", "jobs_passed"]:
		if data.get(key) is Array:
			var list: Array[String] = c.get(key)
			list.clear()
			for v in data[key]:
				list.append(str(v))
	if data.get("counters") is Dictionary:
		c.counters = {}
		for k in data["counters"]:
			c.counters[str(k)] = int(data["counters"][k])
	var bought := old_points_bought(data)
	if not data.has("essence"):
		_essence_from_points(c, data)
	elif not data.has("level"):
		var total := 0
		for stat in bought:
			total += bought[stat]
		c.level = mini(Character.MAX_LEVEL, 1 + total / OLD_POINTS_PER_LEVEL)
		c.xp = 0
	for stat in bought:
		for n in bought[stat]:
			c.essence += old_stat_price(n)
	if not data.has("jobs_passed"):
		# a save from before job switching: the jobs it advanced through count as passed
		for id in c.job_path():
			var passed: JobDef = Content.jobs.get(id)
			if passed and not passed.is_starting_job() and not c.has_passed(passed):
				c.jobs_passed.append(String(id))
	if c.at_max_level():
		c.xp = 0
	c.heart_shards = maxi(0, int(data.get("heart_shards", 0)))
	c.mana_shards = maxi(0, int(data.get("mana_shards", 0)))
	c.recalc()
	if not data.has("heart_shards"):
		# a save from before hearts (Oct 19 2026) counted HP and MP in the hundreds: full hearts
		c.refill()
		return
	c.health.set_hp(maxi(1, int(data.get("hp", c.max_hp()))))
	c.mp = clampi(int(data.get("mp", 0)), 0, c.max_mp())

## Points an older save bought in each base stat ({stat: points}), above OLD_START.
static func old_points_bought(data: Dictionary) -> Dictionary:
	var out := {}
	var base: Variant = data.get("base")
	if not base is Dictionary:
		return out
	for stat in OLD_START:
		var n := int(base.get(stat, 0)) - int(OLD_START[stat])
		if n > 0:
			out[stat] = n
	return out

## The essence the stat point bought after `bought` others in that stat cost.
static func old_stat_price(bought: int) -> int:
	return roundi(OLD_STAT_PRICE * pow(1.0 + maxi(0, bought) / OLD_STAT_STEP, CharacterStats.PRICE_GROWTH))

## A save from before Dawn Essence (it had a level, EXP and points to spend): its level, EXP
## and the skills it bought stay, and its unspent points become essence: the Ability Points
## priced as stat points bought one after another, and each Skill Point the next skill level.
static func _essence_from_points(c: Character, data: Dictionary) -> void:
	c.essence = 0
	for n in maxi(0, int(data.get("ap", 0))):
		c.essence += old_stat_price(n)
	var skill_bought := c.skills.spent()
	for n in maxi(0, int(data.get("sp", 0))):
		c.essence += CharacterStats.skill_price(skill_bought + n)
	# what the skills it learned would have cost, so dropping one in a job switch pays it back
	var k := 0
	for id in c.skills.learned:
		var s: SkillDef = Content.skills.get(id)
		if s == null or s.innate:
			continue
		var cost := 0
		for n in int(c.skills.learned[id]):
			cost += CharacterStats.skill_price(k)
			k += 1
		c.skills.paid[id] = cost
