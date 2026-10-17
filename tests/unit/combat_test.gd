extends TestCase
## Combat: player hits (never miss, crits, damage range and skill multiplier, magic, no
## penalty against stronger monsters), monster touches (dodge from avoid and the job's growth, defense, floor of 1)
## and the faint penalty. Randomness is pinned with seed() or stats that force the outcome.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

## A character whose physical range is exactly 9..18 (power 25 at level 4) and who never
## crits.
func _fighter(extra := {}) -> Character:
	var values := {"attack": 10, "crit": -12}
	values.merge(extra, true)
	var c := fx.character(null, 4)
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
		check(not r["miss"], "no misses")
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
	c.skills.learned[s.id] = 3  # 1 + 0.5 × 2 = 2.0
	check_near(s.damage_at(c.skills.level(s)), 2.0, "multiplier at level 3")
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

func test_stronger_monster_neither_dodges_nor_shrugs_off_damage() -> void:
	var c := _fighter()
	var m := fx.monster(&"t_mob", 60)
	var s := _attack()
	for i in 300:
		var r := Combat.player_hit(s, m, c)
		check(not r["miss"], "no misses without accuracy")
		check_between(r["damage"], 9, 18, "the full damage range")

func test_magic_skill_uses_magic_range() -> void:
	var c := _fighter()
	_wear(c, {"magic_attack": 35, "crit": -12})  # M = 25 power + 35
	var s := _attack()
	s.magic = true
	var m := fx.monster(&"t_mob", 10)
	for i in 100:
		check_between(Combat.player_hit(s, m, c)["damage"], 45, 90, "magic range 45..90")

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
	_wear(c, {"defense": 10, "avoid": -CharacterStats.BASE_AVOID})
	var m := fx.monster(&"t_mob", 10)
	m.attack = 100
	# 100 × 0.85..1.15 - 10 × 0.3 = 82..112
	for i in 300:
		check_between(Combat.monster_hit(m, c), 82, 112, "touch damage")

func test_monster_hit_never_below_one() -> void:
	var c := _fighter()
	_wear(c, {"defense": 1000, "avoid": -CharacterStats.BASE_AVOID})
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

func test_dodge_comes_from_avoid_alone() -> void:
	var c := _fighter({"avoid": 50 - CharacterStats.BASE_AVOID})  # 50 × 0.004 = 20%
	var m := fx.monster(&"t_mob", 60)
	var dodged := 0
	for i in 2000:
		if Combat.monster_hit(m, c) == 0:
			dodged += 1
	check_between(dodged, 300, 500, "about 20% dodged, however strong the monster")

func test_dodge_grows_with_the_jobs_avoid_growth() -> void:
	var c := _fighter({"avoid": -CharacterStats.BASE_AVOID})
	c.job.avoid_growth = 2.5
	c.level = 21  # 2.5 × 20 = 50: 20%
	var m := fx.monster(&"t_mob", 10)
	var dodged := 0
	for i in 2000:
		if Combat.monster_hit(m, c) == 0:
			dodged += 1
	check_between(dodged, 300, 500, "about 20% dodged")

func test_faint_penalty_is_ten_percent_rounded_down() -> void:
	check_eq(Combat.faint_penalty(0), 0, "zero")
	check_eq(Combat.faint_penalty(9), 0, "rounds down")
	check_eq(Combat.faint_penalty(1005), 100, "ten percent")
