extends TestCase
## Balance: a typical character of each job line beats a level-matched (non-boss) monster
## in BAND hits at a few sample levels, typical characters are built sensibly, and levels
## take a sensible number of kills.

const SAMPLE_LEVELS := [3, 10, 15, 22, 30]

## The non-boss monster closest to `level` (ties go to the lower id, so it's stable).
func _monster_near(level: int) -> MonsterDef:
	var best: MonsterDef = null
	var ids := Content.monsters.keys()
	# by name: StringNames sort in an engine-internal order that changes between versions
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id in ids:
		var m: MonsterDef = Content.monsters[id]
		if m.boss:
			continue
		if best == null or absi(m.level - level) < absi(best.level - level):
			best = m
	return best

func test_band_is_sane() -> void:
	check(Balance.BAND.x > 1.0 and Balance.BAND.x < Balance.BAND.y, "low < high")

func test_every_line_beats_its_level_in_band() -> void:
	for lvl in SAMPLE_LEVELS:
		var m := _monster_near(lvl)
		for j in Balance.LINES:
			var hits := Balance.hits_to_kill(Balance.typical(j, m.level), m)
			check_between(hits, Balance.BAND.x - 0.2, Balance.BAND.y, "%s vs %s (Lv %d)" % [j, m.id, m.level])

func test_typical_is_beginner_before_ten() -> void:
	var c := Balance.typical(&"mage", 9)
	check_eq(c.job.id, &"beginner", "beginner at 9")
	check_eq(Balance.typical(&"mage", 10).job.id, &"mage", "mage at 10")

func test_typical_spends_all_points() -> void:
	for j in Balance.LINES:
		var c := Balance.typical(j, 20)
		var start: StatBlock = Content.job(&"beginner").starting_stats
		var spent := 0
		for s in StatBlock.BASE:
			spent += c.base.value(s) - start.value(s)
		check_eq(spent, 19 * c.job.ap_per_level, "%s spends every point" % j)
		var main := StringName(c.job.primary_stat)
		check(c.base.value(main) - start.value(main) >= spent / 2, "%s puts most into the main stat" % j)

func test_typical_wears_a_weapon_it_can_use() -> void:
	for j in Balance.LINES:
		var c := Balance.typical(j, 20)
		check(c.gear.weapon() != null, "%s has a weapon" % j)
		var e := c.gear.weapon()
		if e:
			check_eq(c.gear.equip_problem(e), "", "%s can wear its weapon" % j)
		if e and e.ammo != &"":
			check(c.gear.ammo_count() > 0, "%s has ammo" % j)

func test_typical_gets_stronger_with_level() -> void:
	var m := _monster_near(20)
	for j in Balance.LINES:
		var low := Balance.hits_to_kill(Balance.typical(j, 12), m)
		var high := Balance.hits_to_kill(Balance.typical(j, 30), m)
		check(high < low, "%s at 30 kills faster than at 12" % j)

func test_main_attack_is_known_to_the_job() -> void:
	for j in Balance.LINES:
		var c := Balance.typical(j, 20)
		var attack: Array = Balance.main_attack(c)
		var s: SkillDef = attack[0]
		check(s.innate or c.job_line().has(s.job), "%s uses its own skill %s" % [j, s.id])
		check_between(attack[1], 1, s.max_level, "%s skill level" % j)

func test_kills_per_level() -> void:
	var m := MonsterDef.new()
	m.exp_reward = 55
	check_near(Balance.kills_per_level(1, m), 1.0, "55 EXP at level 1")
	m.exp_reward = 0
	check_near(Balance.kills_per_level(1, m), 55.0, "zero EXP treated as 1")
	for lvl in SAMPLE_LEVELS:
		var real := _monster_near(lvl)
		check(Balance.kills_per_level(real.level, real) <= 1000.0, "%s: no more than 1000 kills a level" % real.id)
