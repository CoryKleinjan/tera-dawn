extends TestCase
## Character rules: EXP and levelling up, HP and MP, recalc, Ability Points, skills and
## Skill Points, buffs and their expiry, quickslots, storage, job advancement,
## tallies, visited maps, pets, and a fresh character from real content.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

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
	fx.skill(&"t_cut")
	check_eq(c.gain_xp(27 + 220 + 742 + 10), 3, "three levels")
	check_eq(c.level, 4, "level 4")
	check_eq(c.xp, 10, "leftover")
	check_eq(c.ap.points, 15, "5 AP a level")
	check_eq(c.skills.points, 9, "3 SP a level")

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
	check_eq(c.ap.points, 15, "AP for the three levels only")

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
	check_eq(c.damage_range(), Vector2i(9, 18), "range")

# ---------- Ability Points ----------

func test_add_ap_raises_base_stat() -> void:
	var c := fx.character(null, {"strength": 4})
	c.ap.points = 2
	check(c.ap.spend(&"strength"), "spent")
	check_eq(c.base.strength, 5, "base")
	check_eq(c.stats.strength, 5, "total recalculated")
	check_eq(c.ap.points, 1, "one left")
	for s in StatBlock.BASE:
		c.ap.points = 1
		check(c.ap.spend(s), "%s allowed" % s)

func test_add_ap_refuses_without_points_or_bad_stat() -> void:
	var c := fx.character()
	c.ap.points = 0
	check(not c.ap.spend(&"strength"), "no points")
	c.ap.points = 3
	check(not c.ap.spend(&"attack"), "attack isn't a base stat")
	check(not c.ap.spend(&"max_hp"), "max HP isn't either")
	check(not c.ap.spend(&"nonsense"), "unknown stat")
	check_eq(c.ap.points, 3, "points kept")
	check_eq(c.base.attack, 0, "nothing raised")

func test_add_ap_spends_several_but_never_more_than_left() -> void:
	var c := fx.character(null, {"luck": 4})
	c.ap.points = 5
	check(c.ap.spend(&"luck", 3), "spent three")
	check_eq(c.base.luck, 7, "LUK")
	check_eq(c.ap.points, 2, "two left")
	check(c.ap.spend(&"luck", 10), "spent the rest")
	check_eq(c.base.luck, 9, "only the two that were left")
	check_eq(c.ap.points, 0, "none left")
	c.ap.points = 3
	check(not c.ap.spend(&"luck", 0), "zero points")
	check(not c.ap.spend(&"luck", -2), "negative points")
	check_eq(c.ap.points, 3, "points kept")

func test_auto_ap_fills_the_primary_stat() -> void:
	var c := fx.character(null, {"strength": 10, "dexterity": 5})
	c.ap.points = 7
	check_eq(c.ap.auto_plan(), {&"strength": 7}, "all in STR with no gear asking for DEX")
	c.ap.points = 0
	check_eq(c.ap.auto_plan(), {}, "nothing to spend")

func test_auto_ap_keeps_enough_secondary_for_gear() -> void:
	var c := fx.character(null, {"strength": 10, "dexterity": 5})
	c.level = 10
	var worn := fx.equip(&"t_worn", EquipDef.Slot.WEAPON)
	worn.required_dexterity = 7
	c.equipment.put(&"weapon", ItemStack.exact(worn))
	var bagged := fx.equip(&"t_bagged", EquipDef.Slot.TOP)
	bagged.required_dexterity = 9
	c.inventory.add_stack(ItemStack.exact(bagged))
	var later := fx.equip(&"t_later", EquipDef.Slot.SHOES)
	later.required_dexterity = 30
	later.required_level = 20
	c.inventory.add_stack(ItemStack.exact(later))
	c.recalc()
	c.ap.points = 10
	check_eq(c.ap.auto_plan(), {&"dexterity": 4, &"strength": 6}, "DEX up to the bag's top (not gear for later levels), the rest in STR")
	c.ap.points = 3
	check_eq(c.ap.auto_plan(), {&"dexterity": 3}, "gear first when points are short")

func test_stats_short_of_a_job() -> void:
	var beginner := fx.job(&"t_beginner")
	var thief := fx.job(&"t_thief", &"t_thieves", &"t_beginner")
	thief.advance_requirements = UnitHelpers.stats({"luck": 25, "dexterity": 10})
	var c := fx.character(beginner, {"luck": 4, "dexterity": 12})
	check_eq(c.stats_short_of(thief), {&"luck": 25}, "only LUK is short")
	c.base.luck = 25
	check_eq(c.stats_short_of(thief), {}, "ready")

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

func test_learn_spends_sp_and_raises_level() -> void:
	var c := fx.character()
	var s := fx.skill()
	c.skills.points = 2
	check_eq(c.skills.learn(s), "", "learned")
	check_eq(c.skills.learn(s), "", "again")
	check_eq(c.skills.level(s), 2, "level 2")
	check_eq(c.skills.points, 0, "SP spent")
	check_ne(c.skills.learn(s), "", "out of SP")
	check_eq(c.skills.level(s), 2, "unchanged")

func test_learn_refused_cases() -> void:
	var c := fx.character()
	c.skills.points = 10
	var innate := fx.skill(&"t_innate")
	innate.innate = true
	check_ne(c.skills.learn_problem(innate), "", "innate")
	var other := fx.skill(&"t_other", SkillDef.Kind.ATTACK, &"t_someone_else")
	check_ne(c.skills.learn_problem(other), "", "another job's skill")
	var maxed := fx.skill(&"t_maxed")
	maxed.max_level = 2
	c.skills.learned[maxed.id] = 2
	check_ne(c.skills.learn_problem(maxed), "", "at max level")
	check_eq(c.skills.points, 10, "nothing spent")

func test_learn_from_earlier_job_in_line() -> void:
	fx.job(&"t_job")
	var c := fx.character(fx.job(&"t_second", &"t_family", &"t_job"))
	c.skills.points = 1
	check_eq(c.skills.learn(fx.skill(&"t_old", SkillDef.Kind.ATTACK, &"t_job")), "", "earlier job's skill")

func test_learn_needs_required_skill_level() -> void:
	var c := fx.character()
	c.skills.points = 10
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
	c.skills.points = 5
	c.set_quickslot(0, &"item", &"t_potion")
	var s := fx.skill()
	c.skills.learn(s)
	check_eq(c.quickslots[1], [&"skill", &"t_skill"], "first free slot")
	c.skills.learn(s)
	check_eq(c.quickslots.count([&"skill", &"t_skill"]), 1, "not added twice")

func test_passive_skill_not_put_on_quickslot() -> void:
	var c := fx.character()
	c.skills.points = 1
	c.skills.learn(fx.skill(&"t_passive", SkillDef.Kind.PASSIVE))
	check_eq(c.quickslots.count([]), Character.QUICKSLOTS, "all still empty")

func test_learn_with_full_quickslots_still_learns() -> void:
	var c := fx.character()
	c.skills.points = 1
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
	c.skills.points = 3
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
	next.advance_level = 10
	next.advance_requirements = UnitHelpers.stats({"strength": 35})
	next.hp_per_level = 20
	var c := fx.character(first, {"strength": 35})
	c.level = 10
	return [c, next]

func test_advance_requirements() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	check_eq(c.advance_problem(next), "", "meets everything")
	c.level = 9
	check_ne(c.advance_problem(next), "", "level too low")
	c.level = 10
	c.base.strength = 34
	check_ne(c.advance_problem(next), "", "STR too low")
	c.base.strength = 35
	c.equipment.put(&"hat", ItemStack.exact(fx.equip(&"t_hat", EquipDef.Slot.HAT, {"strength": 50})))
	c.base.strength = 20
	check_ne(c.advance_problem(next), "", "gear STR doesn't count")

func test_advance_only_from_previous_job() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var later := fx.job(&"t_later", &"t_warrior", &"t_next")
	check_ne(c.advance_problem(later), "", "can't skip a job")
	check_ne(c.advance(later), "", "advance refused")
	check_eq(c.job.id, &"t_job", "job unchanged")

func test_advance_changes_job_gives_gifts_and_refills() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var sword := fx.equip(&"t_gift_sword", EquipDef.Slot.WEAPON, {"attack": 17}, 5)
	var potion := fx.use(&"t_potion")
	next.advance_gifts = [UnitHelpers.drop(sword), UnitHelpers.drop(potion, 20)]
	c.health.damage(50)
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.job.id, &"t_next", "new job")
	check_eq(c.max_hp(), 50 + 10 * 20, "new job's HP growth")
	check_eq(c.health.hp, c.max_hp(), "refilled")
	check_eq(c.gear.weapon(), sword, "the gift weapon is worn")
	check_eq(c.equipment.at(&"weapon").stats.attack, 17, "gift gear unrolled")
	check_eq(c.inventory.count_of(potion), 20, "potions")
	check_eq(Array(c.job_line()), [&"t_next", &"t_job"], "line")

func test_advance_gives_sp() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	next.advance_sp = 2
	fx.skill(&"t_cut", SkillDef.Kind.ATTACK, &"t_next")
	c.skills.points = 0
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.skills.points, 2, "SP to learn a first skill")

func test_late_advance_pays_the_missed_sp() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	next.advance_sp = 1
	fx.skill(&"t_cut", SkillDef.Kind.ATTACK, &"t_next").max_level = 20
	c.level = 13
	c.skills.points = 0
	check_eq(c.advance(next), "", "advanced at 13")
	check_eq(c.skills.points, 1 + 3 * 3, "as many SP as advancing at 10 and levelling to 13")

func test_sp_never_above_what_skills_can_take() -> void:
	var c := fx.character()
	var cut := fx.skill(&"t_cut")
	c.skills.points = 8
	c.gain_xp(27)
	check_eq(c.skills.points, 10, "levelling stops at the 10 levels the job's skills have")
	check_eq(c.skills.learn(cut), "", "learned one")
	c.gain_xp(c.xp_need())
	check_eq(c.skills.points, 9, "still no more than the levels left")
	fx.skill(&"t_other_job", SkillDef.Kind.ATTACK, &"t_elsewhere")
	c.skills.points = 50
	c.skills.keep_in_room()
	check_eq(c.skills.points, 9, "another job's skills don't count")

func test_settle_hands_back_missed_sp() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	next.advance_sp = 1
	var cut := fx.skill(&"t_cut", SkillDef.Kind.ATTACK, &"t_next")
	cut.max_level = 40
	fx.skill(&"t_jab")
	c.job = next
	c.level = 14
	c.skills.learned = {&"t_jab": 9, &"t_cut": 2}
	c.skills.points = 0
	c.skills.settle()
	# t_job Lv 1-10: 27, t_next Lv 10-14: 1 + 12; 11 spent
	check_eq(c.skills.points, 27 + 13 - 11, "earned minus spent")
	c.skills.points = 99
	c.skills.settle()
	check_eq(c.skills.points, 38 + 1, "and never more than the skills can take")

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
	heavy.required_level = 50
	next.advance_gifts = [UnitHelpers.drop(heavy)]
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.gear.weapon(), null, "too heavy to wear")
	check_eq(c.inventory.count_of(heavy), 1, "in the bag")

func test_requirement_lines() -> void:
	var setup := _advance_setup()
	var next: JobDef = setup[1]
	check_eq(Array(next.requirement_lines()), ["Level 10", "35 STR"], "lines")

## A Beginner (starting STR 12, DEX 5) who put 18 points in STR and a path asking for 30 INT.
func _reset_setup() -> Array:
	var first := fx.job(&"t_job")
	first.starting_stats = UnitHelpers.stats({"strength": 12, "dexterity": 5})
	var next := fx.job(&"t_mind", &"t_mage", &"t_job")
	next.advance_requirements = UnitHelpers.stats({"intelligence": 30})
	var c := fx.character(first, {"strength": 30, "dexterity": 5})
	c.ap.points = 2
	return [c, next]

func test_ap_reset_gives_back_every_spent_point_once() -> void:
	var setup := _reset_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	check_eq(c.ap.spent(), 18, "18 points in STR")
	check_eq(c.ap.reset(next), "", "reset")
	check_eq(c.base.strength, 12, "back to the starting STR")
	check_eq(c.base.dexterity, 5, "DEX untouched")
	check_eq(c.ap.points, 20, "18 back plus the 2 unspent")
	check_eq(c.stats.strength, 12, "totals worked out again")
	check(c.ap.reset_used, "used up")
	c.ap.spend(&"strength", 5)
	check_ne(c.ap.reset(next), "", "only once")
	check_eq(c.base.strength, 17, "the second one changes nothing")

func test_ap_reset_only_for_a_beginner_short_of_the_stats() -> void:
	var setup := _reset_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	c.base.intelligence = 30
	check_ne(c.ap.reset_problem(next), "", "already has the INT")
	c.base.intelligence = 0
	c.base.strength = 12
	check_ne(c.ap.reset_problem(next), "", "nothing spent")
	c.base.strength = 30
	check_eq(c.ap.reset_problem(next), "", "spent and short")
	c.job = next
	check_ne(c.ap.reset_problem(next), "", "not a Beginner any more")

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

func test_chair_and_use_defs() -> void:
	var chair := ChairDef.new()
	chair.max_stack = 50
	check_eq(chair.tab(), ItemDef.Tab.SETUP, "chairs in Setup")
	check_eq(chair.stack_size(), 1, "chairs don't stack")
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
	check_eq(c.level, 1, "level 1")
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
	check_ne(c.advance_problem(w), "", "level 1 can't")
	c.level = w.advance_level
	c.base.strength = w.advance_requirements.strength
	check_eq(c.advance_problem(w), "", "level and STR enough")
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
