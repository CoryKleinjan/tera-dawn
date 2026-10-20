extends TestCase
## Achievements: every kind of goal is measured from the character, is reached at exactly
## its goal and not before, and is only awarded once.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

func _ids(list: Array[AchievementDef]) -> Array:
	return list.map(func(a: AchievementDef) -> String: return String(a.id))

## Raises what `kind` measures on `c` to `n`.
func _raise(c: Character, kind: String, n: int) -> void:
	match kind:
		"kills":
			var m := fx.monster(&"t_k")
			c.book.pages.erase(m.id)
			for i in n:
				c.book.record_kill(m)
		"cards", "pages":
			c.book.pages.clear()
			var left := n * (CardDef.SET if kind == "pages" else 1)
			var k := 0
			while left > 0:
				var m := fx.monster(StringName("t_c%d" % k))
				for i in mini(left, CardDef.SET):
					c.book.add_card(m)
				left -= mini(left, CardDef.SET)
				k += 1
		"job": c.job.advances_from = &"beginner" if n > 0 else &""
		"quests":
			c.quests.done.clear()
			for i in n:
				c.quests.done[StringName("t_q%d" % i)] = 1
		"maps":
			c.visited.clear()
			for i in n:
				c.visit(StringName("t_map%d" % i))
		"shards": c.shards = n
		"boss_kinds":
			c.book.pages.clear()
			var bosses := Content.monsters.values().filter(func(m: MonsterDef) -> bool: return m.boss)
			for i in n:
				c.book.record_kill(bosses[i])
		"zones_explored":
			c.visited.clear()
			var regions := Content.regions.values()
			for i in n:
				for m: MapDef in Content.maps.values():
					if m.region == regions[i].id:
						c.visit(m.id)
		_: c.counters[kind] = n

func test_every_achievement_reached_exactly_at_goal() -> void:
	for a in Achievements.all():
		var c := fx.character()
		var goal := a.goal
		_raise(c, a.kind, goal - 1)
		check(not _ids(Achievements.check(c)).has(String(a.id)), "%s not reached one short" % a.id)
		_raise(c, a.kind, goal)
		check_eq(Achievements.measure(c, a.kind), goal, "%s measured" % a.id)
		check(_ids(Achievements.check(c)).has(String(a.id)), "%s reached at goal" % a.id)

func test_check_awards_only_once() -> void:
	var c := fx.character()
	_raise(c, "kills", Achievements.find("hunter").goal)
	var first := _ids(Achievements.check(c))
	check_has(first, "first_hunt", "the first kill goal")
	check_has(first, "hunter", "the second")
	check(not first.has("slayer"), "not the third")
	check_eq(Achievements.check(c).size(), 0, "nothing new the second time")
	check_eq(c.achievements.count("first_hunt"), 1, "listed once")

func test_fresh_character_reaches_nothing() -> void:
	var c := fx.character()
	check_eq(Achievements.check(c).size(), 0, "nothing with no stats bought")
	check_eq(c.achievements.size(), 0, "list empty")

func test_measure_reads_counters_and_unknown_kinds() -> void:
	var c := fx.character()
	c.count(Counters.BOSSES)
	c.count(Counters.BOSSES, 4)
	check_eq(Achievements.measure(c, Counters.BOSSES), 5, "counter")
	check_eq(Achievements.measure(c, "never_counted"), 0, "unknown kind is 0")

func test_job_counts_only_after_advancing() -> void:
	var c := fx.character()
	check_eq(Achievements.measure(c, "job"), 0, "beginner-like job")
	c.job = fx.job(&"t_adv", &"warrior", &"t_job")
	check_eq(Achievements.measure(c, "job"), 1, "advanced job")

func test_overshooting_goal_still_counts() -> void:
	var c := fx.character()
	c.shards = 5_000_000
	check_has(_ids(Achievements.check(c)), "nest_egg", "well past the goal")

func test_find() -> void:
	check_eq(Achievements.find("hunter").goal, 500, "known")
	check(Achievements.find("nope") == null, "unknown")

func test_list_ids_and_kinds_are_sane() -> void:
	var ids := {}
	for a in Achievements.all():
		check(not ids.has(a.id), "%s unique" % a.id)
		ids[a.id] = true
		check(a.goal > 0, "%s has a goal" % a.id)
		check(a.steam != "", "%s has a steam id" % a.id)
