class_name CharacterCodec
extends RefCounted
## Turns a Character into a Dictionary (for the save file and for sending to its client)
## and back. Character.to_dict() and Character.load_dict() call these.

## Everything about the character.
## Bumped when what the stats do changes, so older saves get the essence of their stat points
## back once to spend again (1: one stat per job, Charisma, 2026-10-13).
const STAT_RULES := 1

static func to_dict(c: Character) -> Dictionary:
	return {
		"name": c.name, "level": c.level, "xp": c.xp, "essence": c.essence, "shards": c.shards, "map_id": c.map_id,
		"job": c.job.id, "came_from": String(c.came_from), "base": c.base.to_dict(), "jobs_passed": c.jobs_passed.duplicate(),
		"stat_rules": STAT_RULES,
		"hp": c.health.hp, "mp": c.mp,
		"inventory": c.inventory.to_dict(), "equipment": c.equipment.to_dict(), "storage": c.storage.to_dict(),
		"quests": c.quests.to_dict(),
		"skills": _string_keys(c.skills.learned), "skills_paid": _string_keys(c.skills.paid), "buffs": _string_keys(c.skills.buffs),
		"quickslots": c.quickslots.map(func(q: Array) -> Array: return q.map(func(v) -> String: return String(v))),
		"buddies": c.buddies.duplicate(), "fame": c.fame, "fame_day": c.fame_day, "fame_given": c.fame_given.duplicate(), "guild": c.guild,
		"book": c.book.to_dict(), "pet": String(c.pet), "pet_full": c.pet_full, "visited": c.visited.duplicate(),
		"achievements": c.achievements.duplicate(), "counters": c.counters.duplicate(),
		"scenes_seen": c.scenes_seen.duplicate(), "secrets": c.secrets.duplicate(),
	}

static func _string_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = d[k]
	return out

## Loads what to_dict() wrote into `c`. Missing or bad values keep the current ones, so
## older saves still load (and what they carry that's gone, such as an "appearance", is left
## out).
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
	if data.get("base") is Dictionary:
		c.base = StatBlock.from_dict(data["base"])
	var refund := data.get("base") is Dictionary and int(data.get("stat_rules", 0)) < STAT_RULES
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
	if data.get("skills_paid") is Dictionary:
		for k in data["skills_paid"]:
			if skills.learned.has(StringName(k)):
				skills.paid[StringName(k)] = maxi(0, int(data["skills_paid"][k]))
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
			c.quickslots[i] = [StringName(q[0]), StringName(q[1])] if q is Array and q.size() == 2 else []
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
	for key in ["visited", "achievements", "scenes_seen", "secrets", "jobs_passed"]:
		if data.get(key) is Array:
			var list: Array[String] = c.get(key)
			list.clear()
			for v in data[key]:
				list.append(str(v))
	if data.get("counters") is Dictionary:
		c.counters = {}
		for k in data["counters"]:
			c.counters[str(k)] = int(data["counters"][k])
	if not data.has("essence"):
		_essence_from_points(c, data)
	elif not data.has("level"):
		# a save from the days without levels: a level for every GROWTH_POINTS stat points it
		# bought, counted before any refund below
		c.level = mini(Character.MAX_LEVEL, 1 + c.ap.spent() / CharacterStats.GROWTH_POINTS)
		c.xp = 0
	if not data.has("jobs_passed"):
		# a save from before job switching: the jobs it advanced through count as passed
		for id in c.job_path():
			var passed: JobDef = Content.jobs.get(id)
			if passed and not passed.is_starting_job() and not c.has_passed(passed):
				c.jobs_passed.append(String(id))
	if refund:
		# the stat rules changed since this was saved: the essence of every stat point back
		c.ap.refund_all()
	if c.at_max_level():
		c.xp = 0
	c.recalc()
	c.health.set_hp(maxi(1, int(data.get("hp", c.max_hp()))))
	c.mp = clampi(int(data.get("mp", c.max_mp())), 0, c.max_mp())

## A save from before Dawn Essence (it had a level, EXP and points to spend): its level, EXP
## and the stats and skills it bought stay, and its unspent points become essence, each point
## worth what the next one would cost now.
static func _essence_from_points(c: Character, data: Dictionary) -> void:
	c.essence = 0
	var main := StringName(c.job.primary_stat)
	var stat_bought := c.ap.bought(main)
	for n in maxi(0, int(data.get("ap", 0))):
		c.essence += CharacterStats.stat_price(stat_bought + n)
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
