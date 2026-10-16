class_name TestCharacters
extends RefCounted
## Developer-only test characters: one per job with STAT_POINTS stat points bought, wearing the
## best gear that job can wear up to GEAR_TIER, with every skill learned to its highest level
## and plenty of Dawnshards and Dawn Essence.
## Everything is read from the data, so a new job, skill or piece of gear shows up here with
## no code change.
##
## Each starts in its job's town (home_town), every time character select lists them.
##
## They're saved in their own folder (FOLDER, inside this computer's character saves), never
## with the player's own characters. With the Developer setting on (DevSettings), Play solo,
## Host and Join list them instead (see Net.open_saves). Only debug builds (the editor, or a
## debug export) honour it, so a shipped game never can.

## Which characters to list: the player's own, the test characters, or the test characters
## made again from scratch (picking up new gear).
enum Mode { OFF, ON, REBUILD }

## The test characters' folder, inside the character saves.
const FOLDER := "dev"
## A test character is called this plus its job's name (cut to CharacterStore.MAX_NAME).
const NAME_PREFIX := "Dev "
const SHARDS := 50000
## Dawn Essence left over to try buying with.
const ESSENCE := 5000
## The gear tier test characters wear up to (EquipDef.required_level, until gear tiers come
## from the maps): the top of the game's content so far.
const GEAR_TIER := 35
## Stat points test characters have bought, all told: what a player that far along would.
const STAT_POINTS := (GEAR_TIER - 1) * CharacterStats.GROWTH_POINTS

## Whether this build may make and use test characters: never in a release export.
static func allowed() -> bool:
	return OS.is_debug_build()

## Every job, the starting job first, then by how many advancements it takes and its name.
static func jobs() -> Array[JobDef]:
	var out: Array[JobDef] = []
	for j: JobDef in Content.jobs.values():
		out.append(j)
	out.sort_custom(func(a: JobDef, b: JobDef) -> bool:
		var da := path_to(a).size()
		var db := path_to(b).size()
		return da < db if da != db else a.display_name < b.display_name)
	return out

## The jobs a Beginner advances through to become `job`, in order (empty for the starting job).
static func path_to(job: JobDef) -> Array[JobDef]:
	var out: Array[JobDef] = []
	var j := job
	while j and j.id != Character.START_JOB and not j in out:
		out.push_front(j)
		j = Content.jobs.get(j.advances_from)
	return out

## Makes sure `store` has one test character of every job, making the ones missing, or
## every one again when `rebuild`. Each one kept is put back in its job's town.
static func prepare(store: CharacterStore, rebuild: bool) -> void:
	var have := {}
	for n in store.names():
		var c := store.load_character(n)
		if c and not have.has(c.job):
			have[c.job] = c
	for job in jobs():
		var kept: Character = have.get(job)
		if kept and not rebuild:
			kept.map_id = home_town(job)
			store.save(kept)
		else:
			store.save(build(kept.name if kept else _free_name(store, job), job))

## A name for a new `job` test character that `store` doesn't have yet.
static func _free_name(store: CharacterStore, job: JobDef) -> String:
	var base := name_for(job)
	var out := base
	var n := 2
	while store.exists(out):
		out = base.substr(0, CharacterStore.MAX_NAME - str(n).length()) + str(n)
		n += 1
	return out

## The name a test character of `job` is first offered.
static func name_for(job: JobDef) -> String:
	return CharacterStore.clean_name(NAME_PREFIX + job.display_name)

## The town a `job` test character starts in: the town of the instructor who teaches that
## job, or the nearest job before it that has one (a blend: its first parent's town). The starting job (no instructor) starts
## where every new character does, Character.START_MAP.
static func home_town(job: JobDef) -> StringName:
	var line := path_to(job)
	line.reverse()
	for j in line:
		if j.partner != &"":
			continue # a blend is taught in both its parents' towns: start in the first one's
		for m: MapDef in Content.maps.values():
			for n in m.npcs:
				if n.npc and j.id in n.npc.instructs:
					var town := m.return_town()
					if Content.maps.has(town):
						return town
	return Character.START_MAP

## A test character of `job` called `char_name`.
static func build(char_name: String, job: JobDef) -> Character:
	var c := Character.create(char_name, Character.START_JOB)
	# advanced the way a player would, so stats bought and job gifts add up as usual
	for next in path_to(job):
		if next.advance_quest:
			c.quests.done[next.advance_quest.id] = true
		var problem := c.advance(next)
		if problem != "":
			push_warning("Test character %s couldn't become a %s: %s" % [char_name, next.display_name, problem])
			break
	_wear_best_gear(c)
	_buy_stats(c)
	_learn_every_skill(c)
	c.shards = SHARDS
	c.essence = ESSENCE
	c.map_id = home_town(job)
	c.recalc()
	c.refill()
	return c

## Buys `n` points of `stat` for `c` with Dawn Essence given for them.
static func grant_stat(c: Character, stat: StringName, n: int) -> void:
	for i in maxi(0, n):
		c.essence += c.ap.price(stat)
		c.ap.buy(stat)

# ---------- gear ----------

## The best piece of each kind of gear `c`'s job can wear up to GEAR_TIER, as place -> EquipDef
## (see best_gear_for).
static func best_gear(c: Character) -> Dictionary:
	return best_gear_for(c.job, GEAR_TIER)

## The best gear a `job` character can wear up to gear tier `lvl`, as Equipment place -> EquipDef:
## per kind, the highest required level, then the most stats (weapon attack counts most).
## A kind with more than one place (rings) fills each with the next best piece. The weapon
## is the best of the kind the job is handed first when it advances, when it has one, and
## the off-hand slot takes the job's own off-hand when it has one.
static func best_gear_for(job: JobDef, lvl: int) -> Dictionary:
	var by_slot := {}
	for e in _wearable(job, lvl):
		if not by_slot.has(e.slot):
			by_slot[e.slot] = []
		by_slot[e.slot].append(e)
	var out := {}
	for slot: EquipDef.Slot in by_slot:
		var pieces: Array = by_slot[slot]
		if slot == EquipDef.Slot.SHIELD:
			pieces.sort_custom(func(a: EquipDef, b: EquipDef) -> bool: return _better_offhand(job, a, b))
		else:
			pieces.sort_custom(_better)
		if slot == EquipDef.Slot.WEAPON:
			out[&"weapon"] = best_weapons(job, lvl)[0]
			continue
		var places: Array = Equipment.PLACES_FOR[slot]
		for i in mini(places.size(), pieces.size()):
			out[places[i]] = pieces[i]
	return out

## The best weapon of each kind `job` can use at `lvl`, the one to wield first.
static func best_weapons(job: JobDef, lvl: int) -> Array[EquipDef]:
	var best := {}
	for e in _wearable(job, lvl):
		if e.slot == EquipDef.Slot.WEAPON and (not best.has(e.weapon_kind) or _better(e, best[e.weapon_kind])):
			best[e.weapon_kind] = e
	var out: Array[EquipDef] = []
	for e: EquipDef in best.values():
		out.append(e)
	var main := _main_weapon_kind(job)
	out.sort_custom(func(a: EquipDef, b: EquipDef) -> bool:
		if (a.weapon_kind == main) != (b.weapon_kind == main):
			return a.weapon_kind == main
		return _better(a, b))
	return out

## The weapon kind `job` is handed first when it advances (a Pirate's knuckle), or empty.
static func _main_weapon_kind(job: JobDef) -> StringName:
	for g in job.advance_gifts:
		var e := g.item as EquipDef
		if e and e.slot == EquipDef.Slot.WEAPON:
			return e.weapon_kind
	return &""

## Whether `a` beats `b` in the off-hand slot: an off-hand made for `job` (a Thief's stars, a
## Pirate's pistol) before one anyone can wear (a shield), then the better piece.
static func _better_offhand(job: JobDef, a: EquipDef, b: EquipDef) -> bool:
	var own_a := job.family in a.jobs
	if own_a != (job.family in b.jobs):
		return own_a
	return _better(a, b)

## Every piece of gear meant for `job`'s line (or anyone) up to gear tier `lvl`.
static func _wearable(job: JobDef, lvl: int) -> Array[EquipDef]:
	var out: Array[EquipDef] = []
	for it: ItemDef in Content.items.values():
		var e := it as EquipDef
		if e and (e.jobs.is_empty() or job.wear_families().any(func(f: StringName) -> bool: return f in e.jobs)) and e.required_level <= lvl:
			out.append(e)
	return out

## Whether `a` is better gear than `b`: a higher required level, then more stats, then its id
## (so the pick never changes from run to run).
static func _better(a: EquipDef, b: EquipDef) -> bool:
	if a.required_level != b.required_level:
		return a.required_level > b.required_level
	var sa := _stat_score(a)
	var sb := _stat_score(b)
	if sa != sb:
		return sa > sb
	return String(a.id) < String(b.id)

static func _stat_score(e: EquipDef) -> int:
	if e.stats == null:
		return 0
	var out := 0
	for stat in StatBlock.FIELDS:
		out += e.stats.value(stat)
	return out + 10 * (e.stats.attack + e.stats.magic_attack)

## Swaps everything worn for the best gear, keeping the job's other best weapons in the bag.
static func _wear_best_gear(c: Character) -> void:
	for place in c.equipment.worn.keys():
		var old := c.equipment.take(place)
		if old:
			c.inventory.add_stack(old)
	var gear := best_gear(c)
	for place: StringName in gear:
		c.equipment.put(place, ItemStack.exact(gear[place]))
	for e in best_weapons(c.job, GEAR_TIER).slice(1):
		c.inventory.add_stack(ItemStack.exact(e))

# ---------- stats and skills ----------

## Buys stats up to STAT_POINTS: first whatever the worn gear still asks for, then the rest
## the Auto button's way (the job's damage stats, the cheaper first).
static func _buy_stats(c: Character) -> void:
	for s: ItemStack in c.equipment.worn.values():
		var reqs := s.equip_def().requirements()
		for stat in StatBlock.BASE:
			grant_stat(c, stat, int(reqs.get(stat, 0)) - c.stats.value(stat))
	var stats := c.job.damage_stats()
	while c.ap.spent() < STAT_POINTS:
		var next: StringName = stats[0]
		for stat in stats:
			if c.ap.price(stat) < c.ap.price(next):
				next = stat
		grant_stat(c, next, 1)

## Every skill of the job line at its highest level, learned in an order its requirements
## allow, so new skills go on the quickslots as they would for a player.
static func _learn_every_skill(c: Character) -> void:
	var line := c.job_line()
	var todo: Array[SkillDef] = []
	for s: SkillDef in Content.skills.values():
		if not s.innate and s.job in line:
			todo.append(s)
	todo.sort_custom(func(a: SkillDef, b: SkillDef) -> bool: return String(a.id) < String(b.id))
	var learned := true
	while learned:
		learned = false
		for s in todo:
			c.essence += c.skills.price()
			while c.skills.learn_problem(s) == "":
				c.skills.learn(s)
				c.essence += c.skills.price()
				learned = true
	c.essence = 0
