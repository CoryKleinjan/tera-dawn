extends TestCase
## CharacterStats: the damage range from the weapon's attack, accuracy, crit, Speed and
## Jump multipliers with their caps, and hearts and Mana from shards.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

func test_damage_range_formula() -> void:
	# top = 10 × 2 = 20, lowest 20 × 0.7 = 14
	check_eq(CharacterStats.damage_range(UnitHelpers.stats({"attack": 10})), Vector2i(14, 20), "range")

func test_damage_range_grows_with_attack() -> void:
	check_eq(CharacterStats.damage_range(UnitHelpers.stats({"attack": 20})).y, 40, "twice the attack, twice the top")
	check_eq(CharacterStats.damage_range(UnitHelpers.stats({"attack": 10, "defense": 90, "accuracy": 50, "avoid": 7})).y, 20, "other stats don't add to it")

func test_damage_range_uses_the_bigger_attack() -> void:
	check_eq(CharacterStats.damage_range(UnitHelpers.stats({"magic_attack": 15})), Vector2i(21, 30), "a wand's Magic Attack")
	check_eq(CharacterStats.damage_range(UnitHelpers.stats({"attack": 15, "magic_attack": 5})).y, 30, "Weapon Attack when it's bigger")
	check_eq(CharacterStats.main_attack(UnitHelpers.stats({"attack": 4, "magic_attack": 9})), 9, "the bigger of the two")

func test_damage_range_never_below_one() -> void:
	check_eq(CharacterStats.damage_range(StatBlock.new()), Vector2i(1, 1), "no attack")
	check_eq(CharacterStats.damage_range(UnitHelpers.stats({"attack": 1})), Vector2i(1, 2), "tiny")

func test_accuracy_is_gears() -> void:
	check_eq(CharacterStats.accuracy(UnitHelpers.stats({"accuracy": 3})), 3, "accuracy is gear's")
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

func test_hearts_and_mana_grow_only_from_shards() -> void:
	check_eq(CharacterStats.max_hp(0), CharacterStats.BASE_HEARTS, "five hearts to start")
	check_eq(CharacterStats.max_hp(CharacterStats.HEART_SHARDS_PER_HEART - 1), CharacterStats.BASE_HEARTS, "a heart needs every shard")
	check_eq(CharacterStats.max_hp(2 * CharacterStats.HEART_SHARDS_PER_HEART), CharacterStats.BASE_HEARTS + 2, "two hearts more")
	check_eq(CharacterStats.max_mp(0), CharacterStats.BASE_MANA, "a full orb to start")
	check_eq(CharacterStats.max_mp(CharacterStats.MANA_SHARDS_PER_ORB), CharacterStats.BASE_MANA + CharacterStats.MANA_PER_ORB, "a bigger orb")
	check_eq(CharacterStats.BASE_MANA / CharacterStats.HEAL_COST, 3, "a full orb heals three hearts")

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
