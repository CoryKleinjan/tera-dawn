extends TestCase
## Combat: player hits (never miss, crits, the weapon's damage range and the skill
## multiplier, spells hit the same way, no penalty against stronger monsters) and monster
## touches (a heart, or two from a boss's big move). Randomness is pinned with seed() or stats
## that force the outcome.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

## A character whose damage range is exactly 14..20 (10 attack) and who never crits.
func _fighter(extra := {}) -> Character:
	var values := {"attack": 10, "crit": -12}
	values.merge(extra, true)
	var c := fx.character()
	_wear(c, values)
	return c

## Puts gear with `values` on `c`, in place of the last.
func _wear(c: Character, values: Dictionary) -> void:
	c.equipment.put(&"weapon", ItemStack.exact(fx.equip(&"t_gear", EquipDef.Slot.WEAPON, values)))
	c.recalc()

func _attack(multiplier := 1.0) -> SkillDef:
	var s := fx.skill(&"t_hit")
	s.damage_multiplier = multiplier
	s.innate = true
	return s

func test_never_misses_and_stays_in_range() -> void:
	var c := _fighter()
	var m := fx.monster(&"t_mob", 10)
	var s := _attack()
	for i in 300:
		var r := Combat.player_hit(s, m, c)
		check(not r["crit"], "no crits at 0% crit rate")
		check_between(r["damage"], 14, 20, "within damage range")

func test_skill_multiplier_scales_damage() -> void:
	var c := _fighter()
	var m := fx.monster(&"t_mob", 1)
	var s := _attack(2.0)
	for i in 200:
		check_between(Combat.player_hit(s, m, c)["damage"], 28, 40, "doubled range")

func test_skill_level_raises_multiplier() -> void:
	var s := _attack(1.0)
	s.innate = false
	s.damage_per_level = 0.5
	var c := _fighter()
	c.skills.learned[s.id] = 3  # 1 + 0.5 × 2 = 2.0
	check_near(s.damage_at(c.skills.level(s)), 2.0, "multiplier at level 3")
	var m := fx.monster(&"t_mob", 1)
	for i in 100:
		check_between(Combat.player_hit(s, m, c)["damage"], 28, 40, "level 3 range")

func test_certain_crit_multiplies_damage() -> void:
	var c := _fighter({"crit": 100})
	var m := fx.monster(&"t_mob", 10)
	var s := _attack()
	for i in 200:
		var r := Combat.player_hit(s, m, c)
		check(r["crit"], "always crits")
		check_between(r["damage"], roundi(14 * 1.6), roundi(20 * 1.6), "crit range")

func test_stronger_monster_neither_dodges_nor_shrugs_off_damage() -> void:
	var c := _fighter()
	var m := fx.monster(&"t_mob", 60)
	var s := _attack()
	for i in 300:
		var r := Combat.player_hit(s, m, c)
		check_between(r["damage"], 14, 20, "the full damage range")

func test_a_spell_hits_with_the_same_range_as_a_swing() -> void:
	var c := _fighter()
	_wear(c, {"magic_attack": 35, "crit": -12})  # a wand: 35 × 2 = 70, lowest 49
	var s := _attack()
	s.magic = true
	var m := fx.monster(&"t_mob", 10)
	for i in 100:
		check_between(Combat.player_hit(s, m, c)["damage"], 49, 70, "the wand's damage range")

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

func test_a_monster_hit_takes_one_heart_whatever_its_strength() -> void:
	var c := _fighter({"defense": 1000, "avoid": 10000})
	var m := fx.monster(&"t_mob", 60)
	m.attack = 5000
	for i in 50:
		check_eq(Combat.monster_hit(m, c, 1.3), 1, "one heart: no dodging, no armor, no scaling")

func test_a_bosss_big_hit_takes_two_hearts() -> void:
	var c := _fighter()
	var m := fx.monster(&"t_boss", 10)
	m.boss = true
	check_eq(Combat.monster_hit(m, c), 1, "its touch takes one")
	check_eq(Combat.monster_hit(m, c, Combat.BIG_HIT_POWER - 0.05), 1, "a lighter move takes one")
	check_eq(Combat.monster_hit(m, c, Combat.BIG_HIT_POWER), 2, "a big move takes two")
