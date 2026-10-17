extends TestCase
## Every reference between content resolves: drops, shops, quests, NPCs and where they
## stand, spawns, portals, travel routes, jobs and their gifts, skills, monsters that split
## or shoot, gear, pets, maps and their regions. Each failure names
## the file and the field.

const Scan := preload("res://tests/content/content_scan.gd")

## True (and nothing reported) when `res` is the resource Content has under its id.
func _indexed(res: Resource, table: Dictionary, what: String) -> bool:
	if res == null:
		fail("%s is empty" % what)
		return false
	var id: StringName = res.get("id")
	if not table.has(id):
		fail("%s points at %s (%s), which Content doesn't know" % [what, id, Scan.where(res)])
		return false
	return check(table[id] == res, "%s points at a copy of %s instead of %s" % [what, Scan.where(res), Scan.where(table[id])])

func test_monster_drops_are_real_items() -> void:
	for m: MonsterDef in Content.monsters.values():
		for i in m.drops.size():
			var d := m.drops[i]
			if check(d != null, "%s: drops[%d] is empty" % [Scan.where(m), i]):
				_indexed(d.item, Content.items, "%s: drops[%d].item" % [Scan.where(m), i])

func test_shop_entries_are_real_items() -> void:
	for s: ShopDef in Content.shops.values():
		check(not s.items.is_empty(), "%s: items is empty" % Scan.where(s))
		for i in s.items.size():
			var e := s.items[i]
			if check(e != null, "%s: items[%d] is empty" % [Scan.where(s), i]):
				_indexed(e.item, Content.items, "%s: items[%d].item" % [Scan.where(s), i])

func test_shops_are_run_by_someone() -> void:
	var run := {}
	for n: NpcDef in Content.npcs.values():
		if n.shop:
			_indexed(n.shop, Content.shops, "%s: shop" % Scan.where(n))
			run[n.shop.id] = true
	for id in Content.shops:
		check(run.has(id), "%s: no NPC has it as their shop" % Scan.where(Content.shops[id]))

func test_quest_givers_and_turn_ins_stand_on_a_map() -> void:
	var placed := Scan.placed_npcs()
	for q: QuestDef in Content.quests.values():
		check(Content.npcs.has(q.giver), "%s: giver %s is not an NPC" % [Scan.where(q), q.giver])
		check(placed.has(q.giver), "%s: giver %s stands on no map" % [Scan.where(q), q.giver])
		if q.turn_in != &"":
			check(Content.npcs.has(q.turn_in), "%s: turn_in %s is not an NPC" % [Scan.where(q), q.turn_in])
			check(placed.has(q.turn_in), "%s: turn_in %s stands on no map" % [Scan.where(q), q.turn_in])

func test_quest_objectives_point_at_real_things() -> void:
	var spawned := Scan.spawned_monsters()
	for q: QuestDef in Content.quests.values():
		check(not q.objectives.is_empty(), "%s: objectives is empty" % Scan.where(q))
		for i in q.objectives.size():
			var o := q.objectives[i]
			var what := "%s: objectives[%d]" % [Scan.where(q), i]
			if not check(o != null, what + " is empty"):
				continue
			match o.kind:
				QuestObjective.Kind.KILL:
					if _indexed(o.monster, Content.monsters, what + ".monster"):
						check(spawned.has(o.monster.id), "%s.monster %s lives on no map" % [what, o.monster.id])
				QuestObjective.Kind.COLLECT:
					_indexed(o.item, Content.items, what + ".item")
					if o.drop_from:
						if _indexed(o.drop_from, Content.monsters, what + ".drop_from"):
							check(spawned.has(o.drop_from.id), "%s.drop_from %s lives on no map" % [what, o.drop_from.id])
				QuestObjective.Kind.VISIT:
					check(Content.maps.has(o.map), "%s.map %s is not a map" % [what, o.map])
				QuestObjective.Kind.REACH:
					if check(Content.maps.has(o.map), "%s.map %s is not a map" % [what, o.map]):
						var m := Content.map(o.map)
						check(o.platform > 0 and o.platform < m.platforms.size() + 1, "%s.platform %d is not a ledge on %s" % [what, o.platform, o.map])
					check(o.spot_name != "", "%s.spot_name is empty" % what)
				_:
					fail("%s.kind %d is not KILL, COLLECT, VISIT or REACH" % [what, o.kind])

func test_quest_items_only_drop_for_their_quest() -> void:
	# a quest_item that a monster drops for everyone would fill bags with unsellable junk
	for m: MonsterDef in Content.monsters.values():
		for i in m.drops.size():
			var d := m.drops[i]
			if d and d.item and d.item.quest_item:
				fail("%s: drops[%d] is quest item %s; quest items drop through QuestObjective.drop_from" % [Scan.where(m), i, d.item.id])

func test_quest_requirements_exist_and_never_loop() -> void:
	for q: QuestDef in Content.quests.values():
		for r in q.requires:
			check(Content.quests.has(r), "%s: requires %s, which is not a quest" % [Scan.where(q), r])
			check(r != q.id, "%s: requires itself" % Scan.where(q))
		for j in q.jobs:
			check(Content.jobs.has(j), "%s: jobs lists %s, which is not a job" % [Scan.where(q), j])
	# every quest must be reachable by finishing the ones before it
	for q: QuestDef in Content.quests.values():
		var seen := {}
		var todo: Array[StringName] = [q.id]
		while not todo.is_empty():
			var id: StringName = todo.pop_back()
			var cur: QuestDef = Content.quests.get(id)
			if cur == null:
				continue
			for r in cur.requires:
				if r == q.id:
					fail("%s: requires chain loops back to itself" % Scan.where(q))
					todo.clear()
					break
				if not seen.has(r):
					seen[r] = true
					todo.append(r)

func test_quest_rewards_are_real_items() -> void:
	for q: QuestDef in Content.quests.values():
		for i in q.reward_items.size():
			var r := q.reward_items[i]
			if check(r != null, "%s: reward_items[%d] is empty" % [Scan.where(q), i]):
				_indexed(r.item, Content.items, "%s: reward_items[%d].item" % [Scan.where(q), i])

func test_npc_placements_are_real_npcs() -> void:
	for m: MapDef in Content.maps.values():
		for i in m.npcs.size():
			var p := m.npcs[i]
			if check(p != null, "%s: npcs[%d] is empty" % [Scan.where(m), i]):
				_indexed(p.npc, Content.npcs, "%s: npcs[%d].npc" % [Scan.where(m), i])

func test_every_npc_stands_somewhere() -> void:
	var placed := Scan.placed_npcs()
	for id in Content.npcs:
		check(placed.has(id), "%s: no map places this NPC" % Scan.where(Content.npcs[id]))

func test_npc_services_point_at_real_things() -> void:
	for n: NpcDef in Content.npcs.values():
		for j in n.instructs:
			if check(Content.jobs.has(j), "%s: instructs %s, which is not a job" % [Scan.where(n), j]):
				check(Content.jobs[j].advances_from != &"", "%s: instructs %s, which nobody advances into" % [Scan.where(n), j])
		for i in n.travel.size():
			var r := n.travel[i]
			if not check(r != null, "%s: travel[%d] is empty" % [Scan.where(n), i]):
				continue
			var dest: MapDef = Content.maps.get(r.target_map)
			if check(dest != null, "%s: travel[%d].target_map %s is not a map" % [Scan.where(n), i, r.target_map]):
				check_between(r.target_x, 0, dest.width, "%s: travel[%d].target_x on %s" % [Scan.where(n), i, r.target_map])
			check(r.price >= 0, "%s: travel[%d].price is %d" % [Scan.where(n), i, r.price])
			check(r.by.strip_edges() != "", "%s: travel[%d].by is empty" % [Scan.where(n), i])

func test_travel_npcs_never_send_you_to_their_own_map() -> void:
	for m: MapDef in Content.maps.values():
		for p in m.npcs:
			if p and p.npc:
				for r in p.npc.travel:
					check(r.target_map != m.id, "%s: %s on %s offers a trip to %s itself" % [Scan.where(p.npc), p.npc.id, m.id, m.id])

func test_spawns_are_real_monsters() -> void:
	for m: MapDef in Content.maps.values():
		for i in m.spawns.size():
			var s := m.spawns[i]
			if check(s != null, "%s: spawns[%d] is empty" % [Scan.where(m), i]):
				_indexed(s.monster, Content.monsters, "%s: spawns[%d].monster" % [Scan.where(m), i])
				check(s.count >= 1, "%s: spawns[%d].count is %d" % [Scan.where(m), i, s.count])

func test_portals_lead_to_real_maps() -> void:
	for m: MapDef in Content.maps.values():
		for i in m.portals.size():
			var p := m.portals[i]
			if check(p != null, "%s: portals[%d] is empty" % [Scan.where(m), i]):
				check(Content.maps.has(p.target_map), "%s: portals[%d].target_map %s is not a map" % [Scan.where(m), i, p.target_map])
				check(p.target_map != m.id, "%s: portals[%d] leads back to the same map" % [Scan.where(m), i])

func test_maps_have_a_biome_region_and_town() -> void:
	for m: MapDef in Content.maps.values():
		check(m.biome != null, "%s: biome is empty" % Scan.where(m))
		check(Content.regions.has(m.region), "%s: region %s is not a region" % [Scan.where(m), m.region])
		var home: MapDef = Content.maps.get(m.return_town())
		if check(home != null, "%s: return_map %s is not a map" % [Scan.where(m), m.return_town()]):
			# the tutorial beach wakes you on the beach: its way to town opens only at its end
			check(home.town or m.id == Character.NEW_MAP, "%s: return_map %s is not a town" % [Scan.where(m), home.id])
		if not m.town:
			check(m.return_map != &"" or m.return_town() != m.id, "%s: is not a town and has no return_map" % Scan.where(m))

func test_every_region_has_maps() -> void:
	var used := {}
	for m: MapDef in Content.maps.values():
		used[m.region] = true
	for id in Content.regions:
		check(used.has(id), "%s: no map is in this region" % Scan.where(Content.regions[id]))

func test_jobs_link_up() -> void:
	for j: JobDef in Content.jobs.values():
		if j.advances_from != &"":
			check(Content.jobs.has(j.advances_from), "%s: advances_from %s is not a job" % [Scan.where(j), j.advances_from])
			check(j.advances_from != j.id, "%s: advances from itself" % Scan.where(j))
		check(String(j.family) != "", "%s: family is empty" % Scan.where(j))
		if j.partner != &"":
			check(Content.jobs.has(j.partner), "%s: partner %s is not a job" % [Scan.where(j), j.partner])
			check(j.partner != j.advances_from and j.partner != j.id, "%s: partner must be a second, different parent" % Scan.where(j))
		for i in j.advance_gifts.size():
			var g := j.advance_gifts[i]
			if check(g != null, "%s: advance_gifts[%d] is empty" % [Scan.where(j), i]):
				_indexed(g.item, Content.items, "%s: advance_gifts[%d].item" % [Scan.where(j), i])
		for i in j.starting_items.size():
			var g := j.starting_items[i]
			if check(g != null, "%s: starting_items[%d] is empty" % [Scan.where(j), i]):
				_indexed(g.item, Content.items, "%s: starting_items[%d].item" % [Scan.where(j), i])
		for i in j.starting_gear.size():
			_indexed(j.starting_gear[i], Content.items, "%s: starting_gear[%d]" % [Scan.where(j), i])
		for i in j.creator_gear.size():
			_indexed(j.creator_gear[i], Content.items, "%s: creator_gear[%d]" % [Scan.where(j), i])
	check(Content.jobs.has(Character.START_JOB), "Character.START_JOB %s is not a job" % Character.START_JOB)
	var start: JobDef = Content.jobs.get(Character.START_JOB)
	if start:
		check(start.advances_from == &"", "%s: the starting job advances from another" % Scan.where(start))

func test_starting_gear_can_be_worn_by_a_new_character() -> void:
	var c := Character.create("Rookie")
	for e in c.job.starting_gear:
		if e:
			check_eq(c.gear.equip_problem(e), "", "%s: starting_gear %s" % [Scan.where(c.job), e.id])

func test_every_advanced_job_is_taught_somewhere() -> void:
	var taught := {}
	var placed := Scan.placed_npcs()
	for n: NpcDef in Content.npcs.values():
		if placed.has(n.id):
			for j in n.instructs:
				taught[j] = true
	for j: JobDef in Content.jobs.values():
		# blends wait for a later tutor (docs/game-rules.md); first-job tutors never offer them
		if j.advances_from != &"" and j.partner == &"":
			check(taught.has(j.id), "%s: no placed NPC instructs this job" % Scan.where(j))

func test_job_gifts_suit_the_job() -> void:
	# a weapon handed over when advancing must be one the new job may wield
	for j: JobDef in Content.jobs.values():
		for g in j.advance_gifts:
			var e := g.item as EquipDef if g else null
			if e and not e.jobs.is_empty():
				check(j.family in e.jobs, "%s: advance_gifts %s is for %s, not %s" % [Scan.where(j), e.id, e.jobs, j.family])

func test_skills_link_up() -> void:
	for s: SkillDef in Content.skills.values():
		var w := Scan.where(s)
		if s.innate:
			check(s.job == &"" or Content.jobs.has(s.job), "%s: job %s is not a job" % [w, s.job])
		else:
			check(Content.jobs.has(s.job), "%s: job %s is not a job" % [w, s.job])
		if s.requires != &"":
			var r: SkillDef = Content.skills.get(s.requires)
			if check(r != null, "%s: requires %s, which is not a skill" % [w, s.requires]):
				check(r != s, "%s: requires itself" % w)
				check(s.requires_level <= r.max_level, "%s: requires_level %d but %s stops at %d" % [w, s.requires_level, r.id, r.max_level])
				var line := _job_line(s.job)
				check(r.innate or r.job in line, "%s: requires %s from job %s, outside its job line %s" % [w, r.id, r.job, line])
	check(Content.skills.has(Character.BASIC_ATTACK) and Content.skills[Character.BASIC_ATTACK].innate, "Character.BASIC_ATTACK %s is not an innate skill" % Character.BASIC_ATTACK)

func _job_line(id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	while id != &"" and Content.jobs.has(id) and not id in out:
		out.append(id)
		id = Content.jobs[id].advances_from
	return out

func test_skill_projectiles_and_effects_are_data_files() -> void:
	for s: SkillDef in Content.skills.values():
		var w := Scan.where(s)
		if s.projectile:
			check(s.projectile.resource_path.begins_with("res://data/projectiles/"), "%s: projectile is %s, not a file in data/projectiles" % [w, s.projectile.resource_path])
		for field in ["effect", "hit_effect"]:
			var e: EffectDef = s.get(field)
			if e:
				_indexed(e, Content.effects, "%s: %s" % [w, field])

func test_skill_weapon_kinds_exist_on_some_weapon() -> void:
	var kinds := {}
	for i: ItemDef in Content.items.values():
		if i is EquipDef and (i as EquipDef).weapon_kind != &"":
			kinds[(i as EquipDef).weapon_kind] = true
	for s: SkillDef in Content.skills.values():
		for k in s.weapons:
			check(kinds.has(k), "%s: weapons lists %s, which no weapon is" % [Scan.where(s), k])

func test_monsters_that_split_or_shoot_point_at_real_things() -> void:
	for m: MonsterDef in Content.monsters.values():
		var w := Scan.where(m)
		if m.splits_into:
			if _indexed(m.splits_into, Content.monsters, w + ": splits_into"):
				check(m.splits_into != m, "%s: splits into itself" % w)
				check(m.split_count >= 1, "%s: split_count is %d" % [w, m.split_count])
				check(m.splits_into.splits_into == null, "%s: splits into %s, which splits again (MapDef.roster only follows one level)" % [w, m.splits_into.id])
		for mv in m.moves:
			if not check(mv != null and mv.resource_path.begins_with("res://data/monster_moves/"), "%s: move %s is not a file in data/monster_moves" % [w, mv.resource_path if mv else "(empty)"]):
				continue
			if mv.kind == MonsterMove.Kind.SHOT:
				if check(mv.projectile != null, "%s: shot move %s fires nothing" % [w, mv.id]):
					check(mv.projectile.resource_path.begins_with("res://data/projectiles/"), "%s: %s fires %s, not a file in data/projectiles" % [w, mv.id, mv.projectile.resource_path])
					check(mv.projectile.texture != null, "%s: %s fires %s, which has no texture" % [w, mv.id, mv.projectile.resource_path])

func test_gear_points_at_real_skills_and_jobs() -> void:
	var families := {}
	for j: JobDef in Content.jobs.values():
		families[j.family] = true
	for i: ItemDef in Content.items.values():
		var e := i as EquipDef
		if e == null:
			continue
		var w := Scan.where(e)
		check(e.stats != null, "%s: stats is empty" % w)
		check(Equipment.PLACES_FOR.has(e.slot), "%s: slot %d has no place on the body" % [w, e.slot])
		if e.basic_attack:
			_indexed(e.basic_attack, Content.skills, w + ": basic_attack")
		if e.slot == EquipDef.Slot.WEAPON:
			check(e.weapon_kind != &"", "%s: weapon has no weapon_kind" % w)
		for f in e.jobs:
			check(families.has(f), "%s: jobs lists %s, which is no job's family" % [w, f])

func test_return_scrolls_go_somewhere() -> void:
	for i: ItemDef in Content.items.values():
		var u := i as UseDef
		if u and u.teleport != &"":
			check(u.teleport == &"town" or Content.maps.has(u.teleport), "%s: teleport %s is neither town nor a map" % [Scan.where(u), u.teleport])
		if u and u.use_effect:
			_indexed(u.use_effect, Content.effects, Scan.where(u) + ": use_effect")

func test_every_use_item_does_something() -> void:
	for i: ItemDef in Content.items.values():
		var u := i as UseDef
		if u:
			check(u.heal_hearts > 0 or u.heal_mp > 0 or u.heal_hearts_percent > 0 or u.heal_mp_percent > 0 or u.teleport != &"" or u.pet_food > 0,
				"%s: heals nothing, teleports nowhere and isn't pet food" % Scan.where(u))

func test_pets_have_food_and_sane_numbers() -> void:
	var food := Content.items.values().filter(func(i: ItemDef) -> bool: return i is UseDef and (i as UseDef).pet_food > 0)
	var pets := Content.items.values().filter(func(i: ItemDef) -> bool: return i is PetDef)
	check(not pets.is_empty(), "there are pets")
	if not pets.is_empty():
		check(not food.is_empty(), "there are pets but no pet food (UseDef.pet_food)")
	for p: PetDef in pets:
		check(p.loot_reach > 0 and p.loot_every > 0 and p.hunger_ticks > 0 and p.body_scale > 0, "%s: loot_reach, loot_every, hunger_ticks and body_scale must be positive" % Scan.where(p))
	for p: PetDef in pets:
		check(not p.chatter.is_empty() and p.chatter.all(func(l: String) -> bool: return l.strip_edges() != ""), "%s: chatter is empty or has blank lines" % Scan.where(p))

func test_pickup_effects_are_real_effects() -> void:
	for i: ItemDef in Content.items.values():
		if i.pickup_effect:
			_indexed(i.pickup_effect, Content.effects, Scan.where(i) + ": pickup_effect")

func test_currency_is_one_item_that_drops() -> void:
	var currency := Content.items.values().filter(func(i: ItemDef) -> bool: return i.is_currency)
	check_eq(currency.size(), 1, "currency items (Dawnshards)")
