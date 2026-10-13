class_name CharacterCodec
extends RefCounted
## Turns a Character into a Dictionary (for the save file and for sending to its client)
## and back. Character.to_dict() and Character.load_dict() call these.

## Everything about the character.
## Bumped when what the stats do changes, so older saves get their Ability Points back once
## to spend again (1: one stat per job, Charisma, 2026-10-13).
const STAT_RULES := 1

static func to_dict(c: Character) -> Dictionary:
	return {
		"name": c.name, "appearance": c.appearance.to_dict(), "level": c.level, "xp": c.xp, "shards": c.shards, "map_id": c.map_id,
		"job": c.job.id, "came_from": String(c.came_from), "base": c.base.to_dict(), "ap": c.ap.points, "ap_reset_used": c.ap.reset_used,
		"stat_rules": STAT_RULES,
		"hp": c.health.hp, "mp": c.mp,
		"inventory": c.inventory.to_dict(), "equipment": c.equipment.to_dict(), "storage": c.storage.to_dict(),
		"quests": c.quests.to_dict(),
		"skills": _string_keys(c.skills.learned), "sp": c.skills.points, "buffs": _string_keys(c.skills.buffs), "element": c.skills.element,
		"quickslots": c.quickslots.map(func(q: Array) -> Array: return q.map(func(v) -> String: return String(v))),
		"buddies": c.buddies.duplicate(), "fame": c.fame, "fame_day": c.fame_day, "fame_given": c.fame_given.duplicate(), "guild": c.guild,
		"book": c.book.to_dict(), "pet": String(c.pet), "pet_full": c.pet_full, "visited": c.visited.duplicate(),
		"achievements": c.achievements.duplicate(), "counters": c.counters.duplicate(),
		"scenes_seen": c.scenes_seen.duplicate(),
	}

static func _string_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = d[k]
	return out

## Loads what to_dict() wrote into `c`. Missing or bad values keep the current ones, so
## older saves still load.
static func load_dict(c: Character, data: Dictionary) -> void:
	c.name = str(data.get("name", c.name))
	if data.get("appearance") is Dictionary:
		c.appearance.load_dict(data["appearance"])
	c.level = maxi(1, int(data.get("level", c.level)))
	c.xp = maxi(0, int(data.get("xp", c.xp)))
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
		c.ap.points = maxi(0, int(data.get("ap", 0)))
	else:
		# a save from before stats existed: hand out the points for the levels it has
		c.ap.points = (c.level - 1) * c.job.ap_per_level
	c.ap.reset_used = bool(data.get("ap_reset_used", c.ap.reset_used))
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
	if data.has("sp"):
		skills.points = maxi(0, int(data["sp"]))
	else:
		# a save from before skills existed: hand out the points for the levels it has
		skills.points = (c.level - 1) * c.job.sp_per_level
	skills.buffs.clear()
	if data.get("buffs") is Dictionary:
		for k in data["buffs"]:
			var b: Variant = data["buffs"][k]
			if Content.skills.has(StringName(k)) and b is Array and b.size() == 2:
				skills.buffs[StringName(k)] = [int(b[0]), int(b[1])]
	skills.element = clampi(int(data.get("element", 0)), 0, SkillBook.ELEMENTS.size() - 1)
	if data.get("quickslots") is Array:
		var saved: Array = data["quickslots"]
		for i in Character.QUICKSLOTS:
			var q: Variant = saved[i] if i < saved.size() else []
			c.quickslots[i] = [StringName(q[0]), StringName(q[1])] if q is Array and q.size() == 2 else []
	elif not data.has("sp"):
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
	for key in ["visited", "achievements", "scenes_seen"]:
		if data.get(key) is Array:
			var list: Array[String] = c.get(key)
			list.clear()
			for v in data[key]:
				list.append(str(v))
	if data.get("counters") is Dictionary:
		c.counters = {}
		for k in data["counters"]:
			c.counters[str(k)] = int(data["counters"][k])
	if refund:
		# the stat rules changed since this was saved: every Ability Point back to spend again
		c.ap.refund_all()
	c.recalc()
	c.health.set_hp(maxi(1, int(data.get("hp", c.max_hp()))))
	c.mp = clampi(int(data.get("mp", c.max_mp())), 0, c.max_mp())
