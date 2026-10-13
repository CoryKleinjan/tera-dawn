extends TestCase
## Character.to_dict / load_dict: a full round trip (gear rolled stats and scroll upgrades,
## skills, buffs, quickslots, buddies, fame, guild, Monster Book, pet, visited maps,
## achievements, tallies), bad values, and the older save formats load_dict still accepts.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

## Everything filled in with values that differ from a fresh character.
func _rich() -> Character:
	var c := fx.character(null, {"strength": 30, "dexterity": 12, "luck": 4})
	c.name = "Saver"
	c.level = 12
	c.xp = 345
	c.shards = 9876
	c.ap.points = 4
	c.ap.reset_used = true
	# every Skill Point Lv 12 earned (11 levels × 3) less the 5 spent below
	c.skills.points = 28
	c.map_id = Content.maps.keys()[0]
	var sword := fx.equip(&"t_sword", EquipDef.Slot.WEAPON, {"attack": 20}, 3)
	var worn := ItemStack.exact(sword)
	worn.stats.attack = 23
	worn.slots_used = 3
	worn.upgrades = 2
	c.equipment.put(&"weapon", worn)
	var bagged := ItemStack.exact(fx.equip(&"t_ring", EquipDef.Slot.RING, {"luck": 3}))
	bagged.stats.luck = 4
	c.inventory.put(ItemDef.Tab.EQUIP, 6, bagged)
	c.inventory.add(fx.use(), 42)
	c.storage.add(fx.etc(), 9)
	var passive := fx.skill(&"t_passive", SkillDef.Kind.PASSIVE)
	passive.stats = UnitHelpers.stats({"defense": 7})
	passive.max_level = 20
	var buff := fx.skill(&"t_buff", SkillDef.Kind.BUFF)
	buff.stats = UnitHelpers.stats({"attack": 4})
	buff.max_level = 20
	buff.duration = 30.0
	c.skills.learned[passive.id] = 3
	c.skills.learned[buff.id] = 2
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
	check_eq(b.level, 12, "level")
	check_eq(b.xp, 345, "xp")
	check_eq(b.shards, 9876, "shards")
	check_eq(b.ap.points, 4, "AP")
	check(b.ap.reset_used, "free AP reset used")
	check_eq(b.skills.points, 28, "SP")
	check_eq(b.map_id, c.map_id, "map")
	check(b.job == c.job, "job")
	check_eq(b.base.to_dict(), c.base.to_dict(), "base stats")
	check_eq(b.health.hp, 50, "HP")
	check_eq(b.mp, 17, "MP")

func test_round_trip_gear_keeps_rolled_stats_and_upgrades() -> void:
	var b := _round_trip(_rich())
	var w := b.equipment.at(&"weapon")
	check_eq(w.stats.attack, 23, "rolled attack")
	check_eq(w.slots_used, 3, "slots used")
	check_eq(w.upgrades, 2, "upgrades")
	check_eq(w.slots_left(), 4, "slots left")
	check_eq(b.inventory.at(ItemDef.Tab.EQUIP, 6).stats.luck, 4, "bag gear rolled stats and slot")
	check_eq(b.stats.attack, 23 + 4, "worn gear and buff count in totals")

func test_round_trip_items_and_storage() -> void:
	var b := _round_trip(_rich())
	check_eq(b.inventory.count_of(Content.item(&"t_use")), 42, "potions")
	check_eq(b.storage.count_of(Content.item(&"t_etc")), 9, "storage")

func test_round_trip_skills_buffs_and_quickslots() -> void:
	var b := _round_trip(_rich())
	check_eq(b.skills.learned, {&"t_passive": 3, &"t_buff": 2}, "skills")
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
		"job": "t_job", "level": -4, "xp": -10, "shards": -1, "map_id": "t_nowhere",
		"base": {}, "ap": -3, "sp": -2,
		"skills": {"t_gone": 3},
		"buffs": {"t_gone": [1, 50], "t_job": "bad"},
		"pet": "t_etc", "pet_full": 500, "hp": 0, "mp": 99999,
	})
	check_eq(c.level, 1, "level floor")
	check_eq(c.xp, 0, "xp floor")
	check_eq(c.shards, 0, "shards floor")
	check_eq(c.map_id, Character.START_MAP, "unknown map: start map")
	check_eq(c.ap.points, 0, "AP floor")
	check_eq(c.skills.points, 0, "SP floor")
	check(c.skills.learned.is_empty(), "unknown skill dropped")
	check(c.skills.buffs.is_empty(), "bad buffs dropped")
	check_eq(c.pet, &"", "not a pet")
	check_eq(c.pet_full, 100, "fullness capped")
	check_eq(c.health.hp, 1, "loads with at least 1 HP")
	check_eq(c.mp, c.max_mp(), "MP capped")

func test_skill_levels_clamped_to_max() -> void:
	var s := fx.skill()
	s.max_level = 5
	var c := fx.character()
	c.load_dict({"job": "t_job", "skills": {"t_skill": 99}, "sp": 0})
	check_eq(c.skills.learned[&"t_skill"], 5, "capped")

func test_unknown_job_keeps_current_job() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_no_such_job", "sp": 0, "base": {}})
	check_eq(c.job.id, &"t_job", "kept")

func test_missing_hp_and_mp_load_full() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_job", "level": 3, "base": {}, "sp": 0})
	check_eq(c.health.hp, c.max_hp(), "full HP")
	check_eq(c.mp, c.max_mp(), "full MP")
	check_eq(c.max_hp(), 80, "level 3 max HP")

func test_save_from_before_stats_hands_out_ap() -> void:
	var c := fx.character()
	c.load_dict({"name": "Old", "job": "t_job", "level": 7, "sp": 0})
	check_eq(c.ap.points, 30, "6 levels × 5 AP")

func test_save_from_before_skills_hands_out_sp_and_potion_keys() -> void:
	var c := fx.character()
	c.job.starting_quickslots = [fx.use(&"t_red"), fx.use(&"t_blue")]
	fx.skill(&"t_cut")
	c.load_dict({"name": "Old", "job": "t_job", "level": 4, "base": {"strength": 10}, "ap": 0})
	check_eq(c.skills.points, 9, "3 levels × 3 SP")
	check_eq(c.quickslots[Character.QUICKSLOTS - 2], [&"item", &"t_red"], "first potion key")
	check_eq(c.quickslots[Character.QUICKSLOTS - 1], [&"item", &"t_blue"], "second potion key")

func test_oldest_save_with_only_name_and_level() -> void:
	var c := Character.new()
	c.load_dict({"name": "Ancient", "level": 3, "xp": 5})
	check_eq(c.job.id, Character.START_JOB, "beginner")
	check_eq(c.ap.points, 2 * c.job.ap_per_level, "AP for the levels")
	check_eq(c.skills.points, 2 * c.job.sp_per_level, "SP for the levels")
	check_eq(c.map_id, Character.START_MAP, "start map")
	check_eq(c.health.hp, c.max_hp(), "full HP")
	check_eq(c.quickslots.size(), Character.QUICKSLOTS, "quickslots")

func test_short_or_bad_quickslots_are_padded() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_job", "sp": 0, "base": {}, "quickslots": [["skill", "t_a"], "junk", ["item"]]})
	check_eq(c.quickslots.size(), Character.QUICKSLOTS, "eight")
	check_eq(c.quickslots[0], [&"skill", &"t_a"], "kept")
	check_eq(c.quickslots[1], [], "junk cleared")
	check_eq(c.quickslots[2], [], "short entry cleared")
	check_eq(c.quickslots[7], [], "padded")

func test_hp_over_max_is_clamped() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_job", "sp": 0, "base": {}, "hp": 100000})
	check_eq(c.health.hp, c.max_hp(), "clamped")

func test_real_new_character_round_trip() -> void:
	var c := Character.create("Fresh")
	var back := Character.new()
	back.load_dict(c.to_dict())
	check_eq(back.to_dict(), c.to_dict(), "identical")
