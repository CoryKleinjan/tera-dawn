extends TestCase
## Numbers in content make sense: chances are 0 to 1, amount ranges run low to high,
## HP and prices are positive, shops never pay more than they charge, and
## skills, jobs and items have usable values.

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
		check(m.speed >= 0.0, "%s: speed is %s" % [w, m.speed])
		check(m.size.x > 0 and m.size.y > 0, "%s: size is %s" % [w, m.size])
		check(m.sprite_scale > 0, "%s: sprite_scale is %s" % [w, m.sprite_scale])
		check(m.respawn_ticks.x > 0 and m.respawn_ticks.x <= m.respawn_ticks.y, "%s: respawn_ticks %s must be positive and low to high" % [w, m.respawn_ticks])
		if m.flying:
			check(m.hover_height > 0, "%s: flying with hover_height %s" % [w, m.hover_height])
		check(m.sight > 0, "%s: sight is %s" % [w, m.sight])
		for mv in m.moves:
			if not check(mv != null, "%s: a move is empty" % w):
				continue
			check(mv.reach > mv.min_reach and mv.windup > 0 and mv.cooldown > 0 and mv.power > 0, "%s: move %s needs reach > min_reach and a positive windup, cooldown and power" % [w, mv.id])
			if mv.kind in [MonsterMove.Kind.LUNGE, MonsterMove.Kind.CHARGE, MonsterMove.Kind.SWOOP, MonsterMove.Kind.BLINK]:
				check(mv.distance > 0 and mv.speed > 0, "%s: move %s needs a distance and speed" % [w, mv.id])
			if mv.kind == MonsterMove.Kind.SWOOP:
				check(m.flying, "%s: only fliers can swoop (%s)" % [w, mv.id])
			if m.stationary:
				check(mv.kind in [MonsterMove.Kind.SHOT, MonsterMove.Kind.SLAM], "%s: never moves, so it can't %s" % [w, mv.id])
		if m.splits_into:
			check(m.splits_into.level <= m.level, "%s: splits into %s, which is a higher level (%d > %d)" % [w, m.splits_into.id, m.splits_into.level, m.level])

func test_monsters_have_one_or_two_moves_and_bosses_three() -> void:
	for m: MonsterDef in Content.monsters.values():
		var w := Scan.where(m)
		if m.boss:
			check_eq(m.moves.size(), 3, "%s: a boss has three moves" % w)
			var kinds := {}
			for mv in m.moves:
				kinds[mv.kind] = true
			check_eq(kinds.size(), 3, "%s: a boss's three moves are all different" % w)
		else:
			check_between(m.moves.size(), 1, 2, "%s: one or two moves" % w)

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
		if i.id in Content.extra_items:
			continue
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

func test_quests_have_sane_counts_and_rewards() -> void:
	for q: QuestDef in Content.quests.values():
		var w := Scan.where(q)
		check(q.reward_shards >= 0, "%s: reward_shards %d is negative" % [w, q.reward_shards])
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
				if s.heal > 0.0 and s.duration <= 0.0:
					# a heal and nothing after it (First Aid)
					check(s.heal_at(s.max_level) >= s.heal_at(1), "%s: heal must not fall with level" % w)
					continue
				check(s.duration > 0, "%s: buff duration is %s" % [w, s.duration])
				check(s.duration_ticks(s.max_level) > 0, "%s: buff ends before it starts at max level" % w)
				check(s.stats != null or s.stats_per_level != null or s.regen_mp > 0 or s.mp_guard > 0.0 or s.hide or s.steady,
					"%s: buff does nothing while it lasts" % w)
			SkillDef.Kind.PASSIVE:
				check(s.stats != null or s.stats_per_level != null or s.regen_hp > 0 or s.regen_mp > 0 or s.regen_hp_per_level > 0 or s.regen_mp_per_level > 0,
					"%s: passive adds nothing" % w)
		if s.is_active():
			check(s.describe_level(1).size() > 0, "%s: describe_level(1) says nothing" % w)

func test_job_advances_climb_a_tier() -> void:
	for j: JobDef in Content.jobs.values():
		var w := Scan.where(j)
		if j.advances_from != &"":
			var from: JobDef = Content.jobs.get(j.advances_from)
			if from:
				check(j.tier() > from.tier(), "%s: tier %d is not above %s's %d" % [w, j.tier(), from.id, from.tier()])

func test_every_first_job_has_a_job_test_anyone_may_take() -> void:
	# no stat gate: the Job Test is the way in, and any job may take it to switch
	for j: JobDef in Content.jobs.values():
		if j.advances_from != Character.START_JOB:
			continue
		if not check(j.advance_quest != null, "%s: a first job needs a Job Test (advance_quest)" % Scan.where(j)):
			continue
		check(j.advance_quest.jobs.is_empty(), "%s: its Job Test %s is limited to %s, but any job may take it" % [Scan.where(j), j.advance_quest.id, j.advance_quest.jobs])

func test_gear_has_a_sane_tier_and_stats() -> void:
	for i: ItemDef in Content.items.values():
		if i.id in Content.extra_items:
			continue
		var e := i as EquipDef
		if e == null:
			continue
		var w := Scan.where(e)
		check(e.required_level >= 0 and e.required_level <= 200, "%s: required_level is %d" % [w, e.required_level])
		check(e.variance >= 0, "%s: variance %d is negative" % [w, e.variance])
		if e.stats:
			for f in StatBlock.FIELDS:
				check(e.stats.value(f) >= 0, "%s: stats.%s is negative" % [w, f])
			check(not e.stats.nonzero().is_empty(), "%s: stats are all 0" % w)
		if e.slot == EquipDef.Slot.WEAPON and e.stats:
			check(e.stats.attack > 0 or e.stats.magic_attack > 0, "%s: weapon has no attack" % w)

func test_use_items_have_sane_numbers() -> void:
	for i: ItemDef in Content.items.values():
		if i.id in Content.extra_items:
			continue
		var u := i as UseDef
		if u:
			var w := Scan.where(u)
			check(u.pet_food >= 0 and u.cooldown >= 0, "%s: pet_food or cooldown is negative" % w)

func test_towns_are_safe() -> void:
	# towns are where you wake up: nothing hostile spawns there (the starting meadow excepted)
	for m: MapDef in Content.maps.values():
		if m.town and m.id != Character.START_MAP:
			check(m.spawns.is_empty(), "%s: is a town but has %d spawns" % [Scan.where(m), m.spawns.size()])
