extends TestCase
## QuestLog: who can take a quest, status changes, kill / collect / visit progress, quest
## item drops only while the quest wants them, handing in (items taken, rewards paid, room
## checks), repeatable quests, forfeiting and the save format.

var fx: UnitHelpers
var c: Character
var mob: MonsterDef
var loot: ItemDef

func before_each() -> void:
	fx = UnitHelpers.new()
	c = fx.character()
	mob = fx.monster(&"t_mob")
	loot = fx.etc(&"t_loot", 100)

func after_each() -> void:
	fx.cleanup()

func _kill_quest(id := &"t_kill", n := 3) -> QuestDef:
	var o := fx.objective(QuestObjective.Kind.KILL, n)
	o.monster = mob
	return fx.quest(id, [o])

func _collect_quest(id := &"t_collect", n := 5, drop_from: MonsterDef = null) -> QuestDef:
	var o := fx.objective(QuestObjective.Kind.COLLECT, n)
	o.item = loot
	o.drop_from = drop_from
	o.drop_chance = 0.25
	return fx.quest(id, [o])

func _visit_quest(id := &"t_visit", map := &"t_far") -> QuestDef:
	var o := fx.objective(QuestObjective.Kind.VISIT, 1)
	o.map = map
	return fx.quest(id, [o])

func test_can_take_level_window() -> void:
	var q := _kill_quest()
	q.min_level = 5
	q.max_level = 8
	c.level = 4
	check(not c.quests.can_take(q, c), "too low")
	check_eq(c.quests.status(q, c), QuestLog.Status.LOCKED, "locked")
	c.level = 5
	check(c.quests.can_take(q, c), "min level")
	c.level = 8
	check(c.quests.can_take(q, c), "max level")
	c.level = 9
	check(not c.quests.can_take(q, c), "too high")
	q.max_level = 0
	c.level = 200
	check(c.quests.can_take(q, c), "0 means no cap")

func test_can_take_job_list() -> void:
	var q := _kill_quest()
	q.jobs = [&"t_other_job"]
	check(not c.quests.can_take(q, c), "wrong job")
	q.jobs = [&"t_other_job", &"t_job"]
	check(c.quests.can_take(q, c), "listed job")

func test_can_take_needs_required_quests_done() -> void:
	var q := _kill_quest()
	q.requires = [&"t_before"]
	check(not c.quests.can_take(q, c), "prerequisite not done")
	c.quests.done[&"t_before"] = 1
	check(c.quests.can_take(q, c), "prerequisite done")

func test_status_flow_for_kill_quest() -> void:
	var q := _kill_quest(&"t_kill", 2)
	check_eq(c.quests.status(q, c), QuestLog.Status.AVAILABLE, "available")
	c.quests.accept(q)
	check_eq(c.quests.status(q, c), QuestLog.Status.ACTIVE, "active")
	c.quests.record_kill(mob)
	check_eq(c.quests.status(q, c), QuestLog.Status.ACTIVE, "halfway")
	c.quests.record_kill(mob)
	check_eq(c.quests.status(q, c), QuestLog.Status.READY, "ready")
	check_eq(c.quests.complete(q, c), "", "handed in")
	check_eq(c.quests.status(q, c), QuestLog.Status.DONE, "done")

func test_kill_progress_caps_and_ignores_other_monsters() -> void:
	var q := _kill_quest(&"t_kill", 2)
	c.quests.accept(q)
	var other := fx.monster(&"t_other")
	check_eq(c.quests.record_kill(other).size(), 0, "other monster moves nothing")
	check_eq(Array(c.quests.record_kill(mob)), [q], "moved on")
	c.quests.record_kill(mob)
	check_eq(c.quests.record_kill(mob).size(), 0, "full: no longer moves")
	check_eq(c.quests.active[q.id], [2], "count capped")
	check_eq(c.quests.progress(q, 0, c), 2, "progress")

func test_kills_without_the_quest_count_for_nothing() -> void:
	var q := _kill_quest()
	check_eq(c.quests.record_kill(mob).size(), 0, "not taken")
	check_eq(c.quests.progress(q, 0, c), 0, "no progress")
	check(not c.quests.is_ready(q, c), "not ready")

func test_one_kill_moves_every_quest_that_wants_it() -> void:
	var a := _kill_quest(&"t_a")
	var b := _kill_quest(&"t_b")
	c.quests.accept(a)
	c.quests.accept(b)
	check_eq(c.quests.record_kill(mob).size(), 2, "both moved")

func test_collect_progress_counts_the_bag() -> void:
	var q := _collect_quest(&"t_collect", 5)
	c.quests.accept(q)
	check_eq(c.quests.progress(q, 0, c), 0, "empty")
	c.inventory.add(loot, 3)
	check_eq(c.quests.progress(q, 0, c), 3, "three in bag")
	c.inventory.add(loot, 10)
	check_eq(c.quests.progress(q, 0, c), 5, "capped at count")
	check(c.quests.is_ready(q, c), "ready")
	c.inventory.remove(loot, 12)
	check(not c.quests.is_ready(q, c), "selling them undoes it")

func test_visit_progress() -> void:
	var q := _visit_quest()
	c.quests.accept(q)
	check_eq(c.quests.record_visit(&"t_near").size(), 0, "wrong map")
	check_eq(Array(c.quests.record_visit(&"t_far")), [q], "right map")
	check(c.quests.is_ready(q, c), "ready")

func test_mixed_objectives_need_all() -> void:
	var k := fx.objective(QuestObjective.Kind.KILL, 1)
	k.monster = mob
	var g := fx.objective(QuestObjective.Kind.COLLECT, 2)
	g.item = loot
	var q := fx.quest(&"t_mixed", [k, g])
	c.quests.accept(q)
	c.quests.record_kill(mob)
	check(not c.quests.is_ready(q, c), "items missing")
	c.inventory.add(loot, 2)
	check(c.quests.is_ready(q, c), "both done")

func test_quest_items_drop_only_while_wanted() -> void:
	var q := _collect_quest(&"t_collect", 2, mob)
	check_eq(c.quests.quest_drops(mob, c), [], "no quest, no drop")
	c.quests.accept(q)
	check_eq(c.quests.quest_drops(mob, c), [[loot, 0.25]], "drops while on it")
	check_eq(c.quests.quest_drops(fx.monster(&"t_other"), c), [], "other monsters don't")
	c.inventory.add(loot, 2)
	check_eq(c.quests.quest_drops(mob, c), [], "enough collected: stops")
	c.quests.complete(q, c)
	check_eq(c.quests.quest_drops(mob, c), [], "after handing in")

func test_complete_before_ready_is_refused() -> void:
	var q := _kill_quest()
	check_ne(c.quests.complete(q, c), "", "not taken")
	c.quests.accept(q)
	check_ne(c.quests.complete(q, c), "", "not finished")
	check(c.quests.active.has(q.id), "still active")
	check(not c.quests.done.has(q.id), "not done")

func test_complete_takes_items_and_pays() -> void:
	var q := _collect_quest(&"t_collect", 5)
	var potion := fx.use(&"t_potion")
	var sword := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 10}, 5)
	q.reward_shards = 120
	q.reward_items = [UnitHelpers.drop(potion, 3), UnitHelpers.drop(sword)]
	c.shards = 7
	c.quests.accept(q)
	c.inventory.add(loot, 8)
	check_eq(c.quests.complete(q, c), "", "handed in")
	check_eq(c.inventory.count_of(loot), 3, "only five taken")
	check_eq(c.shards, 127, "shards paid")
	check_eq(c.inventory.count_of(potion), 3, "potions given")
	check_eq(c.inventory.at(ItemDef.Tab.EQUIP, 0).stats.attack, 10, "gear reward has exact stats")
	check(not c.quests.active.has(q.id), "no longer active")
	check_eq(c.quests.done[q.id], 1, "done once")

func test_complete_refused_without_room_for_rewards() -> void:
	var q := _kill_quest(&"t_kill", 1)
	var sword := fx.equip()
	q.reward_items = [UnitHelpers.drop(sword)]
	q.reward_shards = 50
	c.inventory.add(fx.equip(&"t_junk"), Inventory.SLOTS)
	c.quests.accept(q)
	c.quests.record_kill(mob)
	check_ne(c.quests.complete(q, c), "", "no room")
	check(c.quests.active.has(q.id), "still active")
	check_eq(c.shards, 0, "nothing paid")

func test_repeatable_quest_can_be_taken_again() -> void:
	var q := _kill_quest(&"t_kill", 1)
	q.repeatable = true
	for r in 3:
		check_eq(c.quests.status(q, c), QuestLog.Status.AVAILABLE, "available round %d" % r)
		c.quests.accept(q)
		check_eq(c.quests.progress(q, 0, c), 0, "fresh counts round %d" % r)
		c.quests.record_kill(mob)
		check_eq(c.quests.complete(q, c), "", "handed in round %d" % r)
	check_eq(c.quests.done[q.id], 3, "times handed in")

func test_forfeit_drops_progress() -> void:
	var q := _kill_quest()
	c.quests.accept(q)
	c.quests.record_kill(mob)
	c.quests.forfeit(q)
	check_eq(c.quests.status(q, c), QuestLog.Status.AVAILABLE, "available again")
	c.quests.accept(q)
	check_eq(c.quests.progress(q, 0, c), 0, "starts over")

func test_save_round_trip() -> void:
	var a := _kill_quest(&"t_a", 5)
	c.quests.accept(a)
	c.quests.record_kill(mob)
	c.quests.record_kill(mob)
	c.quests.done[&"t_old"] = 2
	var back := QuestLog.new()
	back.load_dict(c.quests.to_dict())
	check_eq(back.active[a.id], [2], "counts")
	check_eq(back.done[&"t_old"], 2, "done")

func test_load_fixes_counts_and_drops_unknown_quests() -> void:
	var k := fx.objective(QuestObjective.Kind.KILL, 3)
	k.monster = mob
	var v := fx.objective(QuestObjective.Kind.VISIT, 1)
	var q := fx.quest(&"t_two", [k, v])
	var ql := QuestLog.new()
	ql.load_dict({"active": {"t_two": [2.0], "t_gone": [1], "t_kill": "bad"}, "done": {"t_x": "4"}})
	check_eq(ql.active.size(), 1, "only the real quest")
	check_eq(ql.active[q.id], [2, 0], "padded to the objectives")
	check_eq(ql.done[&"t_x"], 4, "done count read")
	ql.load_dict({"active": "junk", "done": []})
	check_eq(ql.active.size() + ql.done.size(), 0, "junk clears it")

func test_to_dict_is_a_deep_copy() -> void:
	var q := _kill_quest()
	c.quests.accept(q)
	var d := c.quests.to_dict()
	d["active"][q.id][0] = 99
	check_eq(c.quests.active[q.id][0], 0, "log unchanged")

func test_real_repeatable_quest_reopens() -> void:
	var q := Content.quest(&"q06_tusk_collector")
	check(q.repeatable, "tusk collector repeats")
	var c2 := fx.character()
	c2.level = q.min_level
	c2.quests.done[q.id] = 1
	check_eq(c2.quests.status(q, c2), QuestLog.Status.AVAILABLE, "available after handing in")

func test_complete_refused_when_rewards_need_more_slots_than_free() -> void:
	var q := _kill_quest(&"t_kill", 1)
	q.reward_items = [UnitHelpers.drop(fx.equip(&"t_sword_a")), UnitHelpers.drop(fx.equip(&"t_sword_b"))]
	c.inventory.add(fx.equip(&"t_junk"), Inventory.SLOTS - 1)
	c.quests.accept(q)
	c.quests.record_kill(mob)
	check_ne(c.quests.complete(q, c), "", "two gear rewards, one free slot")
	check(c.quests.active.has(q.id), "still active")

func test_complete_counts_topping_up_stacks_toward_room() -> void:
	var potion := fx.use(&"t_potion", 10)
	var q := _kill_quest(&"t_kill", 1)
	q.reward_items = [UnitHelpers.drop(potion, 5), UnitHelpers.drop(potion, 5)]
	var junk := fx.use(&"t_junk_use", 1)
	c.inventory.add(potion, 5)
	c.inventory.add(junk, Inventory.SLOTS - 1)
	c.quests.accept(q)
	c.quests.record_kill(mob)
	check_ne(c.quests.complete(q, c), "", "ten potions need the full stack and a new slot, none free")
	c.inventory.remove(junk, 1)
	check_eq(c.quests.complete(q, c), "", "one free slot and the stack's room is enough")
	check_eq(c.inventory.count_of(potion), 15, "all rewards paid")
