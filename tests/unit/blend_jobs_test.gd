extends TestCase
## Second-tier jobs: blends of two first jobs. Either parent can advance into one; both
## parents' skills open to it, its base power is both of theirs added up, and it wears both
## their gear. Uses the real blends in data/jobs.

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

func test_every_blend_joins_two_first_jobs() -> void:
	var blends := 0
	for j: JobDef in Content.jobs.values():
		if j.partner == &"":
			continue
		blends += 1
		var a := Content.job(j.advances_from)
		var b := Content.job(j.partner)
		check(a.advances_from == Character.START_JOB and b.advances_from == Character.START_JOB, "%s joins two first jobs" % j.id)
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

func test_a_blends_base_power_is_both_parents_added() -> void:
	for j: JobDef in Content.jobs.values():
		if j.partner == &"":
			continue
		var want := Content.job(j.advances_from).base_power + Content.job(j.partner).base_power
		check_eq(j.base_power, want, "%s: its parents' power added" % j.id)

func test_a_blend_hits_harder_than_either_parent_at_the_same_level() -> void:
	var blade := Content.job(&"spellblade")
	var s := UnitHelpers.stats({"attack": 20})
	var hit := CharacterStats.damage_range(blade, CharacterStats.power(blade, 30), s).y
	for parent in [&"warrior", &"mage"]:
		var p := Content.job(parent)
		check(hit > CharacterStats.damage_range(p, CharacterStats.power(p, 30), s).y, "more than a %s" % parent)
	check_eq(CharacterStats.magic_attack(s, CharacterStats.power(blade, 30)), CharacterStats.power(blade, 30), "spells grow from the same power")

func test_a_blend_wears_both_parents_gear() -> void:
	var c := fx.character(Content.job(&"spellblade"))
	check(c.gear.can_use([&"warrior"] as Array[StringName]), "Warrior gear")
	check(c.gear.can_use([&"mage"] as Array[StringName]), "Magician gear")
	check(not c.gear.can_use([&"thief"] as Array[StringName]), "not Thief gear")
