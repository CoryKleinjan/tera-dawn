extends TestCase
## Character rules: Dawn Essence and growth, HP and MP, recalc, buying stats, skills bought
## with essence, buffs and their expiry, quickslots, storage, job advancement and switching, tallies,
## visited maps, pets, and a fresh character from real content.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

# ---------- Dawn Essence and growth ----------

func test_gain_essence_adds_up_and_never_takes_away() -> void:
	var c := fx.character()
	check_eq(c.essence, 0, "a fresh character has none")
	c.gain_essence(15)
	check_eq(c.essence, 15, "added")
	c.gain_essence(0)
	check_eq(c.essence, 15, "zero gain")
	c.gain_essence(-5)
	check_eq(c.essence, 15, "a negative gain takes nothing")
	c.gain_essence(27)
	check_eq(c.essence, 42, "adds up")

func test_stat_prices_climb_with_each_point_in_a_stat() -> void:
	# 17 × (1 + n / 5) ^ 2.1, rounded
	var want := {0: 17, 1: 25, 2: 34, 3: 46, 4: 58, 5: 73, 10: 171, 19: 458}
	for n in want:
		check_eq(CharacterStats.stat_price(n), want[n], "point %d" % (n + 1))
	for n in range(0, 200):
		check(CharacterStats.stat_price(n + 1) > CharacterStats.stat_price(n), "point %d costs more than %d" % [n + 2, n + 1])

func test_skill_prices_climb_with_each_level_bought() -> void:
	# 17 × (1 + k / 3) ^ 2.1, rounded
	var want := {0: 17, 1: 31, 2: 50, 3: 73, 9: 312}
	for k in want:
		check_eq(CharacterStats.skill_price(k), want[k], "level %d" % (k + 1))
	for k in range(0, 200):
		check(CharacterStats.skill_price(k + 1) > CharacterStats.skill_price(k), "level %d costs more than %d" % [k + 2, k + 1])

func test_buying_a_stat_leaves_max_hp_to_levels() -> void:
	var c := fx.character()
	c.health.damage(30)
	c.essence = 1000
	check_eq(c.ap.buy(&"dexterity", 5), 5, "five points")
	check_eq(c.health.max_hp, 60, "max HP comes from levels")
	check_eq(c.health.hp, 30, "still hurt")

# ---------- EXP and levels ----------

func test_xp_need_formula() -> void:
	var c := fx.character()
	# 27.5 * lvl^3 up to Lv 10, then 27,500 * (lvl / 10)^1.8
	var want := {1: 27, 2: 220, 3: 742, 5: 3437, 10: 27500, 11: 32646, 20: 95760, 30: 198678, 35: 262213}
	for lvl in want:
		check_eq(c.xp_need(lvl), want[lvl], "level %d" % lvl)
	c.level = 5
	check_eq(c.xp_need(), 3437, "defaults to own level")

func test_xp_need_always_grows() -> void:
	var c := fx.character()
	for lvl in range(1, 200):
		check(c.xp_need(lvl + 1) > c.xp_need(lvl), "level %d to %d" % [lvl, lvl + 1])

func test_gain_xp_below_need_keeps_level() -> void:
	var c := fx.character()
	check_eq(c.gain_xp(15), 0, "no level")
	check_eq(c.level, 1, "still 1")
	check_eq(c.xp, 15, "xp kept")
	check_eq(c.gain_xp(0), 0, "zero gain")
	check_eq(c.xp, 15, "unchanged")

func test_gain_xp_exactly_need_levels_up_with_zero_left() -> void:
	var c := fx.character()
	check_eq(c.gain_xp(27), 1, "one level")
	check_eq(c.level, 2, "level 2")
	check_eq(c.xp, 0, "nothing left over")

func test_gain_xp_many_levels_at_once() -> void:
	var c := fx.character()
	check_eq(c.gain_xp(27 + 220 + 742 + 10), 3, "three levels")
	check_eq(c.level, 4, "level 4")
	check_eq(c.xp, 10, "leftover")

func test_exp_stops_at_the_level_cap() -> void:
	var c := fx.character()
	c.level = Character.MAX_LEVEL - 1
	c.xp = c.xp_need() - 10
	check_eq(c.gain_xp(c.xp_need() * 3), 1, "one level, to the cap")
	check_eq(c.level, Character.MAX_LEVEL, "at the cap")
	check(c.at_max_level(), "at max level")
	check_eq(c.xp, 0, "the rest is dropped")
	check_eq(c.gain_xp(1000), 0, "no more levels")
	check_eq(c.xp, 0, "and no EXP")
	check_eq(c.level, Character.MAX_LEVEL, "still at the cap")

func test_many_levels_at_once_stop_at_the_cap() -> void:
	var c := fx.character()
	c.level = Character.MAX_LEVEL - 3
	check_eq(c.gain_xp(1 << 40), 3, "three levels and no further")
	check_eq(c.level, Character.MAX_LEVEL, "capped")

func test_level_up_raises_max_and_refills() -> void:
	var c := fx.character()
	c.health.damage(30)
	c.spend_mp(10)
	c.gain_xp(27)
	check_eq(c.max_hp(), 70, "50 + 2 × 10")
	check_eq(c.health.max_hp, 70, "health max follows")
	check_eq(c.health.hp, 70, "refilled")
	check_eq(c.mp, 30, "MP refilled to 20 + 2 × 5")

func test_no_level_means_no_refill() -> void:
	var c := fx.character()
	c.health.damage(30)
	c.gain_xp(5)
	check_eq(c.health.hp, 30, "still hurt")

# ---------- HP, MP and recalc ----------

func test_spend_and_restore_mp() -> void:
	var c := fx.character()  # max MP 25
	check(c.spend_mp(10), "can spend")
	check_eq(c.mp, 15, "spent")
	check(not c.spend_mp(16), "can't overspend")
	check_eq(c.mp, 15, "unchanged on failure")
	check(c.spend_mp(15), "can spend to zero")
	c.restore_mp(100)
	check_eq(c.mp, 25, "restore capped")
	c.restore_mp(-100)
	check_eq(c.mp, 0, "never negative")

func test_recalc_clamps_hp_and_mp_when_gear_comes_off() -> void:
	var c := fx.character()
	c.equipment.put(&"hat", ItemStack.exact(fx.equip(&"t_hat", EquipDef.Slot.HAT, {"max_hp": 100, "max_mp": 50})))
	c.refill()
	check_eq(c.health.hp, 160, "full with gear")
	check_eq(c.mp, 75, "full MP with gear")
	c.equipment.take(&"hat")
	check_eq(c.health.hp, 60, "HP clamped")
	check_eq(c.mp, 25, "MP clamped")

func test_recalc_emits_stats_changed() -> void:
	var c := fx.character()
	var n := [0]
	c.stats_changed.connect(func() -> void: n[0] += 1)
	c.recalc()
	check_eq(n[0], 1, "emitted")

func test_recalc_without_job_does_nothing() -> void:
	var c := Character.new()
	c.recalc()
	check(c.job == null, "no crash without a job")

func test_damage_range_uses_total_stats() -> void:
	var c := fx.character(null, {"strength": 20, "dexterity": 10})
	c.equipment.put(&"weapon", ItemStack.exact(fx.equip(&"t_a", EquipDef.Slot.WEAPON, {"attack": 10})))
	check_eq(c.damage_range(), Vector2i(7, 14), "range: 20 STR × 3.6 × 10 / 100 × 2")

# ---------- Ability Points ----------

func test_buy_stat_spends_essence_at_its_price() -> void:
	var c := fx.character(null, {"strength": 4})
	check_eq(c.ap.bought(&"strength"), 4, "4 points above a start of 0")
	check_eq(c.ap.price(&"strength"), 58, "the 5th point")
	c.essence = 58 + 5
	check_eq(c.ap.buy(&"strength"), 1, "bought")
	check_eq(c.base.strength, 5, "base")
	check_eq(c.stats.strength, 5, "total recalculated")
	check_eq(c.essence, 5, "paid 58")
	check_eq(c.ap.price(&"strength"), 73, "the next point costs more")
	check_eq(c.ap.price(&"luck"), 17, "a stat with nothing bought is still cheap")
	for s in StatBlock.BASE:
		c.essence = c.ap.price(s)
		check_eq(c.ap.buy(s), 1, "%s allowed" % s)
		check_eq(c.essence, 0, "%s paid exactly" % s)

func test_buy_stat_refuses_without_essence_or_bad_stat() -> void:
	var c := fx.character()
	c.essence = 16
	check_eq(c.ap.buy(&"strength"), 0, "1 short of 17")
	check_eq(c.essence, 16, "nothing spent")
	c.essence = 1000
	check_eq(c.ap.buy(&"attack"), 0, "attack isn't a base stat")
	check_eq(c.ap.buy(&"max_hp"), 0, "max HP isn't either")
	check_eq(c.ap.buy(&"nonsense"), 0, "unknown stat")
	check_eq(c.essence, 1000, "essence kept")
	check_eq(c.base.attack, 0, "nothing raised")
	check_eq(c.base.strength, 0, "nothing raised")

func test_buy_stat_buys_several_but_only_what_essence_pays_for() -> void:
	var c := fx.character(null, {"luck": 4})
	c.essence = 58 + 73 + 10
	check_eq(c.ap.buy(&"luck", 3), 2, "the 5th and 6th points, not the 7th")
	check_eq(c.base.luck, 6, "LUK")
	check_eq(c.essence, 10, "what's left")
	c.essence = 1000
	check_eq(c.ap.buy(&"luck", 0), 0, "zero points")
	check_eq(c.ap.buy(&"luck", -2), 0, "negative points")
	check_eq(c.essence, 1000, "essence kept")

func test_auto_buys_the_damage_stat_while_it_can() -> void:
	var c := fx.character(null, {"strength": 10, "dexterity": 5})
	c.essence = 171 + 196 + 222 + 1
	check_eq(c.ap.auto(), 3, "three points")
	check_eq(c.base.strength, 13, "all in STR")
	check_eq(c.base.dexterity, 5, "DEX untouched")
	check_eq(c.essence, 1, "left over: less than the next point")
	check_eq(c.ap.auto(), 0, "nothing more to buy")

func test_auto_for_a_blend_buys_the_cheaper_damage_stat_first() -> void:
	var j := fx.job()
	j.secondary_stat = &"dexterity"
	var c := fx.character(j, {"strength": 10, "dexterity": 5})
	c.essence = 73 + 89
	check_eq(c.ap.auto(), 2, "two points")
	check_eq([c.base.strength, c.base.dexterity], [10, 7], "both in the cheaper DEX")
	check_eq(c.essence, 0, "all spent")

func test_spent_counts_points_above_the_start_and_what_they_cost() -> void:
	var j := fx.job()
	j.starting_stats = UnitHelpers.stats({"strength": 4, "luck": 4})
	var c := fx.character(j, {"strength": 6, "dexterity": 1, "luck": 3})
	check_eq(c.ap.bought(&"strength"), 2, "STR above its start")
	check_eq(c.ap.bought(&"luck"), 0, "below the start counts as none")
	check_eq(c.ap.spent(), 3, "2 STR and 1 DEX")
	check_eq(c.ap.essence_spent(), 17 + 25 + 17, "each stat's points priced from its own first")

func test_refund_all_hands_back_the_essence_of_every_point_above_the_start() -> void:
	var j := fx.job()
	j.starting_stats = UnitHelpers.stats({"strength": 4, "luck": 4})
	var c := fx.character(j, {"strength": 14, "dexterity": 3, "luck": 6})
	c.essence = 2
	c.ap.refund_all()
	# 10 STR points: 723, 3 DEX: 76, 2 LUK: 42
	check_eq(c.essence, 2 + 723 + 76 + 42, "essence back")
	check_eq([c.base.strength, c.base.dexterity, c.base.luck], [4, 0, 4], "back to the start")
	check_eq(c.ap.spent(), 0, "nothing bought")

# ---------- skills ----------

func test_job_line_walks_back_through_advances() -> void:
	var first := fx.job(&"t_job")
	var second := fx.job(&"t_second", &"t_family", &"t_job")
	var third := fx.job(&"t_third", &"t_family", &"t_second")
	var c := fx.character(third)
	check_eq(Array(c.job_line()), [&"t_third", &"t_second", &"t_job"], "whole line")
	check_eq(Array(fx.character(first).job_line()), [&"t_job"], "first job alone")
	second.advances_from = &"t_third"
	check_eq(c.job_line().size(), 2, "a loop stops instead of hanging")

func test_skill_level_innate_and_null() -> void:
	var c := fx.character()
	var s := fx.skill()
	check_eq(c.skills.level(null), 0, "null")
	check_eq(c.skills.level(s), 0, "unlearned")
	s.innate = true
	check_eq(c.skills.level(s), 1, "innate is at least 1")

func test_learn_spends_essence_and_raises_level() -> void:
	var c := fx.character()
	var s := fx.skill()
	check_eq(c.skills.price(), 17, "the first skill level")
	c.essence = 17 + 31
	check_eq(c.skills.learn(s), "", "learned")
	check_eq(c.essence, 31, "paid 17")
	check_eq(c.skills.price(), 31, "the next level costs more")
	check_eq(c.skills.learn(s), "", "again")
	check_eq(c.skills.level(s), 2, "level 2")
	check_eq(c.skills.spent(), 2, "two levels bought")
	check_eq(c.essence, 0, "essence spent")
	check_eq(c.skills.paid, {&"t_skill": 17 + 31}, "what was paid is kept")
	check_eq(c.skills.learn(s), "You need 50 Dawn Essence for that.", "out of essence")
	check_eq(c.skills.level(s), 2, "unchanged")

func test_skill_price_counts_levels_of_every_skill() -> void:
	var c := fx.character()
	var a := fx.skill(&"t_a")
	var b := fx.skill(&"t_b")
	var innate := fx.skill(&"t_innate")
	innate.innate = true
	c.essence = 10000
	c.skills.learn(a)
	c.skills.learn(b)
	c.skills.learned[innate.id] = 1
	check_eq(c.skills.spent(), 2, "one of each, innate skills not counted")
	check_eq(c.skills.price(), 50, "the third level bought")
	check_eq(c.essence, 10000 - 17 - 31, "paid the first two prices")

func test_can_learn_any_needs_essence_and_a_skill_to_learn() -> void:
	var c := fx.character()
	fx.skill(&"t_elsewhere", SkillDef.Kind.ATTACK, &"t_someone_else")
	c.essence = 10000
	check(not c.skills.can_learn_any(), "no skill of this job")
	var s := fx.skill()
	c.essence = 16
	check(not c.skills.can_learn_any(), "1 short")
	c.essence = 17
	check(c.skills.can_learn_any(), "enough for the first level")
	s.max_level = 1
	c.skills.learned[s.id] = 1
	c.essence = 10000
	check(not c.skills.can_learn_any(), "the only skill is maxed")

func test_learn_refused_cases() -> void:
	var c := fx.character()
	c.essence = 10000
	var innate := fx.skill(&"t_innate")
	innate.innate = true
	check_ne(c.skills.learn_problem(innate), "", "innate")
	var other := fx.skill(&"t_other", SkillDef.Kind.ATTACK, &"t_someone_else")
	check_ne(c.skills.learn_problem(other), "", "another job's skill")
	var maxed := fx.skill(&"t_maxed")
	maxed.max_level = 2
	c.skills.learned[maxed.id] = 2
	check_ne(c.skills.learn_problem(maxed), "", "at max level")
	check_eq(c.essence, 10000, "nothing spent")

func test_learn_from_earlier_job_in_line() -> void:
	fx.job(&"t_job")
	var c := fx.character(fx.job(&"t_second", &"t_family", &"t_job"))
	c.essence = c.skills.price()
	check_eq(c.skills.learn(fx.skill(&"t_old", SkillDef.Kind.ATTACK, &"t_job")), "", "earlier job's skill")

func test_learn_needs_required_skill_level() -> void:
	var c := fx.character()
	c.essence = 10000
	var base_skill := fx.skill(&"t_base")
	var next := fx.skill(&"t_next")
	next.requires = &"t_base"
	next.requires_level = 3
	check_ne(c.skills.learn_problem(next), "", "base not learned")
	c.skills.learned[base_skill.id] = 2
	check_ne(c.skills.learn_problem(next), "", "base too low")
	c.skills.learned[base_skill.id] = 3
	check_eq(c.skills.learn_problem(next), "", "base high enough")

func test_new_active_skill_goes_on_first_free_quickslot() -> void:
	var c := fx.character()
	c.essence = 10000
	c.set_quickslot(0, &"item", &"t_potion")
	var s := fx.skill()
	c.skills.learn(s)
	check_eq(c.quickslots[1], [&"skill", &"t_skill"], "first free slot")
	c.skills.learn(s)
	check_eq(c.quickslots.count([&"skill", &"t_skill"]), 1, "not added twice")

func test_passive_skill_not_put_on_quickslot() -> void:
	var c := fx.character()
	c.essence = c.skills.price()
	c.skills.learn(fx.skill(&"t_passive", SkillDef.Kind.PASSIVE))
	check_eq(c.quickslots.count([]), Character.QUICKSLOTS, "all still empty")

func test_learn_with_full_quickslots_still_learns() -> void:
	var c := fx.character()
	c.essence = c.skills.price()
	for i in Character.QUICKSLOTS:
		c.set_quickslot(i, &"item", StringName("t_i%d" % i))
	check_eq(c.skills.learn(fx.skill()), "", "learned")
	check_eq(c.skills.learned[&"t_skill"], 1, "known")

func test_passive_adds_stats_and_regen() -> void:
	var c := fx.character(null, {"strength": 10})
	var p := fx.skill(&"t_passive", SkillDef.Kind.PASSIVE)
	p.stats = UnitHelpers.stats({"strength": 2})
	p.stats_per_level = UnitHelpers.stats({"strength": 1})
	p.regen_hp = 5
	p.regen_hp_per_level = 2
	p.regen_mp = 1
	c.essence = 10000
	c.skills.learn(p)
	c.skills.learn(p)
	c.skills.learn(p)
	check_eq(c.stats.strength, 10 + 2 + 2, "passive level 3: +4 STR")
	check_eq(c.skills.regen_bonus(), Vector2i(9, 1), "regen at level 3")

func test_use_problem_rules() -> void:
	var c := fx.character()
	var s := fx.skill()
	s.mp_cost = 10
	check_ne(c.skills.use_problem(null), "", "null")
	check_ne(c.skills.use_problem(s), "", "unlearned")
	c.skills.learned[s.id] = 1
	check_eq(c.skills.use_problem(s), "", "usable")
	c.mp = 9
	check_ne(c.skills.use_problem(s), "", "not enough MP")
	c.mp = 10
	s.weapons = [&"bow"]
	check_ne(c.skills.use_problem(s), "", "no weapon")
	var sword := fx.equip(&"t_sword")
	sword.weapon_kind = &"sword"
	c.equipment.put(&"weapon", ItemStack.exact(sword))
	check_ne(c.skills.use_problem(s), "", "wrong weapon")
	sword.weapon_kind = &"bow"
	check_eq(c.skills.use_problem(s), "", "right weapon")
	var p := fx.skill(&"t_passive", SkillDef.Kind.PASSIVE)
	c.skills.learned[p.id] = 1
	check_ne(c.skills.use_problem(p), "", "passives can't be used")

func test_basic_attack_follows_weapon() -> void:
	var c := fx.character()
	check_eq(c.skills.basic_attack().id, Character.BASIC_ATTACK, "plain swing")
	var shot := fx.skill(&"t_shot")
	shot.innate = true
	var bow := fx.equip(&"t_bow")
	bow.basic_attack = shot
	c.equipment.put(&"weapon", ItemStack.exact(bow))
	check(c.skills.basic_attack() == shot, "bow's own shot")
	check_eq(c.skills.use_problem(shot), "", "can shoot")
	check_ne(c.skills.use_problem(Content.skill(Character.BASIC_ATTACK)), "", "plain swing not with a bow")

# ---------- buffs ----------

func _buff(seconds := 2.0) -> SkillDef:
	var b := fx.skill(&"t_buff", SkillDef.Kind.BUFF)
	b.stats = UnitHelpers.stats({"attack": 5, "speed": 10})
	b.stats_per_level = UnitHelpers.stats({"attack": 1})
	b.duration = seconds
	b.duration_per_level = 1.0
	return b

func test_buff_adds_stats_and_duration() -> void:
	var c := fx.character()
	var b := _buff(2.0)
	c.skills.learned[b.id] = 3
	c.skills.add_buff(b)
	check_eq(c.skills.buffs[b.id], [3, 240], "level 3 lasts 4 s = 240 ticks")
	check_eq(c.stats.attack, 7, "5 + 2 attack")
	check_eq(c.stats.speed, 10, "speed")

func test_tick_buffs_counts_down_then_expires() -> void:
	var c := fx.character()
	var b := _buff(1.0)
	c.skills.learned[b.id] = 1
	c.skills.add_buff(b)
	check_eq(c.skills.tick_buffs(59).size(), 0, "not yet")
	check_eq(c.skills.buffs[b.id][1], 1, "one tick left")
	check_eq(c.stats.attack, 5, "still on")
	var ended := c.skills.tick_buffs()
	check_eq(ended.size(), 1, "ended")
	check(ended[0] == b, "the buff skill returned")
	check(not c.skills.buffs.has(b.id), "removed")
	check_eq(c.stats.attack, 0, "stats gone")
	check_eq(c.skills.tick_buffs(100).size(), 0, "nothing more ends")

func test_big_tick_ends_buff_at_once() -> void:
	var c := fx.character()
	var b := _buff(1.0)
	c.skills.learned[b.id] = 1
	c.skills.add_buff(b)
	check_eq(c.skills.tick_buffs(10000).size(), 1, "overshoot ends it")

func test_recasting_refreshes_duration() -> void:
	var c := fx.character()
	var b := _buff(1.0)
	c.skills.learned[b.id] = 1
	c.skills.add_buff(b)
	c.skills.tick_buffs(50)
	c.skills.add_buff(b)
	check_eq(c.skills.buffs[b.id][1], 60, "back to full")
	check_eq(c.stats.attack, 5, "not stacked")

func test_buffs_expire_separately() -> void:
	var c := fx.character()
	var a := _buff(1.0)
	var b := fx.skill(&"t_buff2", SkillDef.Kind.BUFF)
	b.stats = UnitHelpers.stats({"defense": 3})
	b.duration = 2.0
	c.skills.learned[a.id] = 1
	c.skills.learned[b.id] = 1
	c.skills.add_buff(a)
	c.skills.add_buff(b)
	check_eq(c.skills.tick_buffs(60).size(), 1, "short one ends")
	check_eq(c.stats.defense, 3, "long one still on")
	check_eq(c.skills.tick_buffs(60).size(), 1, "long one ends")
	check_eq(c.stats.defense, 0, "both gone")

func test_buff_of_unknown_skill_expires_silently() -> void:
	var c := fx.character()
	c.skills.buffs[&"t_gone"] = [1, 5]
	check_eq(c.skills.tick_buffs(5).size(), 0, "nothing to report")
	check(c.skills.buffs.is_empty(), "but it's removed")

func test_skill_def_level_math() -> void:
	var s := fx.skill()
	s.mp_cost = 4
	s.mp_cost_per_level = 0.3
	s.damage_multiplier = 1.6
	s.damage_per_level = 0.08
	check_eq(s.mp_at(1), 4, "MP level 1")
	check_eq(s.mp_at(11), 7, "MP level 11")
	check_near(s.damage_at(1), 1.6, "damage level 1")
	check_near(s.damage_at(11), 2.4, "damage level 11")
	check_near(s.damage_at(0), 1.6, "level 0 treated as 1")
	check_eq(s.regen_hp_at(0), 0, "no regen unlearned")

func test_skill_def_regen_per_level() -> void:
	var s := fx.skill(&"t_regen", SkillDef.Kind.PASSIVE)
	s.regen_hp = 5
	s.regen_hp_per_level = 2
	s.regen_mp = 3
	s.regen_mp_per_level = 1
	check_eq(s.regen_hp_at(1), 5, "HP level 1")
	check_eq(s.regen_hp_at(4), 11, "HP level 4")
	check_eq(s.regen_mp_at(0), 0, "no MP regen unlearned")
	check_eq(s.regen_mp_at(1), 3, "MP level 1")
	check_eq(s.regen_mp_at(10), 12, "MP level 10")

func test_skill_flash_color_defaults_until_set() -> void:
	var s := fx.skill()
	check_eq(s.flash_color(), SkillDef.DEFAULT_FLASH, "no colour set: the default flash")
	s.flash = Color(0.4, 0.6, 1.0)
	check_eq(s.flash_color(), Color(0.4, 0.6, 1.0), "its own colour once set")
	s.flash = Color(0.4, 0.6, 1.0, 0.0)
	check_eq(s.flash_color(), SkillDef.DEFAULT_FLASH, "a see-through colour counts as unset")

func test_skill_describe_level_lines() -> void:
	var s := fx.skill()
	s.mp_cost = 6
	s.damage_multiplier = 1.5
	s.hits = 2
	s.max_targets = 3
	check_eq(Array(s.describe_level(0)), [], "nothing at level 0")
	check_eq(Array(s.describe_level(1)), ["MP cost: 6", "Damage: 150% x2 hits, up to 3 monsters"], "an attack")
	s.magic = true
	check_eq(s.describe_level(1)[1], "Magic: 150% x2 hits, up to 3 monsters", "a spell says Magic")

func test_skill_describe_level_buff_and_passive() -> void:
	var buff := fx.skill(&"t_buff", SkillDef.Kind.BUFF)
	buff.stats = UnitHelpers.stats({"attack": 5})
	buff.duration = 30.0
	check_eq(Array(buff.describe_level(1)), ["Weapon Attack +5", "Lasts 30 seconds"], "a free buff")
	var passive := fx.skill(&"t_passive", SkillDef.Kind.PASSIVE)
	passive.mp_cost = 9
	passive.regen_mp = 4
	check_eq(Array(passive.describe_level(1)), ["MP recovery +4"], "a passive shows no MP cost")

# ---------- quickslots ----------

func test_quickslots_set_swap_and_clear() -> void:
	var c := fx.character()
	check_eq(c.quickslots.size(), Character.QUICKSLOTS, "eight slots")
	c.set_quickslot(0, &"skill", &"t_a")
	c.set_quickslot(1, &"item", &"t_b")
	c.set_quickslot(1, &"skill", &"t_a")
	check_eq(c.quickslots[1], [&"skill", &"t_a"], "moved")
	check_eq(c.quickslots[0], [&"item", &"t_b"], "swapped back")
	c.set_quickslot(0, &"", &"")
	check_eq(c.quickslots[0], [], "cleared")
	c.set_quickslot(-1, &"item", &"t_x")
	c.set_quickslot(Character.QUICKSLOTS, &"item", &"t_x")
	check_eq(c.quickslots.count([&"item", &"t_x"]), 0, "out of range ignored")

func test_setting_same_slot_again_is_stable() -> void:
	var c := fx.character()
	c.set_quickslot(3, &"skill", &"t_a")
	c.set_quickslot(3, &"skill", &"t_a")
	check_eq(c.quickslots[3], [&"skill", &"t_a"], "still there")
	check_eq(c.quickslots.count([]), Character.QUICKSLOTS - 1, "only one slot used")

# ---------- storage ----------

func test_store_charges_fee_and_moves_stack() -> void:
	var c := fx.character()
	var x := fx.etc()
	c.inventory.add(x, 7)
	c.shards = Character.STORE_FEE + 5
	check_eq(c.store(ItemDef.Tab.ETC, 0), "", "stored")
	check_eq(c.shards, 5, "fee paid")
	check_eq(c.inventory.count_of(x), 0, "left the bag")
	check_eq(c.storage.count_of(x), 7, "in storage")
	check_eq(c.retrieve(ItemDef.Tab.ETC, 0), "", "retrieved free")
	check_eq(c.inventory.count_of(x), 7, "back")
	check_eq(c.shards, 5, "no fee to take out")

func test_store_refusals() -> void:
	var c := fx.character()
	var q := fx.etc(&"t_quest_item")
	q.quest_item = true
	c.inventory.add(q, 1)
	c.inventory.add(fx.use(), 1)
	c.shards = 1000
	check_ne(c.store(ItemDef.Tab.ETC, 0), "", "quest items can't be stored")
	c.shards = Character.STORE_FEE - 1
	check_ne(c.store(ItemDef.Tab.USE, 0), "", "can't pay")
	check_eq(c.shards, Character.STORE_FEE - 1, "nothing charged")
	check_eq(c.store(ItemDef.Tab.USE, 5), "", "empty slot is a no-op")
	c.shards = 1000
	c.storage.add(fx.use(&"t_other", 1), Inventory.SLOTS)
	check_ne(c.store(ItemDef.Tab.USE, 0), "", "storage full")
	check_eq(c.shards, 1000, "nothing charged")

func test_retrieve_needs_room() -> void:
	var c := fx.character()
	var x := fx.etc(&"t_etc", 1)
	c.storage.add(x, 1)
	c.inventory.add(fx.etc(&"t_other", 1), Inventory.SLOTS)
	check_ne(c.retrieve(ItemDef.Tab.ETC, 0), "", "bag full")
	check_eq(c.storage.count_of(x), 1, "still stored")

# ---------- job advancement ----------

func _advance_setup() -> Array:
	var first := fx.job(&"t_job")
	var next := fx.job(&"t_next", &"t_warrior", &"t_job")
	next.hp_growth = 20
	var c := fx.character(first, {"strength": 35})
	return [c, next]

func test_advance_needs_no_stats() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	c.base.strength = 0
	check_eq(c.advance_problem(next), "", "no stats asked")

func test_advance_refuses_the_job_you_are() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	check_eq(c.advance_problem(c.job), "You're already a T Job.", "a Beginner")
	next.display_name = "Archer"
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.advance_problem(next), "You're already an Archer.", "an before a vowel")
	check_eq(c.advance(next), "You're already an Archer.", "advance refused")

func test_advance_only_where_the_job_opens() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var first := c.job
	fx.job(&"t_other", &"t_mage", &"t_job")
	var blend := fx.job(&"t_blend", &"t_blends", &"t_next")
	blend.partner = &"t_other"
	check(not c.can_become(blend), "a Beginner can't skip to a blend")
	check_eq(c.advance(blend), "A T Job can't become a T Blend.", "advance refused")
	check_eq(c.job.id, &"t_job", "job unchanged")
	check(c.can_become(next), "a first job is open")
	check_eq(c.advance(next), "", "advanced")
	check(c.can_become(blend), "a parent can become the blend")
	check(not c.can_become(first), "nobody goes back to being a Beginner")

func test_advance_changes_job_gives_gifts_and_refills() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var sword := fx.equip(&"t_gift_sword", EquipDef.Slot.WEAPON, {"attack": 17}, 5)
	var potion := fx.use(&"t_potion")
	next.advance_gifts = [UnitHelpers.drop(sword), UnitHelpers.drop(potion, 20)]
	c.health.damage(50)
	c.essence = 40
	c.level = 8
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.job.id, &"t_next", "new job")
	# level 8 and 35 STR points bought
	check_eq(c.max_hp(), 50 + 8 * 20 + 35, "new job's HP growth, plus STR")
	check_eq(c.essence, 40, "advancing costs and gives no essence")
	check_eq(c.health.hp, c.max_hp(), "refilled")
	check_eq(c.gear.weapon(), sword, "the gift weapon is worn")
	check_eq(c.equipment.at(&"weapon").stats.attack, 17, "gift gear unrolled")
	check_eq(c.inventory.count_of(potion), 20, "potions")
	check_eq(Array(c.job_line()), [&"t_next", &"t_job"], "line")

func test_advance_keeps_skills_and_their_price() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var jab := fx.skill(&"t_jab")
	var cut := fx.skill(&"t_cut", SkillDef.Kind.ATTACK, &"t_next")
	c.essence = 17
	c.skills.learn(jab)
	check_ne(c.skills.learn_problem(cut), "", "not before advancing")
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.skills.level(jab), 1, "the old job's skill is kept")
	check_eq(c.skills.price(), 31, "the next level costs the same as before advancing")
	check_eq(c.skills.learn_problem(cut), "You need 31 Dawn Essence for that.", "the new job's skills are open, for essence")
	c.essence = 31
	check_eq(c.skills.learn(cut), "", "learned")

func test_advance_needs_room_for_gifts() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	next.advance_gifts = [UnitHelpers.drop(fx.equip(&"t_gift"))]
	c.inventory.add(fx.equip(&"t_junk"), Inventory.SLOTS)
	check_ne(c.advance(next), "", "no room")
	check_eq(c.job.id, &"t_job", "not advanced")

func test_advance_swaps_a_beginner_weapon_for_the_gift() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var stick := fx.equip(&"t_stick")
	var gift := fx.equip(&"t_gift_blade")
	gift.jobs = [&"t_warrior"]
	c.equipment.put(&"weapon", ItemStack.exact(stick))
	next.advance_gifts = [UnitHelpers.drop(fx.use(&"t_potion"), 5), UnitHelpers.drop(gift)]
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.gear.weapon(), gift, "the first weapon gift is worn, even after other gifts")
	check_eq(c.inventory.count_of(stick), 1, "the old weapon is in the bag")

func test_advance_keeps_a_weapon_of_the_new_line_on() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var found := fx.equip(&"t_found_blade")
	found.jobs = [&"t_warrior"]
	var gift := fx.equip(&"t_gift_blade")
	c.equipment.put(&"weapon", ItemStack.exact(found))
	next.advance_gifts = [UnitHelpers.drop(gift)]
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.gear.weapon(), found, "a weapon made for the job stays on")
	check_eq(c.inventory.count_of(gift), 1, "the gift goes to the bag")

func test_advance_leaves_a_gift_weapon_it_cant_wear_in_the_bag() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var heavy := fx.equip(&"t_heavy")
	heavy.required_strength = 50
	next.advance_gifts = [UnitHelpers.drop(heavy)]
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.gear.weapon(), null, "too heavy to wear")
	check_eq(c.inventory.count_of(heavy), 1, "in the bag")

func test_line_runs_back_through_every_parent() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	fx.job(&"t_other", &"t_mage", &"t_job")
	var blend := fx.job(&"t_blend", &"t_blends", &"t_next")
	blend.partner = &"t_other"
	check_eq(c.job.line(), [&"t_job"] as Array[StringName], "a Beginner")
	check_eq(next.line(), [&"t_next", &"t_job"] as Array[StringName], "a first job and the Beginner")
	check_eq(blend.line(), [&"t_blend", &"t_next", &"t_other", &"t_job"] as Array[StringName], "a blend and both parents")

# ---------- switching jobs ----------

## A Warrior-like `next` (passed, with a Beginner skill and two levels of a Warrior skill
## bought, the Warrior skill on a quickslot and its buff running) and a Mage-like `other`,
## each with a Job Test and a potion gift.
func _switch_setup() -> Dictionary:
	var first := fx.job(&"t_job")
	var next := fx.job(&"t_next", &"t_warrior", &"t_job")
	var other := fx.job(&"t_other", &"t_mage", &"t_job")
	var potion := fx.use(&"t_potion")
	for j: JobDef in [next, other]:
		j.advance_quest = fx.quest(StringName("t_%s_test" % j.id))
		j.advance_gifts = [UnitHelpers.drop(potion, 20)]
	var jab := fx.skill(&"t_jab")
	var cut := fx.skill(&"t_cut", SkillDef.Kind.ATTACK, &"t_next")
	var spark := fx.skill(&"t_spark", SkillDef.Kind.ATTACK, &"t_other")
	var c := fx.character(first, {"strength": 20, "intelligence": 7})
	c.quests.done[next.advance_quest.id] = true
	check_eq(c.advance(next), "", "became the first job")
	c.essence = CharacterStats.skill_price(0) + CharacterStats.skill_price(1) + CharacterStats.skill_price(2)
	c.skills.learn(jab)
	c.skills.learn(cut)
	c.skills.learn(cut)
	c.skills.buffs[cut.id] = [2, 100]
	check_eq(c.essence, 0, "everything spent")
	return {"c": c, "first": first, "next": next, "other": other, "potion": potion, "jab": jab, "cut": cut, "spark": spark}

func test_advance_remembers_the_jobs_passed() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	check_eq(Array(c.jobs_passed), ["t_next"], "the first job is passed")
	check(c.has_passed(s["next"]), "has passed it")
	check(not c.has_passed(s["other"]), "not the other")
	check(c.can_become(s["other"]), "another first job is open")
	check(not c.can_become(s["next"]), "not the job you are")
	check(not c.can_become(s["first"]), "nor the Beginner")

func test_switching_needs_the_job_test_the_first_time() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	var other: JobDef = s["other"]
	check_eq(c.advance(other), "Pass the %s first." % other.advance_quest.title, "the Job Test first")
	check_eq(c.job, s["next"], "job unchanged")
	check_eq(c.skills.level(s["cut"]), 2, "skills kept")
	check_eq(c.essence, 0, "nothing handed back")

func test_switching_drops_the_old_jobs_skills_and_refunds_what_was_paid() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	var cut: SkillDef = s["cut"]
	var paid := int(c.skills.paid[cut.id])
	check_eq(paid, CharacterStats.skill_price(1) + CharacterStats.skill_price(2), "what the two levels cost")
	check(c.quickslot_of(&"skill", cut.id) >= 0, "on a quickslot")
	var base := c.base.to_dict()
	var str_total := c.stats.strength
	check_eq(c.skills_lost_by(s["other"]), [cut] as Array[SkillDef], "only the Warrior skill would go")
	c.quests.done[s["other"].advance_quest.id] = true
	check_eq(c.advance(s["other"]), "", "switched")
	check_eq(c.job, s["other"], "the other job")
	check_eq(c.skills.level(cut), 0, "the old job's skill is forgotten")
	check(not c.skills.paid.has(cut.id), "and what was paid for it")
	check_eq(c.essence, paid, "exactly what was paid comes back")
	check_eq(c.quickslot_of(&"skill", cut.id), -1, "its quickslot empties")
	check(not c.skills.buffs.has(cut.id), "its buff ends")
	check_eq(c.skills.level(s["jab"]), 1, "the Beginner skill stays")
	check_eq(c.base.to_dict(), base, "stats stay")
	check_eq(c.stats.strength, str_total, "and their totals")
	check_eq(c.skills.price(), CharacterStats.skill_price(1), "the next level costs as if the old skill was never bought")
	check_eq(c.inventory.count_of(s["potion"]), 40, "gifts the first time")
	check(c.has_passed(s["other"]), "now passed too")

func test_switching_back_is_free_and_gives_no_gifts_again() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	var next: JobDef = s["next"]
	var other: JobDef = s["other"]
	c.quests.done[other.advance_quest.id] = true
	check_eq(c.advance(other), "", "switched")
	c.essence += CharacterStats.skill_price(1)
	var essence := c.essence
	check_eq(c.skills.learn(s["spark"]), "", "a skill of the new job")
	c.quests.done.erase(next.advance_quest.id)
	c.quests.done.erase(other.advance_quest.id)
	var potions := c.inventory.count_of(s["potion"])
	check_eq(c.advance_problem(next), "", "a job passed before needs no Job Test")
	check_eq(c.advance(next), "", "switched back")
	check_eq(c.job, next, "the first job again")
	check_eq(c.inventory.count_of(s["potion"]), potions, "no second gifts")
	check_eq(c.skills.level(s["spark"]), 0, "the other job's skill goes")
	check_eq(c.essence, essence, "its essence comes back")
	check_eq(c.skills.level(s["cut"]), 0, "the skill dropped before stays dropped")
	check_eq(Array(c.jobs_passed), ["t_next", "t_other"], "each job listed once")
	check_eq(c.advance(other), "", "and back again, free")

func test_switching_needs_no_room_for_gifts_once_passed() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	c.quests.done[s["other"].advance_quest.id] = true
	check_eq(c.advance(s["other"]), "", "switched")
	c.inventory.add(fx.use(&"t_junk", 1), Inventory.SLOTS)
	check_eq(c.advance(s["next"]), "", "a full Use tab doesn't matter: no gifts come")

# ---------- tallies, maps, pets ----------

func test_count_tallies() -> void:
	var c := fx.character()
	c.count(Counters.DEALS)
	c.count(Counters.DEALS, 3)
	c.count(Counters.SAT, 0)
	check_eq(c.counters[Counters.DEALS], 4, "added up")
	check_eq(c.counters[Counters.SAT], 0, "zero recorded")

func test_visit_only_new_maps() -> void:
	var c := fx.character()
	check(c.visit(&"t_a"), "first time")
	check(not c.visit(&"t_a"), "second time")
	check(c.visit(&"t_b"), "another map")
	check_eq(Array(c.visited), ["t_a", "t_b"], "listed once each")

func test_pet_def_lookup() -> void:
	var c := fx.character()
	check(c.pet_def() == null, "no pet")
	var p := PetDef.new()
	p.id = &"t_pet"
	fx.register("items", p)
	c.pet = &"t_pet"
	check(c.pet_def() == p, "pet found")
	c.pet = &"t_etc"
	fx.etc()
	check(c.pet_def() == null, "not a pet")
	check_eq(p.tab(), ItemDef.Tab.SETUP, "pets in Setup")
	check_eq(p.stack_size(), 1, "pets don't stack")

func test_use_defs() -> void:
	var u := fx.use()
	u.heal_hp = 50
	u.heal_hp_percent = 10
	u.heal_mp_percent = 25
	check_eq(u.hp_for(300), 80, "50 + 10% of 300")
	check_eq(u.mp_for(30), 8, "25% of 30 rounded")

# ---------- real content ----------

func test_create_beginner_from_content() -> void:
	var c := Character.create("Hero")
	var j := Content.job(&"beginner")
	check_eq(c.name, "Hero", "name")
	check_eq(c.essence, 0, "no essence yet")
	check(c.job == j, "beginner")
	check_eq(c.base.to_dict(), j.starting_stats.to_dict(), "starting stats")
	check_eq(c.equipment.worn.size(), NewCharacter.new().starting_gear(j).size(), "starting gear and the creator's default outfit worn")
	for e in j.starting_gear:
		var worn: ItemStack = null
		for s: ItemStack in c.equipment.worn.values():
			if s.item == e:
				worn = s
		if not check(worn != null, "%s worn" % e.id):
			continue
		check_eq(worn.stats.to_dict(), e.stats.to_dict() if e.stats else {}, "%s exact stats" % e.id)
	check_eq(c.inventory.count_of(Content.item(&"red_potion")), 5, "starting potions")
	check_eq(c.quickslots[Character.QUICKSLOTS - 2], [&"item", &"red_potion"], "red potion key")
	check_eq(c.quickslots[Character.QUICKSLOTS - 1], [&"item", &"blue_potion"], "blue potion key")
	check_eq(c.health.hp, c.max_hp(), "full HP")
	check_eq(c.mp, c.max_mp(), "full MP")
	check_eq(c.map_id, Character.NEW_MAP, "starts on the tutorial beach")

func test_real_beginner_can_reach_warrior() -> void:
	var c := Character.create("Hero")
	var w := Content.job(&"warrior")
	check_eq(c.advance_problem(w), "Pass the Job Test first.", "a new Beginner needs only the Job Test")
	c.quests.done[w.advance_quest.id] = true
	check_eq(c.advance_problem(w), "", "the test is enough")
	check_eq(c.advance(w), "", "advanced")
	check_eq(c.job.id, &"warrior", "warrior")

func test_advance_refused_when_gifts_need_more_slots_than_free() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	next.advance_gifts = [UnitHelpers.drop(fx.equip(&"t_gift_a")), UnitHelpers.drop(fx.equip(&"t_gift_b"))]
	c.inventory.add(fx.equip(&"t_junk"), Inventory.SLOTS - 1)
	check_ne(c.advance(next), "", "two gear gifts, one free slot")
	check_eq(c.job.id, &"t_job", "not advanced")
