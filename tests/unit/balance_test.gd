extends TestCase
## Balance: a typical character of each job line beats a tier-matched (non-boss) monster
## in BAND hits at a few sample tiers, typical characters are built sensibly, and tiers
## take a sensible number of kills.

const SAMPLE_TIERS := [3, 10, 15, 22, 30]

## The non-boss monster whose tier (MonsterDef.level) is closest to `tier` (ties go to the
## lower id, so it's stable).
func _monster_near(tier: int) -> MonsterDef:
	var best: MonsterDef = null
	var ids := Content.monsters.keys()
	# by name: StringNames sort in an engine-internal order that changes between versions
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for id in ids:
		var m: MonsterDef = Content.monsters[id]
		if m.boss:
			continue
		if best == null or absi(m.level - tier) < absi(best.level - tier):
			best = m
	return best

func test_band_is_sane() -> void:
	check(Balance.BAND.x > 1.0 and Balance.BAND.x < Balance.BAND.y, "low < high")

func test_every_line_beats_its_tier_in_band() -> void:
	for t in SAMPLE_TIERS:
		var m := _monster_near(t)
		for j in Balance.lines():
			var hits := Balance.hits_to_kill(Balance.typical(j, m.level), m)
			check_between(hits, Balance.BAND.x - 0.2, Balance.BAND.y, "%s vs %s (tier %d)" % [j, m.id, m.level])

func test_typical_is_beginner_before_ten() -> void:
	var c := Balance.typical(&"mage", 9)
	check_eq(c.job.id, &"beginner", "beginner at 9")
	check_eq(Balance.typical(&"mage", 10).job.id, &"mage", "mage at 10")

func test_typical_buys_its_tiers_points() -> void:
	for j in Balance.lines():
		var c := Balance.typical(j, 20)
		var start: StatBlock = Content.job(&"beginner").starting_stats
		var spent := 0
		for s in StatBlock.BASE:
			spent += c.base.value(s) - start.value(s)
		check_eq(spent, 19 * CharacterStats.GROWTH_POINTS, "%s buys a tier's points for every tier past 1" % j)
		check_eq(c.ap.spent(), spent, "%s: the points count as bought" % j)
		check_eq([c.level, Balance.tier(c)], [20, 20], "%s is level 20, tier 20" % j)
		var main := StringName(c.job.primary_stat)
		check(c.base.value(main) - start.value(main) >= spent / 2, "%s puts most into the main stat" % j)

func test_typical_wears_a_weapon_it_can_use() -> void:
	for j in Balance.lines():
		var c := Balance.typical(j, 20)
		check(c.gear.weapon() != null, "%s has a weapon" % j)
		var e := c.gear.weapon()
		if e:
			check_eq(c.gear.equip_problem(e), "", "%s can wear its weapon" % j)

func test_typical_gets_stronger_with_tier() -> void:
	var m := _monster_near(20)
	for j in Balance.lines():
		var low := Balance.hits_to_kill(Balance.typical(j, 12), m)
		var high := Balance.hits_to_kill(Balance.typical(j, 30), m)
		check(high < low, "%s at 30 kills faster than at 12" % j)

func test_main_attack_is_known_to_the_job() -> void:
	for j in Balance.lines():
		var c := Balance.typical(j, 20)
		var attack: Array = Balance.main_attack(c)
		var s: SkillDef = attack[0]
		check(s.innate or c.job_line().has(s.job), "%s uses its own skill %s" % [j, s.id])
		check_between(attack[1], 1, s.max_level, "%s skill level" % j)

func test_kills_per_tier() -> void:
	# a tier is a level's EXP, and a monster gives as much EXP as essence
	var cost := CharacterStats.xp_need(1)
	var m := MonsterDef.new()
	m.essence = cost
	check_near(Balance.kills_per_tier(1, m), 1.0, "one kill pays for tier 1")
	m.essence = 0
	check_near(Balance.kills_per_tier(1, m), float(cost), "zero essence treated as 1")
	m.essence = cost
	check(Balance.kills_per_tier(2, m) > 1.0, "later tiers cost more")
	for t in SAMPLE_TIERS:
		var real := _monster_near(t)
		check(Balance.kills_per_tier(real.level, real) <= 1000.0, "%s: no more than 1000 kills a tier" % real.id)
