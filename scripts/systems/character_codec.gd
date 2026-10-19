class_name CharacterCodec
extends RefCounted
## Turns a Character into a Dictionary (for the save file and for sending to its client)
## and back. Character.to_dict() and Character.load_dict() call these.

## Everything about the character.
static func to_dict(c: Character) -> Dictionary:
	return {
		"name": c.name, "shards": c.shards, "map_id": c.map_id,
		"job": c.job.id, "came_from": String(c.came_from), "jobs_passed": c.jobs_passed.duplicate(),
		"hp": c.health.hp, "mp": c.mp, "heart_shards": c.heart_shards, "mana_shards": c.mana_shards,
		"inventory": c.inventory.to_dict(), "equipment": c.equipment.to_dict(), "storage": c.storage.to_dict(),
		"quests": c.quests.to_dict(),
		"skills": _string_keys(c.skills.learned), "buffs": _string_keys(c.skills.buffs),
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
## older saves still load (and what they carry that's gone, such as a level, EXP, Dawn
## Essence, base stats or job skills (Cory Oct 19), is left out).
static func load_dict(c: Character, data: Dictionary) -> void:
	c.name = str(data.get("name", c.name))
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
			# a skill or item gone from the game (job skills, potions) leaves its quickslot empty
			if not slot.is_empty() and not (Content.skills if slot[0] == &"skill" else Content.items).has(slot[1]):
				slot = []
			c.quickslots[i] = slot
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
	if not data.has("jobs_passed"):
		# a save from before job switching: the jobs it advanced through count as passed
		for id in c.job_path():
			var passed: JobDef = Content.jobs.get(id)
			if passed and not passed.is_starting_job() and not c.has_passed(passed):
				c.jobs_passed.append(String(id))
	c.heart_shards = maxi(0, int(data.get("heart_shards", 0)))
	c.mana_shards = maxi(0, int(data.get("mana_shards", 0)))
	c.recalc()
	if not data.has("heart_shards"):
		# a save from before hearts (Oct 19 2026) counted HP and MP in the hundreds: full hearts
		c.refill()
		return
	c.health.set_hp(maxi(1, int(data.get("hp", c.max_hp()))))
	c.mp = clampi(int(data.get("mp", 0)), 0, c.max_mp())
