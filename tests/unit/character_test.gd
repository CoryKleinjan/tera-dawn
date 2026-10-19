extends TestCase
## Character rules: hearts and Mana, recalc, damage from the weapon, skills known, buffs and
## their expiry, quickslots, storage, job advancement and switching, tallies, visited maps, pets,
## and a fresh character from real content.

var fx: UnitHelpers

func before_each() -> void:
	fx = UnitHelpers.new()

func after_each() -> void:
	fx.cleanup()

# ---------- hearts, Mana and recalc ----------

func test_spend_and_restore_mp() -> void:
	var c := fx.character()
	check_eq(c.mp, 0, "a new character's orb is empty")
	c.restore_mp(25)
	check(c.spend_mp(10), "can spend")
	check_eq(c.mp, 15, "spent")
	check(not c.spend_mp(16), "can't overspend")
	check_eq(c.mp, 15, "unchanged on failure")
	check(c.spend_mp(15), "can spend to zero")
	c.restore_mp(1000)
	check_eq(c.mp, c.max_mp(), "restore capped")
	c.restore_mp(-1000)
	check_eq(c.mp, 0, "never negative")

func test_gear_adds_no_hearts_or_mana() -> void:
	var c := fx.character()
	c.equipment.put(&"armor", ItemStack.exact(fx.equip(&"t_hat", EquipDef.Slot.ARMOR, {"max_hp": 100, "max_mp": 50})))
	check_eq(c.max_hp(), CharacterStats.BASE_HEARTS, "hearts")
	check_eq(c.max_mp(), CharacterStats.BASE_MANA, "Mana")

func test_shards_add_hearts_and_mana() -> void:
	var c := fx.character()
	c.heart_shards = CharacterStats.HEART_SHARDS_PER_HEART
	c.mana_shards = CharacterStats.MANA_SHARDS_PER_ORB
	check_eq(c.max_hp(), CharacterStats.BASE_HEARTS + 1, "a heart more")
	check_eq(c.max_mp(), CharacterStats.BASE_MANA + CharacterStats.MANA_PER_ORB, "a bigger orb")

func test_healing_spends_mana_on_one_heart() -> void:
	var c := fx.character()
	c.health.damage(2)
	c.mp = CharacterStats.HEAL_COST - 1
	check(not c.heal_heart(), "not enough Mana")
	c.mp = CharacterStats.HEAL_COST * 3
	check(c.heal_heart(), "healed")
	check_eq(c.health.hp, CharacterStats.BASE_HEARTS - 1, "one heart back")
	check_eq(c.mp, CharacterStats.HEAL_COST * 2, "paid")
	check(c.heal_heart(), "healed again")
	check(not c.heal_heart(), "nothing missing to heal")
	check_eq(c.mp, CharacterStats.HEAL_COST, "kept when there's nothing to heal")

func test_recalc_emits_stats_changed() -> void:
	var c := fx.character()
	var n := [0]
	c.stats_changed.connect(func() -> void: n[0] += 1)
	c.recalc()
	check_eq(n[0], 1, "emitted")

func test_recalc_without_job_does_nothing() -> void:
	var c := Character.new()
	c.recalc()
	check(c.job == null, "no crash without a job")

func test_damage_range_comes_from_the_weapons_attack() -> void:
	var c := fx.character()
	check_eq(c.damage_range(), Vector2i(1, 1), "bare hands still hit for 1")
	c.equipment.put(&"weapon", ItemStack.exact(fx.equip(&"t_a", EquipDef.Slot.WEAPON, {"attack": 10})))
	check_eq(c.damage_range(), Vector2i(14, 20), "top: 10 attack × 2; bottom: 70% of the top")
	c.equipment.put(&"weapon", ItemStack.exact(fx.equip(&"t_wand", EquipDef.Slot.WEAPON, {"attack": 3, "magic_attack": 7})))
	check_eq(c.damage_range(), Vector2i(10, 14), "a wand hits with its Magic Attack, the bigger of the two")

# ---------- skills ----------

func test_job_path_walks_back_through_advances() -> void:
	var first := fx.job(&"t_job")
	var second := fx.job(&"t_second", &"t_family", &"t_job")
	var third := fx.job(&"t_third", &"t_family", &"t_second")
	var c := fx.character(third)
	check_eq(Array(c.job_path()), [&"t_third", &"t_second", &"t_job"], "whole path")
	check_eq(Array(fx.character(first).job_path()), [&"t_job"], "first job alone")
	second.advances_from = &"t_third"
	check_eq(c.job_path().size(), 2, "a loop stops instead of hanging")


func test_skill_level_innate_and_null() -> void:
	var c := fx.character()
	var s := fx.skill()
	check_eq(c.skills.level(null), 0, "null")
	check_eq(c.skills.level(s), 0, "unlearned")
	s.innate = true
	check_eq(c.skills.level(s), 1, "innate is at least 1")

func test_passive_adds_stats_and_regen() -> void:
	var c := fx.character()
	var p := fx.skill(&"t_passive", SkillDef.Kind.PASSIVE)
	p.stats = UnitHelpers.stats({"accuracy": 2})
	p.stats_per_level = UnitHelpers.stats({"accuracy": 1})
	p.regen_hp = 5
	p.regen_hp_per_level = 2
	p.regen_mp = 1
	c.skills.learned[p.id] = 3
	c.recalc()
	check_eq(c.stats.accuracy, 2 + 2, "passive level 3: +4 accuracy")
	check_eq(c.skills.regen_bonus(), Vector2i(9, 1), "regen at level 3")

func test_use_problem_rules() -> void:
	var c := fx.character()
	var s := fx.skill()
	s.mp_cost = 10
	check_ne(c.skills.use_problem(null), "", "null")
	check_ne(c.skills.use_problem(s), "", "unlearned")
	c.skills.learned[s.id] = 1
	c.mp = 10
	check_eq(c.skills.use_problem(s), "", "usable")
	c.mp = 9
	check_ne(c.skills.use_problem(s), "", "not enough MP")
	c.mp = 10
	s.weapons = [&"bow"]
	check_ne(c.skills.use_problem(s), "", "no weapon")
	var sword := fx.equip(&"t_sword")
	sword.weapon_kind = &"sword"
	c.equipment.put(&"weapon", ItemStack.exact(sword))
	check_ne(c.skills.use_problem(s), "", "wrong weapon")
	sword.weapon_kind = &"bow"
	check_eq(c.skills.use_problem(s), "", "right weapon")
	var p := fx.skill(&"t_passive", SkillDef.Kind.PASSIVE)
	c.skills.learned[p.id] = 1
	check_ne(c.skills.use_problem(p), "", "passives can't be used")

func test_basic_attack_follows_weapon() -> void:
	var c := fx.character()
	check_eq(c.skills.basic_attack().id, Character.BASIC_ATTACK, "plain swing")
	var shot := fx.skill(&"t_shot")
	shot.innate = true
	var bow := fx.equip(&"t_bow")
	bow.basic_attack = shot
	c.equipment.put(&"weapon", ItemStack.exact(bow))
	check(c.skills.basic_attack() == shot, "bow's own shot")
	check_eq(c.skills.use_problem(shot), "", "can shoot")
	check_ne(c.skills.use_problem(Content.skill(Character.BASIC_ATTACK)), "", "plain swing not with a bow")

# ---------- buffs ----------

func _buff(seconds := 2.0) -> SkillDef:
	var b := fx.skill(&"t_buff", SkillDef.Kind.BUFF)
	b.stats = UnitHelpers.stats({"attack": 5, "speed": 10})
	b.stats_per_level = UnitHelpers.stats({"attack": 1})
	b.duration = seconds
	b.duration_per_level = 1.0
	return b

func test_buff_adds_stats_and_duration() -> void:
	var c := fx.character()
	var b := _buff(2.0)
	c.skills.learned[b.id] = 3
	c.skills.add_buff(b)
	check_eq(c.skills.buffs[b.id], [3, 240], "level 3 lasts 4 s = 240 ticks")
	check_eq(c.stats.attack, 7, "5 + 2 attack")
	check_eq(c.stats.speed, 10, "speed")

func test_tick_buffs_counts_down_then_expires() -> void:
	var c := fx.character()
	var b := _buff(1.0)
	c.skills.learned[b.id] = 1
	c.skills.add_buff(b)
	check_eq(c.skills.tick_buffs(59).size(), 0, "not yet")
	check_eq(c.skills.buffs[b.id][1], 1, "one tick left")
	check_eq(c.stats.attack, 5, "still on")
	var ended := c.skills.tick_buffs()
	check_eq(ended.size(), 1, "ended")
	check(ended[0] == b, "the buff skill returned")
	check(not c.skills.buffs.has(b.id), "removed")
	check_eq(c.stats.attack, 0, "stats gone")
	check_eq(c.skills.tick_buffs(100).size(), 0, "nothing more ends")

func test_big_tick_ends_buff_at_once() -> void:
	var c := fx.character()
	var b := _buff(1.0)
	c.skills.learned[b.id] = 1
	c.skills.add_buff(b)
	check_eq(c.skills.tick_buffs(10000).size(), 1, "overshoot ends it")

func test_recasting_refreshes_duration() -> void:
	var c := fx.character()
	var b := _buff(1.0)
	c.skills.learned[b.id] = 1
	c.skills.add_buff(b)
	c.skills.tick_buffs(50)
	c.skills.add_buff(b)
	check_eq(c.skills.buffs[b.id][1], 60, "back to full")
	check_eq(c.stats.attack, 5, "not stacked")

func test_buffs_expire_separately() -> void:
	var c := fx.character()
	var a := _buff(1.0)
	var b := fx.skill(&"t_buff2", SkillDef.Kind.BUFF)
	b.stats = UnitHelpers.stats({"defense": 3})
	b.duration = 2.0
	c.skills.learned[a.id] = 1
	c.skills.learned[b.id] = 1
	c.skills.add_buff(a)
	c.skills.add_buff(b)
	check_eq(c.skills.tick_buffs(60).size(), 1, "short one ends")
	check_eq(c.stats.defense, 3, "long one still on")
	check_eq(c.skills.tick_buffs(60).size(), 1, "long one ends")
	check_eq(c.stats.defense, 0, "both gone")

func test_buff_of_unknown_skill_expires_silently() -> void:
	var c := fx.character()
	c.skills.buffs[&"t_gone"] = [1, 5]
	check_eq(c.skills.tick_buffs(5).size(), 0, "nothing to report")
	check(c.skills.buffs.is_empty(), "but it's removed")

func test_skill_def_level_math() -> void:
	var s := fx.skill()
	s.mp_cost = 4
	s.mp_cost_per_level = 0.3
	s.damage_multiplier = 1.6
	s.damage_per_level = 0.08
	check_eq(s.mp_at(1), 4, "MP level 1")
	check_eq(s.mp_at(11), 7, "MP level 11")
	check_near(s.damage_at(1), 1.6, "damage level 1")
	check_near(s.damage_at(11), 2.4, "damage level 11")
	check_near(s.damage_at(0), 1.6, "level 0 treated as 1")
	check_eq(s.regen_hp_at(0), 0, "no regen unlearned")

func test_skill_def_regen_per_level() -> void:
	var s := fx.skill(&"t_regen", SkillDef.Kind.PASSIVE)
	s.regen_hp = 5
	s.regen_hp_per_level = 2
	s.regen_mp = 3
	s.regen_mp_per_level = 1
	check_eq(s.regen_hp_at(1), 5, "HP level 1")
	check_eq(s.regen_hp_at(4), 11, "HP level 4")
	check_eq(s.regen_mp_at(0), 0, "no MP regen unlearned")
	check_eq(s.regen_mp_at(1), 3, "MP level 1")
	check_eq(s.regen_mp_at(10), 12, "MP level 10")

func test_skill_flash_color_defaults_until_set() -> void:
	var s := fx.skill()
	check_eq(s.flash_color(), SkillDef.DEFAULT_FLASH, "no colour set: the default flash")
	s.flash = Color(0.4, 0.6, 1.0)
	check_eq(s.flash_color(), Color(0.4, 0.6, 1.0), "its own colour once set")
	s.flash = Color(0.4, 0.6, 1.0, 0.0)
	check_eq(s.flash_color(), SkillDef.DEFAULT_FLASH, "a see-through colour counts as unset")

func test_skill_describe_level_lines() -> void:
	var s := fx.skill()
	s.mp_cost = 6
	s.damage_multiplier = 1.5
	s.hits = 2
	s.max_targets = 3
	check_eq(Array(s.describe_level(0)), [], "nothing at level 0")
	check_eq(Array(s.describe_level(1)), ["MP cost: 6", "Damage: 150% x2 hits, up to 3 monsters"], "an attack")
	s.magic = true
	check_eq(s.describe_level(1)[1], "Magic: 150% x2 hits, up to 3 monsters", "a spell says Magic")

func test_skill_describe_level_buff_and_passive() -> void:
	var buff := fx.skill(&"t_buff", SkillDef.Kind.BUFF)
	buff.stats = UnitHelpers.stats({"attack": 5})
	buff.duration = 30.0
	check_eq(Array(buff.describe_level(1)), ["Weapon Attack +5", "Lasts 30 seconds"], "a free buff")
	var passive := fx.skill(&"t_passive", SkillDef.Kind.PASSIVE)
	passive.mp_cost = 9
	passive.regen_mp = 4
	check_eq(Array(passive.describe_level(1)), ["MP recovery +4"], "a passive shows no MP cost")

# ---------- quickslots ----------

func test_quickslots_set_swap_and_clear() -> void:
	var c := fx.character()
	check_eq(c.quickslots.size(), Character.QUICKSLOTS, "eight slots")
	c.set_quickslot(0, &"skill", &"t_a")
	c.set_quickslot(1, &"item", &"t_b")
	c.set_quickslot(1, &"skill", &"t_a")
	check_eq(c.quickslots[1], [&"skill", &"t_a"], "moved")
	check_eq(c.quickslots[0], [&"item", &"t_b"], "swapped back")
	c.set_quickslot(0, &"", &"")
	check_eq(c.quickslots[0], [], "cleared")
	c.set_quickslot(-1, &"item", &"t_x")
	c.set_quickslot(Character.QUICKSLOTS, &"item", &"t_x")
	check_eq(c.quickslots.count([&"item", &"t_x"]), 0, "out of range ignored")

func test_setting_same_slot_again_is_stable() -> void:
	var c := fx.character()
	c.set_quickslot(3, &"skill", &"t_a")
	c.set_quickslot(3, &"skill", &"t_a")
	check_eq(c.quickslots[3], [&"skill", &"t_a"], "still there")
	check_eq(c.quickslots.count([]), Character.QUICKSLOTS - 1, "only one slot used")

# ---------- storage ----------

func test_store_charges_fee_and_moves_stack() -> void:
	var c := fx.character()
	var x := fx.etc()
	c.inventory.add(x, 7)
	c.shards = Character.STORE_FEE + 5
	check_eq(c.store(ItemDef.Tab.ETC, 0), "", "stored")
	check_eq(c.shards, 5, "fee paid")
	check_eq(c.inventory.count_of(x), 0, "left the bag")
	check_eq(c.storage.count_of(x), 7, "in storage")
	check_eq(c.retrieve(ItemDef.Tab.ETC, 0), "", "retrieved free")
	check_eq(c.inventory.count_of(x), 7, "back")
	check_eq(c.shards, 5, "no fee to take out")

func test_store_refusals() -> void:
	var c := fx.character()
	var q := fx.etc(&"t_quest_item")
	q.quest_item = true
	c.inventory.add(q, 1)
	c.inventory.add(fx.use(), 1)
	c.shards = 1000
	check_ne(c.store(ItemDef.Tab.ETC, 0), "", "quest items can't be stored")
	c.shards = Character.STORE_FEE - 1
	check_ne(c.store(ItemDef.Tab.USE, 0), "", "can't pay")
	check_eq(c.shards, Character.STORE_FEE - 1, "nothing charged")
	check_eq(c.store(ItemDef.Tab.USE, 5), "", "empty slot is a no-op")
	c.shards = 1000
	c.storage.add(fx.use(&"t_other", 1), Inventory.SLOTS)
	check_ne(c.store(ItemDef.Tab.USE, 0), "", "storage full")
	check_eq(c.shards, 1000, "nothing charged")

func test_retrieve_needs_room() -> void:
	var c := fx.character()
	var x := fx.etc(&"t_etc", 1)
	c.storage.add(x, 1)
	c.inventory.add(fx.etc(&"t_other", 1), Inventory.SLOTS)
	check_ne(c.retrieve(ItemDef.Tab.ETC, 0), "", "bag full")
	check_eq(c.storage.count_of(x), 1, "still stored")

# ---------- job advancement ----------

func _advance_setup() -> Array:
	var first := fx.job(&"t_job")
	var next := fx.job(&"t_next", &"t_warrior", &"t_job")
	var c := fx.character(first)
	return [c, next]

func test_advance_refuses_the_job_you_are() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	check_eq(c.advance_problem(c.job), "You're already a T Job.", "a Beginner")
	next.display_name = "Archer"
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.advance_problem(next), "You're already an Archer.", "an before a vowel")
	check_eq(c.advance(next), "You're already an Archer.", "advance refused")

func test_advance_only_where_the_job_opens() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var first := c.job
	fx.job(&"t_other", &"t_mage", &"t_job")
	var blend := fx.job(&"t_blend", &"t_blends", &"t_next")
	blend.partner = &"t_other"
	check(not c.can_become(blend), "a Beginner can't skip to a blend")
	check_eq(c.advance(blend), "A T Job can't become a T Blend.", "advance refused")
	check_eq(c.job.id, &"t_job", "job unchanged")
	check(c.can_become(next), "a first job is open")
	check_eq(c.advance(next), "", "advanced")
	check(c.can_become(blend), "a parent can become the blend")
	check(not c.can_become(first), "nobody goes back to being a Beginner")

func test_advance_changes_job_gives_gifts_and_refills() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var sword := fx.equip(&"t_gift_sword", EquipDef.Slot.WEAPON, {"attack": 17}, 5)
	var scroll := fx.use(&"t_scroll")
	next.advance_gifts = [UnitHelpers.drop(sword), UnitHelpers.drop(scroll, 20)]
	c.health.damage(3)
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.job.id, &"t_next", "new job")
	check_eq(c.health.hp, c.max_hp(), "refilled")
	check_eq(c.gear.weapon(), sword, "the gift weapon is worn")
	check_eq(c.equipment.at(&"weapon").stats.attack, 17, "gift gear unrolled")
	check_eq(c.inventory.count_of(scroll), 20, "scrolls")
	check_eq(Array(c.job_path()), [&"t_next", &"t_job"], "path")

func test_advance_needs_room_for_gifts() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	next.advance_gifts = [UnitHelpers.drop(fx.equip(&"t_gift"))]
	c.inventory.add(fx.equip(&"t_junk"), Inventory.SLOTS)
	check_ne(c.advance(next), "", "no room")
	check_eq(c.job.id, &"t_job", "not advanced")

func test_advance_swaps_a_beginner_weapon_for_the_gift() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var stick := fx.equip(&"t_stick")
	var gift := fx.equip(&"t_gift_blade")
	gift.jobs = [&"t_warrior"]
	c.equipment.put(&"weapon", ItemStack.exact(stick))
	next.advance_gifts = [UnitHelpers.drop(fx.use(&"t_scroll"), 5), UnitHelpers.drop(gift)]
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.gear.weapon(), gift, "the first weapon gift is worn, even after other gifts")
	check_eq(c.inventory.count_of(stick), 1, "the old weapon is in the bag")

func test_advance_keeps_a_weapon_of_the_new_line_on() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var found := fx.equip(&"t_found_blade")
	found.jobs = [&"t_warrior"]
	var gift := fx.equip(&"t_gift_blade")
	c.equipment.put(&"weapon", ItemStack.exact(found))
	next.advance_gifts = [UnitHelpers.drop(gift)]
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.gear.weapon(), found, "a weapon made for the job stays on")
	check_eq(c.inventory.count_of(gift), 1, "the gift goes to the bag")

func test_advance_leaves_a_gift_weapon_it_cant_wear_in_the_bag() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	var heavy := fx.equip(&"t_heavy")
	heavy.jobs = [&"t_mage"]
	next.advance_gifts = [UnitHelpers.drop(heavy)]
	check_eq(c.advance(next), "", "advanced")
	check_eq(c.gear.weapon(), null, "another line's weapon")
	check_eq(c.inventory.count_of(heavy), 1, "in the bag")

# ---------- switching jobs ----------

## A Warrior-like `next` (passed) and a Mage-like `other`, each with a Job Test and a gift of
## 20 scrolls.
func _switch_setup() -> Dictionary:
	var first := fx.job(&"t_job")
	var next := fx.job(&"t_next", &"t_warrior", &"t_job")
	var other := fx.job(&"t_other", &"t_mage", &"t_job")
	var scroll := fx.use(&"t_scroll")
	for j: JobDef in [next, other]:
		j.advance_quest = fx.quest(StringName("t_%s_test" % j.id))
		j.advance_gifts = [UnitHelpers.drop(scroll, 20)]
	var c := fx.character(first)
	c.quests.done[next.advance_quest.id] = true
	check_eq(c.advance(next), "", "became the first job")
	return {"c": c, "first": first, "next": next, "other": other, "scroll": scroll}

func test_advance_remembers_the_jobs_passed() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	check_eq(Array(c.jobs_passed), ["t_next"], "the first job is passed")
	check(c.has_passed(s["next"]), "has passed it")
	check(not c.has_passed(s["other"]), "not the other")
	check(c.can_become(s["other"]), "another first job is open")
	check(not c.can_become(s["next"]), "not the job you are")
	check(not c.can_become(s["first"]), "nor the Beginner")

func test_switching_needs_the_job_test_the_first_time() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	var other: JobDef = s["other"]
	check_eq(c.advance(other), "Pass the %s first." % other.advance_quest.title, "the Job Test first")
	check_eq(c.job, s["next"], "job unchanged")

func test_switching_the_first_time_gives_the_gifts() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	c.quests.done[s["other"].advance_quest.id] = true
	check_eq(c.advance(s["other"]), "", "switched")
	check_eq(c.job, s["other"], "the other job")
	check_eq(c.inventory.count_of(s["scroll"]), 40, "gifts of both jobs")
	check(c.has_passed(s["other"]), "now passed too")

func test_switching_back_is_free_and_gives_no_gifts_again() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	var next: JobDef = s["next"]
	var other: JobDef = s["other"]
	c.quests.done[other.advance_quest.id] = true
	check_eq(c.advance(other), "", "switched")
	c.quests.done.erase(next.advance_quest.id)
	c.quests.done.erase(other.advance_quest.id)
	var scrolls := c.inventory.count_of(s["scroll"])
	check_eq(c.advance_problem(next), "", "a job passed before needs no Job Test")
	check_eq(c.advance(next), "", "switched back")
	check_eq(c.job, next, "the first job again")
	check_eq(c.inventory.count_of(s["scroll"]), scrolls, "no second gifts")
	check_eq(Array(c.jobs_passed), ["t_next", "t_other"], "each job listed once")
	check_eq(c.advance(other), "", "and back again, free")

func test_switching_needs_no_room_for_gifts_once_passed() -> void:
	var s := _switch_setup()
	var c: Character = s["c"]
	c.quests.done[s["other"].advance_quest.id] = true
	check_eq(c.advance(s["other"]), "", "switched")
	c.inventory.add(fx.use(&"t_junk", 1), Inventory.SLOTS)
	check_eq(c.advance(s["next"]), "", "a full Use tab doesn't matter: no gifts come")

# ---------- tallies, maps, pets ----------

func test_count_tallies() -> void:
	var c := fx.character()
	c.count(Counters.DEALS)
	c.count(Counters.DEALS, 3)
	c.count(Counters.SAT, 0)
	check_eq(c.counters[Counters.DEALS], 4, "added up")
	check_eq(c.counters[Counters.SAT], 0, "zero recorded")

func test_visit_only_new_maps() -> void:
	var c := fx.character()
	check(c.visit(&"t_a"), "first time")
	check(not c.visit(&"t_a"), "second time")
	check(c.visit(&"t_b"), "another map")
	check_eq(Array(c.visited), ["t_a", "t_b"], "listed once each")

func test_pet_def_lookup() -> void:
	var c := fx.character()
	check(c.pet_def() == null, "no pet")
	var p := PetDef.new()
	p.id = &"t_pet"
	fx.register("items", p)
	c.pet = &"t_pet"
	check(c.pet_def() == p, "pet found")
	c.pet = &"t_etc"
	fx.etc()
	check(c.pet_def() == null, "not a pet")
	check_eq(p.tab(), ItemDef.Tab.SETUP, "pets in Setup")
	check_eq(p.stack_size(), 1, "pets don't stack")

# ---------- real content ----------

func test_create_beginner_from_content() -> void:
	var c := Character.create("Hero")
	var j := Content.job(&"beginner")
	check_eq(c.name, "Hero", "name")
	check(c.job == j, "beginner")
	check_eq(c.equipment.worn.size(), NewCharacter.new().starting_gear(j).size(), "starting gear and the creator's default outfit worn")
	for e in j.starting_gear:
		var worn: ItemStack = null
		for s: ItemStack in c.equipment.worn.values():
			if s.item == e:
				worn = s
		if not check(worn != null, "%s worn" % e.id):
			continue
		check_eq(worn.stats.to_dict(), e.stats.to_dict() if e.stats else {}, "%s exact stats" % e.id)
	for entry in j.starting_items:
		check_eq(c.inventory.count_of(entry.item), entry.min_amount, "%s given" % entry.item.id)
	for i in j.starting_quickslots.size():
		check_eq(c.quickslots[Character.QUICKSLOTS - j.starting_quickslots.size() + i], [&"item", j.starting_quickslots[i].id], "%s on the last keys" % j.starting_quickslots[i].id)
	check_eq(c.health.hp, c.max_hp(), "every heart")
	check_eq(c.mp, 0, "an empty orb")
	check_eq(c.map_id, Character.NEW_MAP, "starts on the tutorial beach")

func test_real_beginner_can_reach_warrior() -> void:
	var c := Character.create("Hero")
	var w := Content.job(&"warrior")
	check_eq(c.advance_problem(w), "Pass the Job Test first.", "a new Beginner needs only the Job Test")
	c.quests.done[w.advance_quest.id] = true
	check_eq(c.advance_problem(w), "", "the test is enough")
	check_eq(c.advance(w), "", "advanced")
	check_eq(c.job.id, &"warrior", "warrior")

func test_advance_refused_when_gifts_need_more_slots_than_free() -> void:
	var setup := _advance_setup()
	var c: Character = setup[0]
	var next: JobDef = setup[1]
	next.advance_gifts = [UnitHelpers.drop(fx.equip(&"t_gift_a")), UnitHelpers.drop(fx.equip(&"t_gift_b"))]
	c.inventory.add(fx.equip(&"t_junk"), Inventory.SLOTS - 1)
	check_ne(c.advance(next), "", "two gear gifts, one free slot")
	check_eq(c.job.id, &"t_job", "not advanced")
