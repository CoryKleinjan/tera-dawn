extends TestCase
## CharacterStats: damage and magic ranges per job and main stat, accuracy, avoid, crit,
## Speed and Jump multipliers with their caps, and max HP / MP growth.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

func _job(primary: String, secondary: String, mastery := 0.5) -> JobDef:
	var j := fx.job()
	j.primary_stat = primary
	j.secondary_stat = secondary
	j.mastery = mastery
	return j

func test_damage_range_formula() -> void:
	# (20 × 4 + 10) × 10 / 100 × 2 = 18, lowest 18 × 0.5 = 9
	var s := UnitHelpers.stats({"strength": 20, "dexterity": 10, "attack": 10})
	check_eq(CharacterStats.damage_range(_job("strength", "dexterity"), s), Vector2i(9, 18), "range")

func test_damage_range_uses_the_jobs_own_stats() -> void:
	var s := UnitHelpers.stats({"strength": 100, "dexterity": 10, "luck": 30, "attack": 10})
	# thief-like: (30 × 4 + 10) × 10 / 100 × 2 = 26
	check_eq(CharacterStats.damage_range(_job("luck", "dexterity"), s).y, 26, "luck main")
	# warrior-like: (100 × 4 + 10) × 0.2 = 82
	check_eq(CharacterStats.damage_range(_job("strength", "dexterity"), s).y, 82, "strength main")
	# archer-like: (10 × 4 + 100) × 0.2 = 28
	check_eq(CharacterStats.damage_range(_job("dexterity", "strength"), s).y, 28, "dex main")

func test_more_main_stat_means_more_damage_than_more_secondary() -> void:
	var j := _job("strength", "dexterity")
	var base := CharacterStats.damage_range(j, UnitHelpers.stats({"strength": 20, "dexterity": 20, "attack": 20})).y
	var more_main := CharacterStats.damage_range(j, UnitHelpers.stats({"strength": 30, "dexterity": 20, "attack": 20})).y
	var more_second := CharacterStats.damage_range(j, UnitHelpers.stats({"strength": 20, "dexterity": 30, "attack": 20})).y
	check(more_main > more_second, "main stat counts four times")
	check(more_second > base, "secondary still helps")

func test_extra_attack_adds_to_weapon_attack() -> void:
	var j := _job("strength", "dexterity")
	var s := UnitHelpers.stats({"strength": 20, "dexterity": 10, "attack": 10})
	# (90) × 15 / 100 × 2 = 27
	check_eq(CharacterStats.damage_range(j, s, 5).y, 27, "ammo attack")

func test_damage_range_never_below_one() -> void:
	var j := _job("strength", "dexterity", 0.1)
	check_eq(CharacterStats.damage_range(j, StatBlock.new()), Vector2i(1, 1), "no stats, no attack")
	check_eq(CharacterStats.damage_range(j, UnitHelpers.stats({"strength": 1, "attack": 1})), Vector2i(1, 1), "tiny")

func test_mastery_sets_the_low_end() -> void:
	var s := UnitHelpers.stats({"strength": 50, "attack": 50})  # top = 200 × 50 / 100 × 2 = 200
	check_eq(CharacterStats.damage_range(_job("strength", "dexterity", 0.6), s), Vector2i(120, 200), "60%")
	check_eq(CharacterStats.damage_range(_job("strength", "dexterity", 0.95), s), Vector2i(190, 200), "95%")

func test_magic_range_formula() -> void:
	# M = 40 + 20 = 60: 60² / 120 + 60 = 90
	var s := UnitHelpers.stats({"intelligence": 40, "magic_attack": 20})
	check_eq(CharacterStats.magic_attack(s), 60, "magic attack includes INT")
	check_eq(CharacterStats.magic_range(_job("intelligence", "luck", 0.5), s), Vector2i(45, 90), "range")
	check_eq(CharacterStats.magic_range(_job("intelligence", "luck"), StatBlock.new()), Vector2i(1, 1), "floor of one")

func test_magic_range_ignores_weapon_attack() -> void:
	var j := _job("intelligence", "luck")
	var a := CharacterStats.magic_range(j, UnitHelpers.stats({"intelligence": 40}))
	var b := CharacterStats.magic_range(j, UnitHelpers.stats({"intelligence": 40, "attack": 500, "strength": 99}))
	check_eq(a, b, "only INT and Magic Attack")

func test_accuracy_and_avoid() -> void:
	var s := UnitHelpers.stats({"dexterity": 10, "luck": 4, "accuracy": 3, "avoid": 2})
	check_eq(CharacterStats.accuracy(s), 3 + 8 + 2, "accuracy = acc + 0.8 DEX + 0.5 LUK")
	check_eq(CharacterStats.avoid(s), 2 + 3 + 2, "avoid = avoid + 0.25 DEX + 0.5 LUK (rounded)")
	check_eq(CharacterStats.accuracy(StatBlock.new()), 0, "zero")

func test_crit_rate() -> void:
	check_near(CharacterStats.crit_rate(StatBlock.new()), 0.12, "base")
	check_near(CharacterStats.crit_rate(UnitHelpers.stats({"crit": 8})), 0.20, "plus 8%")

func test_speed_multiplier_and_caps() -> void:
	check_near(CharacterStats.speed_multiplier(StatBlock.new()), 1.0, "none")
	check_near(CharacterStats.speed_multiplier(UnitHelpers.stats({"speed": 20})), 1.2, "+20")
	check_near(CharacterStats.speed_multiplier(UnitHelpers.stats({"speed": 40})), 1.4, "at cap")
	check_near(CharacterStats.speed_multiplier(UnitHelpers.stats({"speed": 300})), 1.4, "capped at 140%")
	check_near(CharacterStats.speed_multiplier(UnitHelpers.stats({"speed": -90})), 0.5, "floored at 50%")

func test_jump_multiplier_and_caps() -> void:
	check_near(CharacterStats.jump_multiplier(UnitHelpers.stats({"jump": 10})), 1.1, "+10")
	check_near(CharacterStats.jump_multiplier(UnitHelpers.stats({"jump": 100})), 1.23, "capped at 123%")
	check_near(CharacterStats.jump_multiplier(UnitHelpers.stats({"jump": -100})), 0.5, "floored at 50%")

func test_max_hp_and_mp_grow_with_level_and_gear() -> void:
	var j := fx.job()  # 50 + 10/level HP, 20 + 5/level MP
	check_eq(CharacterStats.max_hp(j, 1, StatBlock.new()), 60, "HP level 1")
	check_eq(CharacterStats.max_hp(j, 10, UnitHelpers.stats({"max_hp": 25})), 175, "HP level 10 with gear")
	check_eq(CharacterStats.max_mp(j, 1, StatBlock.new()), 25, "MP level 1")
	check_eq(CharacterStats.max_mp(j, 30, UnitHelpers.stats({"max_mp": 5})), 175, "MP level 30 with gear")

func test_real_jobs_use_their_listed_main_stat() -> void:
	var s := UnitHelpers.stats({"strength": 10, "dexterity": 10, "intelligence": 10, "luck": 10, "attack": 10})
	for id in Content.jobs:
		var j: JobDef = Content.jobs[id]
		var bumped := s.copy()
		bumped.set(StringName(j.primary_stat), 60)
		check(CharacterStats.damage_range(j, bumped).y > CharacterStats.damage_range(j, s).y, "%s: main stat raises damage" % id)

func test_stat_block_rolled_and_format() -> void:
	check_eq(StatBlock.format(&"attack", 3), "+3", "plain")
	check_eq(StatBlock.format(&"defense", -2), "-2", "negative")
	check_eq(StatBlock.format(&"speed", 5), "+5%", "percent")
	var s := UnitHelpers.stats({"attack": 5})
	check_eq(s.rolled(0).to_dict(), {"attack": 5}, "no spread")
	check_eq(StatBlock.from_dict(s.to_dict()).attack, 5, "round trip")
	check_eq(StatBlock.from_dict({"bogus": 3}).nonzero().size(), 0, "unknown keys ignored")
	var p := s.plus(UnitHelpers.stats({"attack": 2, "luck": 1}))
	check_eq(p.to_dict(), {"attack": 7, "luck": 1}, "plus")
	check_eq(s.attack, 5, "plus doesn't change the original")
	s.add(null)
	check_eq(s.attack, 5, "adding null is a no-op")
