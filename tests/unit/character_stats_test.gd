extends TestCase
## CharacterStats: power, damage and magic ranges from power, accuracy, avoid, crit,
## Speed and Jump multipliers with their caps, and max HP / MP growth.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

func _job(mastery := 0.5, base_power := 10) -> JobDef:
	var j := fx.job()
	j.mastery = mastery
	j.base_power = base_power
	return j

func test_power_grows_with_level() -> void:
	var j := _job(0.5, 12)
	check_eq(CharacterStats.power(j, 1), 12, "base power at level 1")
	check_eq(CharacterStats.power(j, 10), 12 + 9 * CharacterStats.POWER_PER_LEVEL, "five a level")
	check_eq(CharacterStats.power(j, 0), 12, "never below level 1")

func test_damage_range_formula() -> void:
	# 20 × 3.6 × 10 / 100 × 2 = 14.4 -> 14, lowest 14 × 0.5 = 7
	var s := UnitHelpers.stats({"attack": 10})
	check_eq(CharacterStats.damage_range(_job(), 20, s), Vector2i(7, 14), "range")

func test_damage_range_grows_with_power_and_attack() -> void:
	var j := _job()
	var s := UnitHelpers.stats({"attack": 10})
	check_eq(CharacterStats.damage_range(j, 30, s).y, 22, "30 power")
	check_eq(CharacterStats.damage_range(j, 100, s).y, 72, "100 power")
	check_eq(CharacterStats.damage_range(j, 100, UnitHelpers.stats({"attack": 20})).y, 144, "twice the attack")
	check_eq(CharacterStats.damage_range(j, 100, UnitHelpers.stats({"attack": 10, "defense": 90, "accuracy": 50})).y, 72, "other stats don't add to it")

func test_damage_range_never_below_one() -> void:
	var j := _job(0.1)
	check_eq(CharacterStats.damage_range(j, 0, StatBlock.new()), Vector2i(1, 1), "no power, no attack")
	check_eq(CharacterStats.damage_range(j, 1, UnitHelpers.stats({"attack": 1})), Vector2i(1, 1), "tiny")

func test_mastery_sets_the_low_end() -> void:
	var s := UnitHelpers.stats({"attack": 50})  # top = 50 × 3.6 × 50 / 100 × 2 = 180
	check_eq(CharacterStats.damage_range(_job(0.6), 50, s), Vector2i(108, 180), "60%")
	check_eq(CharacterStats.damage_range(_job(0.95), 50, s), Vector2i(171, 180), "95%")

func test_magic_range_formula() -> void:
	# M = 40 + 20 = 60: 60² / 120 + 60 = 90
	var s := UnitHelpers.stats({"magic_attack": 20})
	check_eq(CharacterStats.magic_attack(s, 40), 60, "magic attack includes power")
	check_eq(CharacterStats.magic_range(_job(0.5), 40, s), Vector2i(45, 90), "range")
	check_eq(CharacterStats.magic_range(_job(), 0, StatBlock.new()), Vector2i(1, 1), "floor of one")

func test_magic_range_ignores_weapon_attack() -> void:
	var j := _job()
	var a := CharacterStats.magic_range(j, 40, StatBlock.new())
	var b := CharacterStats.magic_range(j, 40, UnitHelpers.stats({"attack": 500}))
	check_eq(a, b, "only power and Magic Attack")

func test_accuracy_and_avoid() -> void:
	var s := UnitHelpers.stats({"accuracy": 3, "avoid": 2})
	check_eq(CharacterStats.accuracy(s), 3, "accuracy is gear's")
	check_eq(CharacterStats.accuracy(StatBlock.new()), 0, "zero")
	var j := _job()
	check_eq(CharacterStats.avoid(j, 1, s), 2 + CharacterStats.BASE_AVOID, "avoid = gear + base")
	check_eq(CharacterStats.avoid(j, 50, s), 2 + CharacterStats.BASE_AVOID, "no growth without avoid_growth")
	j.avoid_growth = 3.75
	check_eq(CharacterStats.avoid(j, 1, StatBlock.new()), CharacterStats.BASE_AVOID, "nothing at level 1")
	check_eq(CharacterStats.avoid(j, 11, s), 2 + CharacterStats.BASE_AVOID + 38, "3.75 a level, rounded")

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

func test_hearts_and_mp_grow_with_level_and_gear() -> void:
	var j := fx.job()  # MP 20 + 5 a level
	check_eq(CharacterStats.max_hearts(j, 1, StatBlock.new()), 5, "five segments at level 1")
	check_eq(CharacterStats.max_hearts(j, 0, StatBlock.new()), 5, "never below level 1")
	check_eq(CharacterStats.max_hearts(j, 19, StatBlock.new()), 5, "still five at level 19")
	check_eq(CharacterStats.max_hearts(j, 20, StatBlock.new()), 6, "one more every 20 levels")
	check_eq(CharacterStats.max_hearts(j, 100, StatBlock.new()), 10, "ten at level 100")
	check_eq(CharacterStats.max_hearts(j, 1, UnitHelpers.stats({"heart_pieces": 3})), 5, "three pieces aren't a segment")
	check_eq(CharacterStats.max_hearts(j, 1, UnitHelpers.stats({"heart_pieces": 4})), 6, "four pieces make a segment")
	j.bonus_hearts = 1
	check_eq(CharacterStats.max_hearts(j, 1, StatBlock.new()), 6, "the job's bonus segment")
	check_eq(CharacterStats.max_mp(j, 1, StatBlock.new()), 25, "MP at level 1")
	check_eq(CharacterStats.max_mp(j, 30, UnitHelpers.stats({"max_mp": 5})), 175, "MP at level 30, with gear")

func test_real_jobs_grow_their_damage_with_level() -> void:
	var s := UnitHelpers.stats({"attack": 10})
	for id in Content.jobs:
		var j: JobDef = Content.jobs[id]
		check(j.base_power > 0, "%s: has base power" % id)
		var low := CharacterStats.damage_range(j, CharacterStats.power(j, 10), s).y
		check(CharacterStats.damage_range(j, CharacterStats.power(j, 30), s).y > low, "%s: levels raise damage" % id)

func test_stat_block_rolled_and_format() -> void:
	check_eq(StatBlock.format(&"attack", 3), "+3", "plain")
	check_eq(StatBlock.format(&"defense", -2), "-2", "negative")
	check_eq(StatBlock.format(&"speed", 5), "+5%", "percent")
	var s := UnitHelpers.stats({"attack": 5})
	check_eq(s.rolled(0).to_dict(), {"attack": 5}, "no spread")
	check_eq(StatBlock.from_dict(s.to_dict()).attack, 5, "round trip")
	check_eq(StatBlock.from_dict({"bogus": 3}).nonzero().size(), 0, "unknown keys ignored")
	var p := s.plus(UnitHelpers.stats({"attack": 2, "avoid": 1}))
	check_eq(p.to_dict(), {"attack": 7, "avoid": 1}, "plus")
	check_eq(s.attack, 5, "plus doesn't change the original")
	s.add(null)
	check_eq(s.attack, 5, "adding null is a no-op")

func test_shop_prices_are_the_same_for_everyone() -> void:
	var line := ShopEntry.new()
	line.item = fx.use()
	line.price = 1000
	check_eq(line.cost(), 1000, "listed price")
	line.price = 0
	line.item.sell_price = 30
	check_eq(line.cost(), 30 * ShopEntry.PRICE_MARKUP, "marked-up sell price")
