extends SmokeArea
## Content the game loads: monsters, maps, towns and their instructors, skills, items, jobs,
## shops and quests all reference real content, and the maps join up into one world.

## Runs the content checks, then the world graph's.
func check() -> void:
	_check(Content.monsters.size() >= 9, "monster definitions load (%d)" % Content.monsters.size())
	_check(Content.maps.has(&"meadow") and Content.maps.has(&"hollow"), "the starting maps load")
	var towns := Content.maps.values().filter(func(m: MapDef) -> bool: return m.town)
	_check(towns.size() >= 7, "there are hub towns (%d)" % towns.size())
	# instructors teach in their halls, rooms inside the towns
	var town_and_rooms := Content.maps.values().filter(func(m: MapDef) -> bool: return m.town or m.interior)
	for id in [&"warrior", &"archer", &"mage", &"thief", &"pirate"]:
		var teaches := false
		for m in town_and_rooms:
			for n in m.npcs:
				teaches = teaches or id in n.npc.instructs
		_check(teaches, "some town's instructor teaches %s" % id)
	_check(Content.skill(Character.BASIC_ATTACK) != null and Content.skill(Character.BASIC_ATTACK).innate, "the basic attack is an innate skill")
	var problems := []
	for id in Content.skills:
		var sk: SkillDef = Content.skills[id]
		if sk.icon == null:
			problems.append("skill %s has no icon" % id)
		if not sk.innate and not Content.jobs.has(sk.job):
			problems.append("skill %s belongs to unknown job %s" % [id, sk.job])
		if sk.requires != &"" and not Content.skills.has(sk.requires):
			problems.append("skill %s requires unknown skill %s" % [id, sk.requires])
		if sk.kind == SkillDef.Kind.BUFF and sk.duration <= 0 and sk.heal <= 0.0:
			problems.append("buff %s has no duration" % id)
	for id in Content.maps:
		var map: MapDef = Content.maps[id]
		var count := map.platforms.size() + 1
		for s in map.spawns:
			if s.monster == null or s.platform >= count:
				problems.append("%s: bad spawn" % id)
		for p in map.portals:
			if not Content.maps.has(p.target_map) or p.platform >= count:
				problems.append("%s: portal to %s" % [id, p.target_map])
		for n in map.npcs:
			if n.npc == null or n.platform >= count:
				problems.append("%s: bad NPC" % id)
			elif n.npc.instructs.any(func(j: StringName) -> bool: return not Content.jobs.has(j)):
				problems.append("%s: %s teaches an unknown job" % [id, n.npc.id])
		if map.region != &"" and not Content.regions.has(map.region):
			problems.append("%s: unknown region %s" % [id, map.region])
		if not Content.maps.has(map.return_town()):
			problems.append("%s: returns to unknown map %s" % [id, map.return_town()])
		for n in map.npcs:
			for route in (n.npc.travel if n.npc else []):
				if not Content.maps.has(route.target_map):
					problems.append("%s: %s travels to unknown map %s" % [id, n.npc.id, route.target_map])
		for c in map.climbables:
			if c.style == null or c.style.middle == null:
				problems.append("%s: climbable at %d has no style" % [id, c.x])
	for id in Content.monsters:
		var m: MonsterDef = Content.monsters[id]
		if m.sprite_frames == null and m.texture == null:
			problems.append("monster %s has no sprite" % id)
		for d in m.drops:
			if d.item == null:
				problems.append("monster %s drops nothing" % id)
	for id in Content.items:
		var item: ItemDef = Content.items[id]
		if item.icon == null and not item is EquipDef: # gear has no icons yet
			problems.append("item %s has no icon" % id)
		if item is EquipDef and (item as EquipDef).stats == null:
			problems.append("equip %s has no stats" % id)
	for id in Content.jobs:
		var job: JobDef = Content.jobs[id]
		if job.advances_from == &"" and (job.starting_stats == null or job.starting_gear.has(null)):
			problems.append("job %s is missing starting stats or gear" % id)
		if job.advances_from != &"" and not Content.jobs.has(job.advances_from):
			problems.append("job %s advances from unknown job %s" % [id, job.advances_from])
		for g in job.advance_gifts:
			if g == null or g.item == null:
				problems.append("job %s has an empty advancement gift" % id)
	_check(problems.is_empty(), "maps, monsters, items and jobs reference valid content %s" % [problems])
	_check(Content.jobs.has(Character.START_JOB), "the starting job is defined")
	var shop_problems := []
	for id in Content.shops:
		for e in Content.shops[id].items:
			if e == null or e.item == null or e.cost() <= 0:
				shop_problems.append(id)
	_check(not Content.shops.is_empty() and shop_problems.is_empty(), "every shop sells real items at a price %s" % [shop_problems])
	var placed := {}
	for id in Content.maps:
		for n in Content.maps[id].npcs:
			placed[n.npc.id] = true
	var quest_problems := []
	for id in Content.quests:
		var q: QuestDef = Content.quests[id]
		if not placed.has(q.giver) or not placed.has(q.turn_in_npc()) or q.objectives.is_empty():
			quest_problems.append(id)
		for r in q.requires:
			if not Content.quests.has(r):
				quest_problems.append("%s needs %s" % [id, r])
		for o in q.objectives:
			if (o.kind == QuestObjective.Kind.KILL and o.monster == null) or (o.kind == QuestObjective.Kind.COLLECT and o.item == null) \
				or (o.kind == QuestObjective.Kind.VISIT and not Content.maps.has(o.map)):
				quest_problems.append("%s has a broken objective" % id)
	_check(Content.quests.size() >= 6 and quest_problems.is_empty(), "every quest has a placed giver and real objectives %s" % [quest_problems])
	_check_world_graph()

## Every portal leads somewhere with a portal back, every map can be reached from the
## meadow, and every item a quest asks for can be found.
func _check_world_graph() -> void:
	var problems := []
	for id in Content.maps:
		var m: MapDef = Content.maps[id]
		for p in m.portals:
			var there: MapDef = Content.maps.get(p.target_map)
			if there == null:
				problems.append("%s portal to missing %s" % [id, p.target_map])
			elif not p.one_way and not there.portals.any(func(b: PortalDef) -> bool: return b.target_map == id):
				problems.append("%s -> %s has no way back" % [id, p.target_map])
			elif p.target_x < 0 or p.target_x > there.width or there.portals.any(func(b: PortalDef) -> bool: return absf(b.x - p.target_x) < 34):
				problems.append("%s -> %s lands on a portal or off the map" % [id, p.target_map])
			if p.platform >= m.platforms.size() + 1:
				problems.append("%s portal on a missing platform" % id)
		for s in m.spawns:
			if s.platform > m.platforms.size():
				problems.append("%s spawns on a missing platform" % id)
		if not m.town and m.return_town() == id and id != Character.NEW_MAP:
			problems.append("%s has no town" % id)
	# walk the portals and travel routes from the meadow
	# (and from the tutorial beach, where new characters start and nothing leads back to)
	var seen := {&"meadow": true, Character.NEW_MAP: true}
	var todo: Array[StringName] = [&"meadow", Character.NEW_MAP]
	while not todo.is_empty():
		var id: StringName = todo.pop_back()
		var nexts: Array[StringName] = Content.maps[id].neighbours()
		for n in Content.maps[id].npcs:
			for r in n.npc.travel:
				nexts.append(r.target_map)
		for n in nexts:
			if Content.maps.has(n) and not seen.has(n):
				seen[n] = true
				todo.append(n)
	for id in Content.maps:
		if not seen.has(id):
			problems.append("%s can't be reached" % id)
	_check(Content.maps.size() >= 40 and problems.is_empty(), "%d maps joined by portals both ways, all reachable %s" % [Content.maps.size(), problems])
	var dropped := {}
	for id in Content.monsters:
		for d in Content.monsters[id].drops:
			dropped[d.item.id] = true
	var missing := []
	for id in Content.quests:
		for o in Content.quests[id].objectives:
			if o.kind == QuestObjective.Kind.COLLECT and not dropped.has(o.item.id) and o.drop_from == null and Content.quests[id].gift_on_accept != o.item:
				missing.append(o.item.id)
	_check(missing.is_empty(), "every item a quest asks for drops somewhere %s" % [missing])
	var bosses := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return m.boss)
	var shooters := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return not m.projectiles().is_empty())
	var splitters := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return m.splits_into != null)
	_check(Content.monsters.size() >= 50 and bosses.size() >= 6 and shooters.size() >= 10 and splitters.size() >= 4,
		"%d monsters, with bosses, shooters and splitters" % Content.monsters.size())
	var scrolls := Content.items.values().filter(func(i: ItemDef) -> bool: return i is ScrollDef)
	_check(Content.items.size() >= 200 and scrolls.size() >= 12 and scrolls.all(func(s: ScrollDef) -> bool: return not s.slots.is_empty() and s.stats != null),
		"%d items, with upgrade scrolls for each kind of gear" % Content.items.size())
