extends TestCase
## Character.to_dict / load_dict: a full round trip (gear rolled stats, jobs passed, skills,
## buffs, quickslots, Monster Book, pet, visited maps, achievements,
## tallies, hearts and Mana), bad values, and older saves, whose levels, EXP, Dawn Essence
## and stat points load as nothing.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

## Everything filled in with values that differ from a fresh character.
func _rich() -> Character:
	var c := fx.character()
	c.name = "Saver"
	c.look = &"wanderer"
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
	var scroll := fx.use()
	c.inventory.add(scroll, 42)
	c.storage.add(fx.etc(), 9)
	var passive := fx.skill(&"t_passive", SkillDef.Kind.PASSIVE)
	passive.stats = UnitHelpers.stats({"defense": 7})
	var buff := fx.skill(&"t_buff", SkillDef.Kind.BUFF)
	buff.stats = UnitHelpers.stats({"attack": 4})
	buff.duration = 30.0
	c.skills.learned[passive.id] = 3
	c.skills.learned[buff.id] = 2
	c.skills.buffs[buff.id] = [2, 500]
	c.set_quickslot(0, &"skill", buff.id)
	c.set_quickslot(Character.QUICKSLOTS - 2, &"item", scroll.id)
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
	c.heart_shards = 5
	c.mana_shards = 2
	c.recalc()
	c.health.set_hp(3)
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
	check_eq(b.look, &"wanderer", "look")
	check_eq(b.shards, 9876, "shards")
	check_eq(Array(b.jobs_passed), ["t_next", "t_other"], "jobs passed")
	check_eq(b.map_id, c.map_id, "map")
	check(b.job == c.job, "job")
	check_eq(b.damage_range(), c.damage_range(), "damage")
	check_eq(b.health.hp, 3, "hearts")
	check_eq(b.mp, 17, "Mana")
	check_eq([b.heart_shards, b.mana_shards], [5, 2], "Heart and Mana Shards")
	check_eq(b.max_hp(), CharacterStats.BASE_HEARTS + 1, "a heart from the shards")

func test_round_trip_gear_keeps_rolled_stats() -> void:
	var b := _round_trip(_rich())
	var w := b.equipment.at(&"weapon")
	check_eq(w.stats.attack, 23, "rolled attack")
	check_eq(b.inventory.at(ItemDef.Tab.EQUIP, 6).stats.avoid, 4, "bag gear rolled stats and slot")
	check_eq(b.stats.attack, 23 + 4, "worn gear and buff count in totals")

func test_round_trip_items_and_storage() -> void:
	var b := _round_trip(_rich())
	check_eq(b.inventory.count_of(Content.item(&"t_use")), 42, "usable items")
	check_eq(b.storage.count_of(Content.item(&"t_etc")), 9, "storage")

func test_round_trip_skills_buffs_and_quickslots() -> void:
	var b := _round_trip(_rich())
	check_eq(b.skills.learned, {&"t_passive": 3, &"t_buff": 2}, "skills")
	check_eq(b.skills.buffs, {&"t_buff": [2, 500]}, "buffs")
	check_eq(b.quickslots[0], [&"skill", &"t_buff"], "skill quickslot")
	check_eq(b.quickslots[Character.QUICKSLOTS - 2], [&"item", &"t_use"], "item quickslot")
	check_eq(b.stats.defense, 7, "passive applied")

func test_round_trip_social_book_pet_and_tallies() -> void:
	var b := _round_trip(_rich())
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

func test_save_has_no_levels_essence_or_points() -> void:
	var d := _rich().to_dict()
	for gone in ["level", "xp", "essence", "skills_paid", "ap", "sp", "ap_reset_used", "base", "stat_rules"]:
		check(not d.has(gone), "no %s" % gone)

func test_save_is_stable() -> void:
	var c := _rich()
	var once := c.to_dict()
	check_eq(_round_trip(c).to_dict(), once, "saving a loaded save changes nothing")

func test_to_dict_does_not_share_lists() -> void:
	var c := _rich()
	var d := c.to_dict()
	d["counters"]["deals"] = 100
	check_eq(c.counters["deals"], 3, "counters untouched")

func test_bad_values_are_clamped_or_ignored() -> void:
	var c := fx.character()
	c.load_dict({
		"job": "t_job", "shards": -1, "map_id": "t_nowhere",
		"skills": {"t_gone": 3},
		"buffs": {"t_gone": [1, 50], "t_job": "bad"},
		"pet": "t_etc", "pet_full": 500, "hp": 0, "mp": 99999, "heart_shards": -3, "mana_shards": -1,
	})
	check_eq(c.shards, 0, "shards floor")
	check_eq(c.map_id, Character.START_MAP, "unknown map: start map")
	check(c.skills.learned.is_empty(), "unknown skill dropped")
	check(c.skills.buffs.is_empty(), "bad buffs dropped")
	check_eq(c.pet, &"", "not a pet")
	check_eq(c.pet_full, 100, "fullness capped")
	check_eq(c.health.hp, 1, "loads with at least 1 heart")
	check_eq(c.mp, c.max_mp(), "Mana capped")
	check_eq([c.heart_shards, c.mana_shards], [0, 0], "shards floored")

func test_a_skill_or_item_gone_from_the_game_is_dropped() -> void:
	fx.skill()
	var c := fx.character()
	c.load_dict({"job": "t_job", "skills": {"t_skill": 1, "t_gone": 2},
		"quickslots": [["skill", "t_gone"], ["skill", "t_skill"], ["item", "t_gone_potion"]]})
	check(not c.skills.learned.has(&"t_gone"), "dropped")
	check_eq(c.skills.learned[&"t_skill"], 1, "a known skill kept")
	check_eq(c.quickslots[0], [], "its quickslot emptied")
	check_eq(c.quickslots[1], [&"skill", &"t_skill"], "others kept")
	check_eq(c.quickslots[2], [], "a gone item's quickslot emptied")

func test_skill_levels_clamped_to_max() -> void:
	var s := fx.skill()
	s.max_level = 5
	var c := fx.character()
	c.load_dict({"job": "t_job", "skills": {"t_skill": 99}})
	check_eq(c.skills.learned[&"t_skill"], 5, "capped")

func test_unknown_job_keeps_current_job() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_no_such_job"})
	check_eq(c.job.id, &"t_job", "kept")

func test_a_save_from_before_hearts_loads_with_every_heart() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_job", "level": 2, "hp": 37, "mp": 80})
	check_eq(c.max_hp(), CharacterStats.BASE_HEARTS, "five hearts")
	check_eq(c.health.hp, c.max_hp(), "every heart, whatever HP it had")
	check_eq(c.mp, 0, "an empty orb")

func test_save_with_an_old_appearance_loads_without_it() -> void:
	var c := fx.character()
	c.load_dict({"name": "Old", "job": "t_job",
		"appearance": {"skin": "", "face": "", "eyes": "", "hair": "hair_ponytail", "hair_color": ""}})
	check_eq(c.name, "Old", "the rest loads")
	check(not c.to_dict().has("appearance"), "and the old appearance is not saved again")
	check_eq(c.look, HeroLookDef.all()[0].id, "a save from before the looks gets the first one")

func test_a_look_the_game_does_not_know_loads_as_the_first() -> void:
	var c := fx.character()
	c.load_dict({"name": "Odd", "job": "t_job", "look": "dragon"})
	check_eq(c.look, HeroLookDef.all()[0].id, "the first look")

func test_save_with_levels_and_essence_loads_without_them() -> void:
	fx.skill()
	var c := fx.character()
	c.load_dict({"name": "Old", "job": "t_job", "level": 7, "xp": 100, "essence": 345, "ap": 3, "sp": 2,
		"base": {"strength": 15}, "skills": {"t_skill": 2}, "skills_paid": {"t_skill": 48}})
	check_eq(c.name, "Old", "the rest loads")
	check_eq(c.skills.learned[&"t_skill"], 2, "skills still in the game kept")
	var d := c.to_dict()
	for gone in ["level", "xp", "essence", "ap", "sp", "base", "skills_paid"]:
		check(not d.has(gone), "%s not saved again" % gone)

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
	c.load_dict({"name": "Old", "job": "t_next"})
	check_eq(Array(c.jobs_passed), ["t_next"], "its first job, not the Beginner")
	var b := fx.character(first)
	b.load_dict({"name": "Old", "job": "t_blend", "came_from": "t_other"})
	check_eq(Array(b.jobs_passed), ["t_blend", "t_other"], "a blend and the parent it came from")
	var fresh := fx.character(first)
	fresh.load_dict({"name": "Old", "job": "t_job"})
	check(fresh.jobs_passed.is_empty(), "a Beginner has passed nothing")
	var newer := fx.character(first)
	newer.load_dict({"name": "New", "job": "t_next", "jobs_passed": []})
	check(newer.jobs_passed.is_empty(), "a newer save keeps its own list")

func test_oldest_save_with_only_name_and_level() -> void:
	var c := Character.new()
	c.load_dict({"name": "Ancient", "level": 3, "xp": 5})
	check_eq(c.job.id, Character.START_JOB, "beginner")
	check_eq(c.map_id, Character.START_MAP, "start map")
	check_eq(c.health.hp, c.max_hp(), "full HP")
	check_eq(c.quickslots.size(), Character.QUICKSLOTS, "quickslots")

func test_short_or_bad_quickslots_are_padded() -> void:
	fx.skill(&"t_a")
	var c := fx.character()
	c.load_dict({"job": "t_job", "quickslots": [["skill", "t_a"], "junk", ["item"]]})
	check_eq(c.quickslots.size(), Character.QUICKSLOTS, "eight")
	check_eq(c.quickslots[0], [&"skill", &"t_a"], "kept")
	check_eq(c.quickslots[1], [], "junk cleared")
	check_eq(c.quickslots[2], [], "short entry cleared")
	check_eq(c.quickslots[7], [], "padded")

func test_hp_over_max_is_clamped() -> void:
	var c := fx.character()
	c.load_dict({"job": "t_job", "hp": 100000})
	check_eq(c.health.hp, c.max_hp(), "clamped")

func test_real_new_character_round_trip() -> void:
	var c := Character.create("Fresh")
	var back := Character.new()
	back.load_dict(c.to_dict())
	check_eq(back.to_dict(), c.to_dict(), "identical")

func test_server_load_reads_an_old_save() -> void:
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
	check_eq(c.name, "Late", "name")
	check(not c.to_dict().has("level"), "its level left out")
