extends TestCase
## CharacterStats: damage and magic ranges per job and main stat, accuracy, avoid, crit,
## Speed and Jump multipliers with their caps, and max HP / MP growth.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

func _job(primary: String, mastery := 0.5) -> JobDef:
	var j := fx.job()
	j.primary_stat = primary
	j.mastery = mastery
	return j

func test_damage_range_formula() -> void:
	# 20 × 3.6 × 10 / 100 × 2 = 14.4 -> 14, lowest 14 × 0.5 = 7
	var s := UnitHelpers.stats({"strength": 20, "dexterity": 10, "attack": 10})
	check_eq(CharacterStats.damage_range(_job("strength"), s), Vector2i(7, 14), "range")

func test_damage_range_uses_only_the_jobs_own_stat() -> void:
	var s := UnitHelpers.stats({"strength": 100, "dexterity": 10, "luck": 30, "charisma": 50, "attack": 10})
	# 30 × 3.6 × 10 / 100 × 2 = 21.6 -> 22
	check_eq(CharacterStats.damage_range(_job("luck"), s).y, 22, "luck")
	check_eq(CharacterStats.damage_range(_job("strength"), s).y, 72, "strength")
	check_eq(CharacterStats.damage_range(_job("dexterity"), s).y, 7, "dex")
	check_eq(CharacterStats.damage_range(_job("charisma"), s).y, 36, "charisma")
	var more_other := UnitHelpers.stats({"strength": 100, "dexterity": 90, "attack": 10})
	check_eq(CharacterStats.damage_range(_job("strength"), more_other).y, 72, "no other stat adds to it")

func test_a_job_that_uses_its_best_stat_hits_with_the_highest() -> void:
	var j := _job("strength")
	j.uses_best_stat = true
	var s := UnitHelpers.stats({"strength": 10, "dexterity": 15, "intelligence": 40, "attack": 10})
	check_eq(j.damage_stat(s), &"intelligence", "INT is highest")
	check_eq(CharacterStats.damage_range(j, s).y, 29, "INT main: 40 × 3.6 × 0.2")
	s.intelligence = 4
	check_eq(j.damage_stat(s), &"dexterity", "DEX highest")
	s.strength = 15
	check_eq(j.damage_stat(s), &"strength", "a tie goes to the primary stat")
	j.uses_best_stat = false
	s.luck = 99
	check_eq(j.damage_stat(s), &"strength", "other jobs keep their own stat")

func test_what_each_stat_gives_as_it_grows() -> void:
	var j := _job("strength")
	var none := StatBlock.new()
	var s := UnitHelpers.stats({"strength": 50, "intelligence": 40, "dexterity": 30, "luck": 20, "charisma": 100})
	check_eq(CharacterStats.max_hp(j, 10, s) - CharacterStats.max_hp(j, 10, none), 50, "STR adds Max HP")
	check_eq(CharacterStats.max_mp(j, 10, s) - CharacterStats.max_mp(j, 10, none), 40, "INT adds Max MP")
	check_eq(CharacterStats.accuracy(s), 24, "DEX adds Accuracy")
	check_eq(CharacterStats.avoid(s), 15, "LUK adds Avoidability")
	check(is_equal_approx(CharacterStats.shop_discount(s), 0.1), "CHA takes 10% off at 100")
	check(is_equal_approx(CharacterStats.shop_discount(UnitHelpers.stats({"charisma": 900})), CharacterStats.MAX_DISCOUNT), "the discount is capped")
	check(is_equal_approx(CharacterStats.shard_bonus(s), 1.2), "CHA finds 20% more Dawnshards at 100")

func test_damage_range_never_below_one() -> void:
	var j := _job("strength", 0.1)
	check_eq(CharacterStats.damage_range(j, StatBlock.new()), Vector2i(1, 1), "no stats, no attack")
	check_eq(CharacterStats.damage_range(j, UnitHelpers.stats({"strength": 1, "attack": 1})), Vector2i(1, 1), "tiny")

func test_mastery_sets_the_low_end() -> void:
	var s := UnitHelpers.stats({"strength": 50, "attack": 50})  # top = 50 × 3.6 × 50 / 100 × 2 = 180
	check_eq(CharacterStats.damage_range(_job("strength", 0.6), s), Vector2i(108, 180), "60%")
	check_eq(CharacterStats.damage_range(_job("strength", 0.95), s), Vector2i(171, 180), "95%")

func test_magic_range_formula() -> void:
	# M = 40 + 20 = 60: 60² / 120 + 60 = 90
	var s := UnitHelpers.stats({"intelligence": 40, "magic_attack": 20})
	check_eq(CharacterStats.magic_attack(s), 60, "magic attack includes INT")
	check_eq(CharacterStats.magic_range(_job("intelligence", 0.5), s), Vector2i(45, 90), "range")
	check_eq(CharacterStats.magic_range(_job("intelligence"), StatBlock.new()), Vector2i(1, 1), "floor of one")

func test_magic_range_ignores_weapon_attack() -> void:
	var j := _job("intelligence")
	var a := CharacterStats.magic_range(j, UnitHelpers.stats({"intelligence": 40}))
	var b := CharacterStats.magic_range(j, UnitHelpers.stats({"intelligence": 40, "attack": 500, "strength": 99}))
	check_eq(a, b, "only INT and Magic Attack")

func test_accuracy_and_avoid() -> void:
	var s := UnitHelpers.stats({"dexterity": 10, "luck": 4, "accuracy": 3, "avoid": 2})
	check_eq(CharacterStats.accuracy(s), 3 + 8, "accuracy = acc + 0.8 DEX")
	check_eq(CharacterStats.avoid(s), 2 + 3, "avoid = avoid + 0.75 LUK")
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

func test_charisma_talks_shop_prices_down() -> void:
	var line := ShopEntry.new()
	line.item = fx.use()
	line.price = 1000
	var c := fx.character(null, {"charisma": 50})
	check_eq(line.cost_for(c), 950, "5% off at 50 CHA")
	c.base.charisma = 0
	c.recalc()
	check_eq(line.cost_for(c), 1000, "full price with none")
