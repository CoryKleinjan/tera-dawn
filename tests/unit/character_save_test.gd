extends TestCase
## Character.to_dict / load_dict: a full round trip (gear rolled stats,
## level, EXP, Dawn Essence, jobs passed, skills and what was paid for them, buffs, quickslots, buddies, fame, guild, Monster Book, pet, visited maps,
## achievements, tallies), bad values, and the older save formats load_dict still accepts
## (base stats handed back as essence).

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

## Everything filled in with values that differ from a fresh character.
func _rich() -> Character:
	var c := fx.character()
	c.name = "Saver"
	c.level = 12
	c.xp = 40
	c.essence = 345
	c.shards = 9876
	c.jobs_passed.assign(["t_next", "t_other"])
	c.map_id = Content.maps.keys()[0]
	var sword := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}, 3)
	var worn := ItemStack.exact(sword)
	worn.stats.attack = 23
	c.equipment.put(&"weapon", worn)
	var bagged := ItemStack.exact(fx.equip(&"t_ring", EquipDef.Slot.RING, {"avoid": 3}))
	bagged.stats.avoid = 4
	c.inventory.put(ItemDef.Tab.EQUIP, 6, bagged)
	c.inventory.add(fx.use(), 42)
	c.storage.add(fx.etc(), 9)
	var passive := fx.skill(&"t_passive", SkillDef.Kind.PASSIVE)
	passive.stats = UnitHelpers.stats({"defense": 7})
	var buff := fx.skill(&"t_buff", SkillDef.Kind.BUFF)
	buff.stats = UnitHelpers.stats({"attack": 4})
	buff.duration = 30.0
	c.skills.learned[passive.id] = 3
	c.skills.learned[buff.id] = 2
	c.skills.paid[passive.id] = 17 + 31 + 50
	c.skills.paid[buff.id] = 73 + 101
	c.skills.buffs[buff.id] = [2, 500]
	c.set_quickslot(0, &"skill", buff.id)
	c.set_quickslot(Character.QUICKSLOTS - 2, &"item", &"red_potion")
	c.buddies.assign(["Ana", "Bo"])
	c.fame = 7
	c.fame_day = 20000
	c.fame_given = {"Ana": 19999}
	c.guild = "Dawnguard"
	var mob := fx.monster()
	c.book.record_kill(mob)
	c.book.add_card(mob)
	var pet := PetDef.new()
	pet.id = &"t_pet"
	fx.register("items", pet)
	c.pet = &"t_pet"
	c.pet_full = 64
	c.visit(&"meadow")
	c.achievements.append("first_hunt")
	c.count(Counters.DEALS, 3)
	var q := fx.objective(QuestObjective.Kind.KILL, 5)
	q.monster = mob
	c.quests.accept(fx.quest(&"t_quest", [q]))
	c.quests.record_kill(mob)
	c.recalc()
	c.health.set_hp(50)
	c.mp = 17
	return c

func _round_trip(c: Character) -> Character:
	var back := Character.new()
	back.load_dict(c.to_dict())
	return back

func test_round_trip_basics() -> void:
	var c := _rich()
	var b := _round_trip(c)
	check_eq(b.name, "Saver", "name")
	check_eq(b.essence, 345, "essence")
	check_eq(b.shards, 9876, "shards")
	check_eq(Array(b.jobs_passed), ["t_next", "t_other"], "jobs passed")
	check_eq(b.map_id, c.map_id, "map")
	check(b.job == c.job, "job")
	check_eq([b.level, b.xp], [12, 40], "level and EXP")
	check_eq(b.power(), c.power(), "power")
	check_eq(b.health.hp, 50, "HP")
	check_eq(b.mp, 17, "MP")

func test_round_trip_gear_keeps_rolled_stats() -> void:
	var b := _round_trip(_rich())
	var w := b.equipment.at(&"weapon")
	check_eq(w.stats.attack, 23, "rolled attack")
	check_eq(b.inventory.at(ItemDef.Tab.EQUIP, 6).stats.avoid, 4, "bag gear rolled stats and slot")
	check_eq(b.stats.attack, 23 + 4, "worn gear and buff count in totals")

func test_round_trip_items_and_storage() -> void:
	var b := _round_trip(_rich())
	check_eq(b.inventory.count_of(Content.item(&"t_use")), 42, "potions")
	check_eq(b.storage.count_of(Content.item(&"t_etc")), 9, "storage")

func test_round_trip_skills_buffs_and_quickslots() -> void:
	var b := _round_trip(_rich())
	check_eq(b.skills.learned, {&"t_passive": 3, &"t_buff": 2}, "skills")
	check_eq(b.skills.paid, {&"t_passive": 98, &"t_buff": 174}, "essence paid for them")
	check_eq(b.skills.buffs, {&"t_buff": [2, 500]}, "buffs")
	check_eq(b.quickslots[0], [&"skill", &"t_buff"], "skill quickslot")
	check_eq(b.quickslots[Character.QUICKSLOTS - 2], [&"item", &"red_potion"], "potion quickslot")
	check_eq(b.stats.defense, 7, "passive applied")

func test_round_trip_social_book_pet_and_tallies() -> void:
	var b := _round_trip(_rich())
	check_eq(Array(b.buddies), ["Ana", "Bo"], "buddies")
	check_eq(b.fame, 7, "fame")
	check_eq(b.fame_day, 20000, "fame day")
	check_eq(b.fame_given, {"Ana": 19999}, "fame given")
	check_eq(b.guild, "Dawnguard", "guild")
	var mob := Content.monster(&"t_mob")
	check_eq(b.book.kills(mob), 1, "book kills")
	check_eq(b.book.cards(mob), 1, "book cards")
	check_eq(b.pet, &"t_pet", "pet")
	check_eq(b.pet_full, 64, "pet fullness")
	check_eq(Array(b.visited), ["meadow"], "visited")
	check_eq(Array(b.achievements), ["first_hunt"], "achievements")
	check_eq(b.counters, {"deals": 3}, "tallies")
	check_eq(b.quests.active[&"t_quest"], [1], "quest progress")

func test_round_trip_survives_json() -> void:
	var c := _rich()
	var back := Character.new()
	back.load_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check_eq(back.to_dict(), c.to_dict(), "same after JSON")

func test_save_has_level_exp_and_essence_and_no_points() -> void:
	var d := _rich().to_dict()
	check_eq([d["level"], d["xp"]], [12, 40], "level and EXP saved")
	check_eq(d["essence"], 345, "essence saved")
	check(d.has("skills_paid"), "what skills cost saved")
	for gone in ["ap", "sp", "ap_reset_used", "base", "stat_rules"]:
		check(not d.has(gone), "no %s" % gone)

func test_save_is_stable() -> void:
	var c := _rich()
	var once := c.to_dict()
	check_eq(_round_trip(c).to_dict(), once, "saving a loaded save changes nothing")

func test_to_dict_does_not_share_lists() -> void:
	var c := _rich()
	var d := c.to_dict()
	d["buddies"].append("Eve")
	d["counters"]["deals"] = 100
	check_eq(c.buddies.size(), 2, "buddies untouched")
	check_eq(c.counters["deals"], 3, "counters untouched")

func test_bad_values_are_clamped_or_ignored() -> void:
	var c := fx.character()
	c.load_dict({
		"job": "t_job", "essence": -10, "shards": -1, "map_id": "t_nowhere",
		"base": {},
		"skills": {"t_gone": 3}, "skills_paid": {"t_gone": 17},
		"buffs": {"t_gone": [1, 50], "t_job": "bad"},
		"pet": "t_etc", "pet_full": 500, "hp": 0, "mp": 99999,
	})
	check_eq(c.essence, 17, "essence floor, plus what the unknown skill cost")
	check_eq([c.level, c.xp], [1, 0], "no level from the days without levels")
	check_eq(c.shards, 0, "shards floor")
	check_eq(c.map_id, Character.START_MAP, "unknown map: start map")
	check(c.skills.learned.is_empty(), "unknown skill dropped")
	check(c.skills.paid.is_empty(), "and what was paid for it")
	check(c.skills.buffs.is_empty(), "bad buffs dropped")
	check_eq(c.pet, &"", "not a pet")
	check_eq(c.pet_full, 100, "fullness capped")
	check_eq(c.health.hp, 1, "loads with at least 1 HP")
	check_eq(c.mp, c.max_mp(), "MP capped")

func test_bad_paid_values_are_floored() -> void:
	fx.skill()
	var c := fx.character()
	c.load_dict({"job": "t_job", "essence": 0, "skills": {"t_skill": 1}, "skills_paid": {"t_skill": -5}})
	check_eq(c.skills.paid, {&"t_skill": 0}, "never negative")

func test_a_skill_gone_from_the_game_pays_back_its_essence() -> void:
	fx.skill()
	var c := fx.character()
	c.load_dict({"job": "t_job", "essence": 10, "skills": {"t_skill": 1, "t_gone": 2},
		"skills_paid": {"t_skill": 7, "t_gone": 50},
		"quickslots": [["skill", "t_gone"], ["skill", "t_skill"]]})
	check(not c.skills.learned.has(&"t_gone"), "dropped")
	check_eq(c.essence, 60, "its essence back")
	check_eq(c.quickslots[0], [], "its quickslot emptied")
	check_eq(c.quickslots[1], [&"skill", &"t_skill"], "others kept")

func test_skill_levels_clamped_to_max() -> void:
	var s := fx.skill()
	s.max_level = 5
	var c := fx.character()
	c.load_dict({"job": "t_job", "skills": {"t_skill": 99}, "essence": 0})
	check_eq(c.skills.learned[&"t_skill"], 5, "capped")

func test_unknown_job_keeps_current_job() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_no_such_job", "essence": 0, "base": {}})
	check_eq(c.job.id, &"t_job", "kept")

func test_missing_hp_and_mp_load_full() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_job", "essence": 0, "level": 2})
	check_eq(c.health.hp, c.max_hp(), "full HP")
	check_eq(c.mp, c.max_mp(), "full MP")
	check_eq(c.max_hp(), 70, "level 2: 50 + 2 × 10")

func test_save_with_an_old_appearance_loads_without_it() -> void:
	var c := fx.character()
	c.load_dict({"name": "Old", "job": "t_job", "essence": 3, "base": {},
		"appearance": {"skin": "", "face": "", "eyes": "", "hair": "hair_ponytail", "hair_color": ""}})
	check_eq([c.name, c.essence], ["Old", 3], "the rest loads")
	check(not c.to_dict().has("appearance"), "and the look is not saved again")

func test_save_from_before_essence_keeps_its_level_and_turns_points_into_essence() -> void:
	var c := fx.character()
	c.load_dict({"name": "Old", "job": "t_job", "level": 7, "xp": 100, "ap": 3, "sp": 2})
	check_eq([c.level, c.xp], [7, 100], "level and EXP kept")
	# 3 AP at 17 + 25 + 34, 2 skill levels at 17 + 31
	check_eq(c.essence, 76 + 48, "unspent points become essence")
	check(c.skills.learned.is_empty(), "no skills learned for it")
	var d := c.to_dict()
	check_eq([d["level"], d["xp"], d["essence"]], [7, 100, 124], "saved again with all three")

func test_old_stat_prices_climb_with_each_point_in_a_stat() -> void:
	# 17 × (1 + n / 5) ^ 2.1, rounded
	var want := {0: 17, 1: 25, 2: 34, 3: 46, 4: 58, 5: 73, 10: 171, 19: 458}
	for n in want:
		check_eq(CharacterCodec.old_stat_price(n), want[n], "point %d" % (n + 1))
	for n in range(0, 200):
		check(CharacterCodec.old_stat_price(n + 1) > CharacterCodec.old_stat_price(n), "point %d costs more than %d" % [n + 2, n + 1])
	check_eq(CharacterCodec.old_stat_price(-3), 17, "never below the first")

func test_save_with_base_stats_gets_the_essence_of_every_point_bought() -> void:
	var c := fx.character()
	c.load_dict({"name": "Old", "job": "t_job", "level": 5, "essence": 10,
		"base": {"strength": 14, "dexterity": 6, "intelligence": 5, "luck": 4, "charisma": 3}})
	# 2 STR at 17 + 25, 1 DEX at 17, 1 INT at 17: each stat priced from its own first
	check_eq(c.essence, 10 + 42 + 17 + 17, "essence back")
	check_eq(c.level, 5, "level kept")
	var start := fx.character()
	start.load_dict({"name": "New", "job": "t_job", "level": 3, "essence": 4, "base": CharacterCodec.OLD_START})
	check_eq(start.essence, 4, "nothing bought above the start, nothing back")

func test_save_from_without_levels_gets_a_level_per_five_stat_points() -> void:
	var c := fx.character()
	c.load_dict({"name": "Mid", "job": "t_job", "essence": 9, "base": {"strength": 20, "dexterity": 11}})
	check_eq([c.level, c.xp], [1 + 14 / CharacterCodec.OLD_POINTS_PER_LEVEL, 0], "a level for every 5 points bought")
	# 8 STR points (449) and 6 DEX points (253)
	check_eq(c.essence, 9 + 449 + 253, "essence kept, and the points' essence back")
	var big := fx.character()
	big.load_dict({"name": "Big", "job": "t_job", "essence": 0, "base": {"strength": 900}})
	check_eq(big.level, Character.MAX_LEVEL, "never past the cap")
	var again := fx.character()
	again.load_dict(c.to_dict())
	check_eq(again.level, c.level, "a newer save keeps its own level")
	check_eq(again.essence, c.essence, "and gets nothing back twice")

func test_save_from_before_essence_refunds_its_stats_and_prices_its_points() -> void:
	fx.skill()
	var c := fx.character()
	c.load_dict({"name": "Old", "job": "t_job", "level": 9, "xp": 0,
		"base": {"strength": 15}, "ap": 2, "skills": {"t_skill": 2}, "sp": 1})
	# 3 STR points back (17 + 25 + 34), 2 AP at 17 + 25, skill level 3 at 50
	check_eq(c.essence, 76 + 42 + 50, "every point as essence")
	check_eq(c.level, 9, "level kept")
	check_eq(c.skills.learned[&"t_skill"], 2, "skills kept")
	check_eq(c.skills.paid, {&"t_skill": 17 + 31}, "and priced as bought, so a job switch can hand it back")

func test_save_from_before_essence_prices_each_skill_in_turn() -> void:
	fx.skill(&"t_a")
	fx.skill(&"t_b")
	var c := fx.character()
	c.load_dict({"name": "Old", "job": "t_job", "level": 9, "skills": {"t_a": 1, "t_b": 2}})
	var paid := int(c.skills.paid[&"t_a"]) + int(c.skills.paid[&"t_b"])
	check_eq(paid, 17 + 31 + 50, "three levels at the first three prices")
	check_eq(c.skills.paid.size(), 2, "both priced")

func test_jobs_passed_survives_json() -> void:
	var c := fx.character()
	c.jobs_passed.assign(["t_next"])
	var back := Character.new()
	back.load_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check_eq(Array(back.jobs_passed), ["t_next"], "kept")
	check(back.has_passed(fx.job(&"t_next", &"t_warrior", &"t_job")), "and counts as passed")

func test_save_from_before_switching_counts_its_path_as_passed() -> void:
	var first := fx.job(&"t_job")
	fx.job(&"t_next", &"t_warrior", &"t_job")
	fx.job(&"t_other", &"t_mage", &"t_job")
	var blend := fx.job(&"t_blend", &"t_blends", &"t_next")
	blend.partner = &"t_other"
	var c := fx.character(first)
	c.load_dict({"name": "Old", "job": "t_next", "essence": 0, "base": {}})
	check_eq(Array(c.jobs_passed), ["t_next"], "its first job, not the Beginner")
	var b := fx.character(first)
	b.load_dict({"name": "Old", "job": "t_blend", "came_from": "t_other", "essence": 0, "base": {}})
	check_eq(Array(b.jobs_passed), ["t_blend", "t_other"], "a blend and the parent it came from")
	var fresh := fx.character(first)
	fresh.load_dict({"name": "Old", "job": "t_job", "essence": 0, "base": {}})
	check(fresh.jobs_passed.is_empty(), "a Beginner has passed nothing")
	var newer := fx.character(first)
	newer.load_dict({"name": "New", "job": "t_next", "essence": 0, "base": {}, "jobs_passed": []})
	check(newer.jobs_passed.is_empty(), "a newer save keeps its own list")

func test_save_with_base_stats_gets_its_points_back_once() -> void:
	var c := fx.character()
	c.load_dict({"name": "Old", "job": "t_job", "level": 7, "base": {"strength": 12, "dexterity": 8}, "ap": 2, "sp": 0})
	# 2 unspent AP (17 + 25), then 3 DEX points above the start back (17 + 25 + 34)
	check_eq(c.essence, 42 + 76, "every point's essence back")
	check(not c.to_dict().has("base"), "no base stats saved again")
	var again := fx.character()
	again.load_dict(c.to_dict())
	check_eq(again.essence, c.essence, "a newer save gets nothing back twice")

func test_save_from_before_skills_gets_potion_keys() -> void:
	var c := fx.character()
	c.job.starting_quickslots = [fx.use(&"t_red"), fx.use(&"t_blue")]
	c.load_dict({"name": "Old", "job": "t_job", "level": 4, "base": {"strength": 10}, "ap": 0})
	check_eq(c.quickslots[Character.QUICKSLOTS - 2], [&"item", &"t_red"], "first potion key")
	check_eq(c.quickslots[Character.QUICKSLOTS - 1], [&"item", &"t_blue"], "second potion key")

func test_oldest_save_with_only_name_and_level() -> void:
	var c := Character.new()
	c.load_dict({"name": "Ancient", "level": 3, "xp": 5})
	check_eq(c.job.id, Character.START_JOB, "beginner")
	check_eq([c.level, c.xp, c.essence], [3, 5, 0], "level and EXP kept")
	check_eq(c.map_id, Character.START_MAP, "start map")
	check_eq(c.health.hp, c.max_hp(), "full HP")
	check_eq(c.quickslots.size(), Character.QUICKSLOTS, "quickslots")

func test_short_or_bad_quickslots_are_padded() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_job", "essence": 0, "base": {}, "quickslots": [["skill", "t_a"], "junk", ["item"]]})
	check_eq(c.quickslots.size(), Character.QUICKSLOTS, "eight")
	check_eq(c.quickslots[0], [&"skill", &"t_a"], "kept")
	check_eq(c.quickslots[1], [], "junk cleared")
	check_eq(c.quickslots[2], [], "short entry cleared")
	check_eq(c.quickslots[7], [], "padded")

func test_hp_over_max_is_clamped() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_job", "essence": 0, "base": {}, "hp": 100000})
	check_eq(c.health.hp, c.max_hp(), "clamped")

func test_real_new_character_round_trip() -> void:
	var c := Character.create("Fresh")
	var back := Character.new()
	back.load_dict(c.to_dict())
	check_eq(back.to_dict(), c.to_dict(), "identical")

func test_server_load_keeps_an_old_saves_level() -> void:
	fx.job()
	var path := "user://t_old_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "Late", "job": "t_job", "level": 14, "xp": 50, "sp": 3}))
	f.close()
	var c := CharacterStore.load_file(path, "Late")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not check(c != null, "loads"):
		return
	check_eq(c.job.id, &"t_job", "job")
	check_eq([c.level, c.xp], [14, 50], "level and EXP")
	# 3 skill levels at 17 + 31 + 50
	check_eq(c.essence, 98, "SP as essence")
