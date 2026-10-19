extends TestCase
## Balance: typical characters are built sensibly (job, gear tier, weapon) and get stronger
## with tier, and hits come from the weapon's damage range. Whether the game's monsters sit in
## BAND is the smoke test's job: here the runner's test gear (TestGear) is on offer too.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

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
	check(Balance.JOB_TIER < Balance.TOP_TIER, "jobs come before the top gear tier")

func test_lines_are_the_first_jobs() -> void:
	var lines := Balance.lines()
	check(not lines.is_empty(), "there are job lines")
	for j in lines:
		check_eq(Content.job(j).advances_from, Character.START_JOB, "%s is taken by a Beginner" % j)

func test_typical_is_beginner_before_job_tier() -> void:
	var c := Balance.typical(&"mage", Balance.JOB_TIER - 1)
	check_eq(c.job.id, Character.START_JOB, "a Beginner just before the job tier")
	check_eq(Balance.typical(&"mage", Balance.JOB_TIER).job.id, &"mage", "a Magician at the job tier")

func test_gear_rank_climbs_from_first_to_top() -> void:
	var top := Content.top_gear_tier()
	check_eq(Balance.gear_rank(1), 1, "first gear tier before jobs")
	check_eq(Balance.gear_rank(Balance.JOB_TIER), 1, "first gear tier at the job tier")
	check_eq(Balance.gear_rank(Balance.TOP_TIER), top, "top gear tier at the top tier")
	check_eq(Balance.gear_rank(Balance.TOP_TIER + 20), top, "never past the top")
	for t in range(1, Balance.TOP_TIER + 2):
		check(Balance.gear_rank(t + 1) >= Balance.gear_rank(t), "never goes down at tier %d" % t)

func test_typical_wears_a_weapon_it_can_use_at_its_gear_rank() -> void:
	for j in Balance.lines():
		var c := Balance.typical(j, 20)
		var e := c.gear.weapon()
		check(e != null, "%s has a weapon" % j)
		if e == null:
			continue
		check_eq(c.gear.equip_problem(e), "", "%s can wear its weapon" % j)
		check_eq(c.equipment.at(c.equipment.place_for(e)).tier, Balance.gear_rank(20), "%s's weapon is raised to the gear tier" % j)

func test_typical_gets_stronger_with_tier() -> void:
	var m := _monster_near(20)
	for j in Balance.lines():
		var low := Balance.hits_to_kill(Balance.typical(j, 12), m)
		var high := Balance.hits_to_kill(Balance.typical(j, 30), m)
		check(high < low, "%s at 30 kills faster than at 12" % j)

func test_main_attack_is_the_weapons_own() -> void:
	for j in Balance.lines():
		var c := Balance.typical(j, 20)
		var s := Balance.main_attack(c)
		check(s != null, "%s has an attack" % j)
		check_eq(s, c.skills.basic_attack(), "%s uses its weapon's attack" % j)

func test_hits_come_from_the_damage_range() -> void:
	var c := Balance.typical(&"warrior", 20)
	var s := Balance.main_attack(c)
	var spread := c.damage_range()
	var hit := Balance.average_hit(c, s)
	check_between(hit, spread.x * s.damage_at(1), spread.y * s.damage_at(1) * Combat.CRIT_MULTIPLIER, "an average hit is inside the range (crits included)")
	check_near(Balance.swing_damage(c), hit * s.hits, "a swing is every hit of the attack")
	var m := fx.monster(&"t_mob", 20, 1000)
	check_near(Balance.hits_to_kill(c, m), 1000.0 / Balance.swing_damage(c), "hits to kill are its HP over a swing")
