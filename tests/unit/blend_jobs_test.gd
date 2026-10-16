extends TestCase
## Second-tier jobs: blends of two first jobs. Either parent can advance into one; both
## parents' skills open to it, both their stats add up for damage, and it wears both their
## gear. Uses the real blends in data/jobs.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

## A new character who has taken the first job `first`.
func _first_job(first: StringName) -> Character:
	var c := Character.create("Blender")
	c.job = Content.job(first)
	c.recalc()
	return c

func test_every_blend_joins_two_first_jobs_and_their_stats() -> void:
	var blends := 0
	for j: JobDef in Content.jobs.values():
		if j.partner == &"":
			continue
		blends += 1
		var a := Content.job(j.advances_from)
		var b := Content.job(j.partner)
		check(a.advances_from == Character.START_JOB and b.advances_from == Character.START_JOB, "%s joins two first jobs" % j.id)
		check_eq(j.damage_stats(), [StringName(a.primary_stat), StringName(b.primary_stat)] as Array[StringName], "%s: its stats are its parents'" % j.id)
		check_eq(j.tier(), 2, "%s is a second-tier job" % j.id)
	check_eq(blends, 5, "five blends")

func test_every_first_job_has_two_blends() -> void:
	for id in [&"warrior", &"mage", &"thief", &"archer", &"pirate"]:
		check_eq(JobDef.paths_from(id).size(), 2, "%s has two paths" % id)

func test_either_parent_can_advance_into_a_blend() -> void:
	var blade := Content.job(&"spellblade")
	var warrior := _first_job(&"warrior")
	var mage := _first_job(&"mage")
	var thief := _first_job(&"thief")
	check_eq(warrior.advance_problem(blade), "", "a Warrior can")
	check_eq(mage.advance_problem(blade), "", "a Magician can")
	check(thief.advance_problem(blade) != "", "a Thief can't")

func test_a_blend_learns_both_parents_skills() -> void:
	var c := _first_job(&"mage")
	check_eq(c.advance(Content.job(&"spellblade")), "", "advanced")
	check_eq(c.came_from, &"mage", "remembers coming from Magician")
	check_eq(c.job_path(), [&"spellblade", &"mage", &"beginner"] as Array[StringName], "its path runs back through Magician")
	check(&"warrior" in c.job_line(), "Warrior skills open to it")
	check(not &"thief" in c.job_line(), "Thief skills don't")
	c.essence = 100000
	check_eq(c.skills.learn(Content.skill(&"power_strike")), "", "learns a Warrior skill")
	check_eq(c.skills.learn(Content.skill(&"ice_spike")), "", "and a Magician skill")
	check(c.skills.learn(Content.skill(&"shadow_fang")) != "", "but not a Thief skill")

func test_came_from_is_saved() -> void:
	var c := _first_job(&"mage")
	c.advance(Content.job(&"spellblade"))
	var back := Character.new()
	back.load_dict(c.to_dict())
	check_eq(back.came_from, &"mage", "kept")
	check_eq(back.job_path()[1], &"mage", "so the path still runs through Magician")

func test_both_parents_skills_share_one_price() -> void:
	var c := _first_job(&"warrior")
	c.advance(Content.job(&"wildhunter"))
	c.essence = c.skills.price()
	check_eq(c.skills.learn(Content.skill(&"power_strike")), "", "a Warrior skill bought")
	check_eq(c.essence, 0, "for its price")
	check_eq(c.skills.price(), CharacterStats.skill_price(1), "the next skill, from either parent, costs the second level's price")

func test_both_stats_add_up_for_damage() -> void:
	var blade := Content.job(&"spellblade")
	var s := UnitHelpers.stats({"strength": 100, "intelligence": 50})
	check_eq(blade.damage_stat_value(s), 150, "STR and INT added")
	var more_str := UnitHelpers.stats({"strength": 110, "intelligence": 50, "attack": 20})
	var more_int := UnitHelpers.stats({"strength": 100, "intelligence": 60, "attack": 20})
	check_eq(CharacterStats.damage_range(blade, more_str), CharacterStats.damage_range(blade, more_int), "a point in either is worth the same")
	check_eq(CharacterStats.magic_attack(more_int, blade), 160, "spells add both too")
	check_eq(CharacterStats.magic_attack(more_int, Content.job(&"mage")), 60, "a Magician's spells only INT")

func test_auto_buys_both_stats_in_turn() -> void:
	var c := Character.create("Hexer")
	c.job = Content.job(&"hexcaster")
	c.recalc()
	var int_before := c.base.intelligence
	var luk_before := c.base.luck
	# the cheaper first, a tie to the first stat: INT, LUK, INT, LUK, INT
	c.essence = 2 * CharacterStats.stat_price(0) + 2 * CharacterStats.stat_price(1) + CharacterStats.stat_price(2)
	check_eq(c.ap.auto(), 5, "five points bought")
	check_eq(c.base.intelligence - int_before, 3, "three in INT")
	check_eq(c.base.luck - luk_before, 2, "two in LUK")
	check_eq(c.essence, 0, "every bit of essence spent")

func test_a_blend_wears_both_parents_gear() -> void:
	var c := fx.character(Content.job(&"spellblade"))
	check(c.gear.can_use([&"warrior"] as Array[StringName]), "Warrior gear")
	check(c.gear.can_use([&"mage"] as Array[StringName]), "Magician gear")
	check(not c.gear.can_use([&"thief"] as Array[StringName]), "not Thief gear")
