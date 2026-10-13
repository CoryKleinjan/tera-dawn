extends TestCase
## Numbers in content make sense: chances are 0 to 1, amount ranges run low to high,
## HP, levels and prices are positive, shops never pay more than they charge, levels sit
## inside their map's and region's ranges, and skills, jobs and items have usable values.

const Scan := preload("res://tests/content/content_scan.gd")

func _check_drop(d: DropEntry, what: String) -> void:
	if d == null:
		return
	check(d.chance > 0.0 and d.chance <= 1.0, "%s.chance is %s, want above 0 and at most 1" % [what, d.chance])
	check(d.min_amount >= 1, "%s.min_amount is %d, want at least 1" % [what, d.min_amount])
	check(d.min_amount <= d.max_amount, "%s: min_amount %d is above max_amount %d" % [what, d.min_amount, d.max_amount])

func test_drop_entries_have_sane_chances_and_amounts() -> void:
	for m: MonsterDef in Content.monsters.values():
		for i in m.drops.size():
			_check_drop(m.drops[i], "%s: drops[%d]" % [Scan.where(m), i])
	for q: QuestDef in Content.quests.values():
		for i in q.reward_items.size():
			_check_drop(q.reward_items[i], "%s: reward_items[%d]" % [Scan.where(q), i])
	for j: JobDef in Content.jobs.values():
		for i in j.advance_gifts.size():
			_check_drop(j.advance_gifts[i], "%s: advance_gifts[%d]" % [Scan.where(j), i])
		for i in j.starting_items.size():
			_check_drop(j.starting_items[i], "%s: starting_items[%d]" % [Scan.where(j), i])

func test_gifts_and_rewards_always_arrive() -> void:
	# these are handed over, not rolled: a chance below 1 would be ignored or confusing
	for q: QuestDef in Content.quests.values():
		for i in q.reward_items.size():
			check_eq(q.reward_items[i].chance, 1.0, "%s: reward_items[%d].chance" % [Scan.where(q), i])
	for j: JobDef in Content.jobs.values():
		for i in j.advance_gifts.size():
			check_eq(j.advance_gifts[i].chance, 1.0, "%s: advance_gifts[%d].chance" % [Scan.where(j), i])
		for i in j.starting_items.size():
			check_eq(j.starting_items[i].chance, 1.0, "%s: starting_items[%d].chance" % [Scan.where(j), i])

func test_monsters_have_positive_stats() -> void:
	for m: MonsterDef in Content.monsters.values():
		var w := Scan.where(m)
		check(m.level >= 1, "%s: level is %d" % [w, m.level])
		check(m.max_hp >= 1, "%s: max_hp is %d" % [w, m.max_hp])
		check(m.attack >= 0, "%s: attack is %d" % [w, m.attack])
		check(m.exp_reward >= 1, "%s: exp_reward is %d" % [w, m.exp_reward])
		check(m.speed >= 0.0, "%s: speed is %s" % [w, m.speed])
		check(m.size.x > 0 and m.size.y > 0, "%s: size is %s" % [w, m.size])
		check(m.sprite_scale > 0, "%s: sprite_scale is %s" % [w, m.sprite_scale])
		check(m.respawn_ticks.x > 0 and m.respawn_ticks.x <= m.respawn_ticks.y, "%s: respawn_ticks %s must be positive and low to high" % [w, m.respawn_ticks])
		if m.flying:
			check(m.hover_height > 0, "%s: flying with hover_height %s" % [w, m.hover_height])
		if m.shot:
			check(m.shot_range > 0 and m.shot_cooldown > 0, "%s: shot_range %s / shot_cooldown %d must be positive" % [w, m.shot_range, m.shot_cooldown])
		if m.splits_into:
			check(m.splits_into.level <= m.level, "%s: splits into %s, which is a higher level (%d > %d)" % [w, m.splits_into.id, m.splits_into.level, m.level])

func test_bosses_outclass_their_map() -> void:
	for map: MapDef in Content.maps.values():
		var bosses := []
		var top := 0
		for s in map.spawns:
			if s and s.monster:
				if s.monster.boss:
					bosses.append(s.monster)
				else:
					top = maxi(top, s.monster.max_hp)
		for b: MonsterDef in bosses:
			check(b.max_hp > top, "%s: boss %s has %d HP, no more than the map's other monsters (%d)" % [Scan.where(map), b.id, b.max_hp, top])

func test_items_have_sane_prices_and_stacks() -> void:
	for i: ItemDef in Content.items.values():
		var w := Scan.where(i)
		check(i.sell_price >= 0, "%s: sell_price is %d" % [w, i.sell_price])
		check(i.stack_size() >= 1, "%s: stack_size is %d" % [w, i.stack_size()])
		check(i.sprite_scale > 0, "%s: sprite_scale is %s" % [w, i.sprite_scale])
		if i.quest_item:
			check(i.tab() == ItemDef.Tab.ETC, "%s: quest items belong in the Etc tab" % w)
		if i is CardDef:
			continue
		if not i.quest_item and not i.is_currency:
			check(i.sell_price >= 1, "%s: sell_price is 0, so shops won't pay for it" % w)

## Each weapon from level 15 to 35 drops from at least two monsters, one of them not a
## boss, so nobody waits on a single spawn for their next weapon.
func test_mid_game_weapons_drop_in_two_places() -> void:
	for i: ItemDef in Content.items.values():
		var e := i as EquipDef
		if e == null or e.weapon_kind == &"" or e.required_level < 15 or e.required_level > 35:
			continue
		var sources := 0
		var from_a_regular := false
		for m: MonsterDef in Content.monsters.values():
			if m.drops.any(func(d: DropEntry) -> bool: return d.item == e):
				sources += 1
				from_a_regular = from_a_regular or not m.boss
		check(sources >= 2, "%s: drops from %d monster(s), want at least 2" % [Scan.where(e), sources])
		check(from_a_regular, "%s: only a boss drops it" % Scan.where(e))

## Better weapons come only from monsters: shops sell nothing above a first job's weapon.
func test_shops_only_sell_basic_weapons() -> void:
	var first_job_level := 0
	for j in JobDef.paths_from(Character.START_JOB):
		first_job_level = maxi(first_job_level, j.advance_level)
	for s: ShopDef in Content.shops.values():
		for e in s.items:
			var w := e.item as EquipDef
			if w and w.weapon_kind != &"":
				check(w.required_level <= first_job_level, "%s: sells %s (level %d), a weapon only monsters should drop" % [Scan.where(s), w.id, w.required_level])

func test_shops_never_pay_more_than_they_charge() -> void:
	for s: ShopDef in Content.shops.values():
		for i in s.items.size():
			var e := s.items[i]
			if e == null or e.item == null:
				continue
			check(e.price >= 0, "%s: items[%d].price is %d" % [Scan.where(s), i, e.price])
			check(e.cost() > e.item.sell_price, "%s: items[%d] sells %s for %d but buys it back for %d" % [Scan.where(s), i, e.item.id, e.cost(), e.item.sell_price])

func test_no_item_is_sold_twice_in_a_shop() -> void:
	for s: ShopDef in Content.shops.values():
		var seen := {}
		for i in s.items.size():
			var e := s.items[i]
			if e and e.item:
				check(not seen.has(e.item.id), "%s: items[%d] sells %s again" % [Scan.where(s), i, e.item.id])
				seen[e.item.id] = true

func test_travel_fares_are_affordable() -> void:
	for n: NpcDef in Content.npcs.values():
		for i in n.travel.size():
			check_between(n.travel[i].price, 0, 100000, "%s: travel[%d].price" % [Scan.where(n), i])

func test_quests_have_sane_levels_counts_and_rewards() -> void:
	for q: QuestDef in Content.quests.values():
		var w := Scan.where(q)
		check(q.min_level >= 1, "%s: min_level is %d" % [w, q.min_level])
		check(q.max_level == 0 or q.max_level >= q.min_level, "%s: max_level %d is below min_level %d" % [w, q.max_level, q.min_level])
		check(q.reward_xp >= 0 and q.reward_shards >= 0, "%s: reward_xp %d / reward_shards %d is negative" % [w, q.reward_xp, q.reward_shards])
		check(q.reward_xp > 0 or q.reward_shards > 0 or not q.reward_items.is_empty(), "%s: rewards nothing" % w)
		check(q.offer_text != "" and q.progress_text != "" and q.complete_text != "", "%s: offer_text, progress_text or complete_text is empty" % w)
		for i in q.objectives.size():
			var o := q.objectives[i]
			if o == null:
				continue
			check(o.count >= 1, "%s: objectives[%d].count is %d" % [w, i, o.count])
			if o.kind == QuestObjective.Kind.COLLECT:
				check(o.drop_chance > 0.0 and o.drop_chance <= 1.0, "%s: objectives[%d].drop_chance is %s" % [w, i, o.drop_chance])
				if o.item:
					check(o.count <= o.item.stack_size() * Inventory.SLOTS, "%s: objectives[%d] wants %d %s, more than a bag holds" % [w, i, o.count, o.item.id])
			if o.kind == QuestObjective.Kind.VISIT or o.kind == QuestObjective.Kind.REACH:
				check_eq(o.count, 1, "%s: objectives[%d].count of a VISIT or REACH" % [w, i])

func test_quests_ask_for_monsters_near_their_level() -> void:
	for q: QuestDef in Content.quests.values():
		for i in q.objectives.size():
			var o := q.objectives[i]
			var m: MonsterDef = o.monster if o and o.kind == QuestObjective.Kind.KILL else null
			if m:
				check(m.level <= q.min_level + 15, "%s: objectives[%d] wants level %d %s from level %d players" % [Scan.where(q), i, m.level, m.id, q.min_level])

func test_required_quests_are_open_by_the_time_you_get_there() -> void:
	# a quest needing another one that unlocks at a higher level can never be offered first
	for q: QuestDef in Content.quests.values():
		for r in q.requires:
			var before: QuestDef = Content.quests.get(r)
			if before:
				check(before.min_level <= maxi(q.min_level, 1) or q.max_level == 0, "%s: requires %s, which opens at level %d (above %d)" % [Scan.where(q), r, before.min_level, q.min_level])
				check(q.max_level == 0 or before.min_level <= q.max_level, "%s: requires %s (level %d+) but stops at level %d" % [Scan.where(q), r, before.min_level, q.max_level])

func test_skills_have_usable_numbers() -> void:
	for s: SkillDef in Content.skills.values():
		var w := Scan.where(s)
		check(s.max_level >= 1, "%s: max_level is %d" % [w, s.max_level])
		check(s.requires_level >= 1, "%s: requires_level is %d" % [w, s.requires_level])
		check(s.mp_cost >= 0 and s.mp_at(s.max_level) >= 0, "%s: MP cost goes negative" % w)
		check(s.cooldown >= 0 and s.action_ticks >= 0, "%s: cooldown %d / action_ticks %d is negative" % [w, s.cooldown, s.action_ticks])
		if s.innate:
			check_eq(s.max_level, 1, "%s: max_level of an innate skill" % w)
		match s.kind:
			SkillDef.Kind.ATTACK:
				check(s.reach > 0 and s.height > 0, "%s: reach %s / height %s must be positive" % [w, s.reach, s.height])
				check(s.max_targets >= 1 and s.hits >= 1, "%s: max_targets %d / hits %d must be at least 1" % [w, s.max_targets, s.hits])
				check(s.damage_at(1) > 0 and s.damage_at(s.max_level) >= s.damage_at(1), "%s: damage must be positive and not fall with level" % w)
			SkillDef.Kind.BUFF:
				check(s.duration > 0, "%s: buff duration is %s" % [w, s.duration])
				check(s.duration_ticks(s.max_level) > 0, "%s: buff ends before it starts at max level" % w)
				check(s.stats != null or s.stats_per_level != null, "%s: buff adds no stats" % w)
			SkillDef.Kind.PASSIVE:
				check(s.stats != null or s.stats_per_level != null or s.regen_hp > 0 or s.regen_mp > 0 or s.regen_hp_per_level > 0 or s.regen_mp_per_level > 0,
					"%s: passive adds nothing" % w)
		if s.is_active():
			check(s.describe_level(1).size() > 0, "%s: describe_level(1) says nothing" % w)

func test_jobs_have_usable_growth() -> void:
	for j: JobDef in Content.jobs.values():
		var w := Scan.where(j)
		check_between(j.mastery, 0.1, 0.95, "%s: mastery" % w)
		check(j.base_hp > 0 and j.base_mp >= 0 and j.hp_per_level > 0 and j.mp_per_level >= 0, "%s: HP / MP growth must be positive" % w)
		check(j.ap_per_level >= 1 and j.sp_per_level >= 1, "%s: ap_per_level %d / sp_per_level %d" % [w, j.ap_per_level, j.sp_per_level])
		if j.advances_from != &"":
			var from: JobDef = Content.jobs.get(j.advances_from)
			check(j.advance_level >= 2, "%s: advance_level is %d" % [w, j.advance_level])
			if from and from.advances_from != &"":
				check(j.advance_level > from.advance_level, "%s: advance_level %d is not above %s's %d" % [w, j.advance_level, from.id, from.advance_level])

func test_job_requirements_are_reachable_with_ability_points() -> void:
	# a Beginner at the advance level must be able to meet every stat requirement
	var start: JobDef = Content.jobs.get(Character.START_JOB)
	for j: JobDef in Content.jobs.values():
		if j.advances_from != Character.START_JOB or j.advance_requirements == null or start == null:
			continue
		var budget := start.ap_per_level * (j.advance_level - 1)
		var need := 0
		for stat in StatBlock.BASE:
			need += maxi(0, j.advance_requirements.value(stat) - start.starting_stats.value(stat))
		check(need <= budget, "%s: needs %d Ability Points by level %d but a Beginner only gets %d" % [Scan.where(j), need, j.advance_level, budget])

func test_gear_has_sane_requirements_and_stats() -> void:
	for i: ItemDef in Content.items.values():
		var e := i as EquipDef
		if e == null:
			continue
		var w := Scan.where(e)
		check(e.required_level >= 0 and e.required_level <= 200, "%s: required_level is %d" % [w, e.required_level])
		for f in ["required_strength", "required_dexterity", "required_intelligence", "required_luck"]:
			check(int(e.get(f)) >= 0, "%s: %s is negative" % [w, f])
		check(e.variance >= 0 and e.upgrade_slots >= 0, "%s: variance %d / upgrade_slots %d is negative" % [w, e.variance, e.upgrade_slots])
		if e.stats:
			for f in StatBlock.FIELDS:
				check(e.stats.value(f) >= 0, "%s: stats.%s is negative" % [w, f])
			check(not e.stats.nonzero().is_empty(), "%s: stats are all 0" % w)
		if e.slot == EquipDef.Slot.WEAPON and e.stats:
			check(e.stats.attack > 0 or e.stats.magic_attack > 0, "%s: weapon has no attack" % w)

func test_use_items_have_sane_numbers() -> void:
	for i: ItemDef in Content.items.values():
		var u := i as UseDef
		if u:
			var w := Scan.where(u)
			check(u.heal_hp >= 0 and u.heal_mp >= 0 and u.pet_food >= 0 and u.cooldown >= 0, "%s: a heal, pet_food or cooldown is negative" % w)
			check_between(u.heal_hp_percent, 0, 100, "%s: heal_hp_percent" % w)
			check_between(u.heal_mp_percent, 0, 100, "%s: heal_mp_percent" % w)
		var s := i as ScrollDef
		if s:
			check(s.chance > 0.0 and s.chance <= 1.0, "%s: chance is %s" % [Scan.where(s), s.chance])

func test_level_texts_are_readable() -> void:
	for m: MapDef in Content.maps.values():
		if m.interior:
			check(m.level_text == "", "%s: a room inside a building isn't on the world map, so has no level_text" % Scan.where(m))
			continue
		if m.level_text == "Town":
			check(m.town, "%s: level_text says Town but town is false" % Scan.where(m))
			continue
		var r := Scan.level_range(m.level_text)
		check(r.x >= 1 and r.x <= r.y, "%s: level_text %s isn't \"Lv. low-high\" or Town" % [Scan.where(m), m.level_text])
	for g: RegionDef in Content.regions.values():
		var r := Scan.level_range(g.level_text)
		check(r.x >= 1 and r.x <= r.y, "%s: level_text %s isn't \"Lv. low-high\"" % [Scan.where(g), g.level_text])

func test_map_levels_sit_inside_their_region() -> void:
	for m: MapDef in Content.maps.values():
		var mine := Scan.level_range(m.level_text)
		var g: RegionDef = Content.regions.get(m.region)
		if mine.x < 0 or g == null:
			continue
		var range := Scan.level_range(g.level_text)
		check(mine.x >= range.x and mine.y <= range.y, "%s: level_text %s is outside region %s (%s)" % [Scan.where(m), m.level_text, g.id, g.level_text])

func test_map_monsters_match_its_levels() -> void:
	# maps mix in weaker monsters, but some monster must suit the map's levels and none
	# (bosses aside) may be far above them
	for m: MapDef in Content.maps.values():
		var r := Scan.level_range(m.level_text)
		if r.x < 0:
			continue
		var suits := false
		for i in m.spawns.size():
			var mon := m.spawns[i].monster if m.spawns[i] else null
			if mon == null:
				continue
			suits = suits or (mon.level >= r.x - 2 and mon.level <= r.y + 2)
			if not mon.boss:
				check(mon.level <= r.y + 3, "%s: spawns[%d] %s is level %d, well above %s" % [Scan.where(m), i, mon.id, mon.level, m.level_text])
		check(suits or m.spawns.is_empty(), "%s: no monster is near %s" % [Scan.where(m), m.level_text])

func test_towns_are_safe() -> void:
	# towns are where you wake up: nothing hostile spawns there (the starting meadow excepted)
	for m: MapDef in Content.maps.values():
		if m.town and m.id != Character.START_MAP:
			check(m.spawns.is_empty(), "%s: is a town but has %d spawns" % [Scan.where(m), m.spawns.size()])
