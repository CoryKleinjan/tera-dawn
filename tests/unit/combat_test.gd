extends TestCase
## Combat: player hits (misses against higher monsters, crits, damage range and skill
## multiplier, level penalty, ammo and magic), monster touches (dodge, defense, floor of 1)
## and the faint penalty. Randomness is pinned with seed() or stats that force the outcome.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

## A level-10 character whose physical range is exactly 9..18 and who never crits.
func _fighter(extra := {}) -> Character:
	var values := {"strength": 20, "dexterity": 10, "attack": 10, "crit": -12}
	values.merge(extra, true)
	var c := fx.character(null, {})
	c.base = UnitHelpers.stats(values)
	c.level = 10
	c.recalc()
	return c

func _attack(multiplier := 1.0) -> SkillDef:
	var s := fx.skill(&"t_hit")
	s.damage_multiplier = multiplier
	s.innate = true
	return s

func test_same_level_never_misses_and_stays_in_range() -> void:
	var c := _fighter()
	var m := fx.monster(&"t_mob", 10)
	var s := _attack()
	for i in 300:
		var r := Combat.player_hit(s, m, c)
		check(not r["miss"], "no misses at equal level")
		check(not r["crit"], "no crits at 0% crit rate")
		check_between(r["damage"], 9, 18, "within damage range")

func test_skill_multiplier_scales_damage() -> void:
	var c := _fighter()
	var m := fx.monster(&"t_mob", 1)
	var s := _attack(2.0)
	for i in 200:
		check_between(Combat.player_hit(s, m, c)["damage"], 18, 36, "doubled range")

func test_skill_level_raises_multiplier() -> void:
	var s := _attack(1.0)
	s.innate = false
	s.damage_per_level = 0.5
	var c := _fighter()
	c.skills[s.id] = 3  # 1 + 0.5 × 2 = 2.0
	check_near(s.damage_at(c.skill_level(s)), 2.0, "multiplier at level 3")
	var m := fx.monster(&"t_mob", 1)
	for i in 100:
		check_between(Combat.player_hit(s, m, c)["damage"], 18, 36, "level 3 range")

func test_certain_crit_multiplies_damage() -> void:
	var c := _fighter({"crit": 100})
	var m := fx.monster(&"t_mob", 10)
	var s := _attack()
	for i in 200:
		var r := Combat.player_hit(s, m, c)
		check(r["crit"], "always crits")
		check_between(r["damage"], roundi(9 * 1.6), roundi(18 * 1.6), "crit range")

func test_higher_level_monster_takes_less_and_can_dodge() -> void:
	var c := _fighter()
	c.base.dexterity = 0
	c.recalc()
	var m := fx.monster(&"t_mob", 20)  # 10 levels above: 60% miss before accuracy, capped at 60%
	var s := _attack()
	var misses := 0
	for i in 1000:
		var r := Combat.player_hit(s, m, c)
		if r["miss"]:
			misses += 1
			check_eq(r["damage"], 0, "miss does no damage")
		else:
			# raw 8..18 (STR 20 only: 80 × 10 / 100 × 2 = 16)... minus 20, floored at 1
			check_eq(r["damage"], 1, "level gap eats the damage down to 1")
	check_between(misses, 500, 700, "about 60% misses")

func test_accuracy_wins_back_misses() -> void:
	var c := _fighter({"accuracy": 1000})
	var m := fx.monster(&"t_mob", 30)
	var s := _attack()
	for i in 200:
		check(not Combat.player_hit(s, m, c)["miss"], "enough accuracy never misses")

func test_level_gap_reduction_is_two_per_level() -> void:
	var c := _fighter({"strength": 1000, "attack": 100})
	c.base.dexterity = 0
	c.job.mastery = 0.95
	c.recalc()
	var r := c.damage_range()
	var m := fx.monster(&"t_mob", 11)
	var s := _attack()
	s.damage_multiplier = 1.0
	c.base.accuracy = 1000
	c.recalc()
	for i in 100:
		check_between(Combat.player_hit(s, m, c)["damage"], r.x - 2, r.y - 2, "one level above: -2")

func test_magic_skill_uses_magic_range() -> void:
	var c := _fighter()
	c.base = UnitHelpers.stats({"intelligence": 40, "magic_attack": 20, "crit": -12})
	c.recalc()
	var s := _attack()
	s.magic = true
	var m := fx.monster(&"t_mob", 10)
	for i in 100:
		check_between(Combat.player_hit(s, m, c)["damage"], 45, 90, "magic range 45..90")

func test_ammo_skill_adds_ammo_attack() -> void:
	var c := _fighter()
	var bow := fx.equip(&"t_bow", EquipDef.Slot.WEAPON)
	bow.ammo = &"star"
	c.equipment.put(&"weapon", ItemStack.exact(bow))
	c.inventory.add(fx.ammo(&"t_star", &"star", 10), 50)
	var s := _attack()
	s.uses_ammo = true
	var m := fx.monster(&"t_mob", 10)
	# attack 20: (90) × 20 / 100 × 2 = 36, low 18
	for i in 100:
		check_between(Combat.player_hit(s, m, c)["damage"], 18, 36, "star attack added")

func test_player_hit_is_repeatable_with_same_seed() -> void:
	var c := _fighter({"crit": 20})
	var m := fx.monster(&"t_mob", 14)
	var s := _attack(1.3)
	seed(7)
	var a := []
	for i in 20:
		a.append(Combat.player_hit(s, m, c))
	seed(7)
	var b := []
	for i in 20:
		b.append(Combat.player_hit(s, m, c))
	check_eq(a, b, "same seed, same hits")

func test_monster_hit_range_without_dodge() -> void:
	var c := _fighter()
	c.base = UnitHelpers.stats({"defense": 10})
	c.level = 10
	c.recalc()
	var m := fx.monster(&"t_mob", 10)
	m.attack = 100
	# 100 × 0.85..1.15 - 6 - 3 = 76..106
	for i in 300:
		check_between(Combat.monster_hit(m, c), 76, 106, "touch damage")

func test_monster_hit_never_below_one() -> void:
	var c := _fighter()
	c.base = UnitHelpers.stats({"defense": 1000})
	c.recalc()
	var m := fx.monster(&"t_mob", 10)
	m.attack = 5
	for i in 50:
		check_eq(Combat.monster_hit(m, c), 1, "at least 1")

func test_monster_hit_dodge_capped_at_thirty_percent() -> void:
	var c := _fighter({"avoid": 10000})
	var m := fx.monster(&"t_mob", 1)
	var dodged := 0
	for i in 2000:
		if Combat.monster_hit(m, c) == 0:
			dodged += 1
	check_between(dodged, 500, 700, "about 30% dodged")

func test_high_level_monster_cannot_be_dodged() -> void:
	var c := _fighter({"avoid": 50})
	var m := fx.monster(&"t_mob", 60)
	for i in 300:
		check(Combat.monster_hit(m, c) > 0, "no dodge 50 levels up")

func test_faint_penalty_is_ten_percent_rounded_down() -> void:
	check_eq(Combat.faint_penalty(0), 0, "zero")
	check_eq(Combat.faint_penalty(9), 0, "rounds down")
	check_eq(Combat.faint_penalty(1005), 100, "ten percent")
