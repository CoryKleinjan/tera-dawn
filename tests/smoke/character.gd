extends SmokeArea
## A character without the world: inventory, equipment, damage, saving, jobs and skills.

## Inventory, equipment, stats and saving, without the world.
func check() -> void:
	var c := Character.create("Tester")
	var sword: EquipDef = Content.item(&"training_sword")
	_check(c.equipment.at(&"weapon") != null and c.equipment.at(&"weapon").item == sword, "a new character wears the starting sword")
	var dmg := c.damage_range()
	_check(dmg.x > 0 and dmg.y >= dmg.x and dmg.y == roundi(sword.stats.attack * CharacterStats.DAMAGE_PER_ATTACK), "the damage range comes from the weapon's attack (%d ~ %d)" % [dmg.x, dmg.y])

	# stacking and a full tab
	var scroll: ItemDef = Content.item(&"return_scroll")
	c.inventory.add(scroll, 150)
	_check(c.inventory.count_of(scroll) == 150 and c.inventory.at(ItemDef.Tab.USE, 0).count == 100 and c.inventory.at(ItemDef.Tab.USE, 1).count == 50, "scrolls stack up to 100 a slot")
	var tusk: ItemDef = Content.item(&"boar_tusk")
	var left := c.inventory.add(tusk, 200 * Inventory.SLOTS + 7)
	_check(left == 7 and not c.inventory.has_room(tusk), "a full Etc tab hands back what doesn't fit")
	c.inventory.clear()

	# unequip and equip change stats
	var attack := c.stats.attack
	_check(c.gear.unequip(&"weapon") == "" and c.stats.attack == attack - sword.stats.attack, "taking off the sword lowers Weapon Attack")
	_check(c.gear.equip(_first_filled(c, ItemDef.Tab.EQUIP)) == "" and c.stats.attack == attack, "putting it back on restores Weapon Attack")
	c.inventory.add(Content.item(&"leaf_cap"))
	var defense := c.stats.defense
	c.gear.equip(_first_filled(c, ItemDef.Tab.EQUIP))
	_check(c.stats.defense > defense, "wearing a hat raises Weapon Defense")

	# a stronger weapon, and with it more damage
	var top := c.damage_range().y
	c.inventory.add(Content.item(&"dawn_blade"))
	_check(c.gear.equip(_first_filled(c, ItemDef.Tab.EQUIP)) == "", "a new Beginner can wear the Dawn Blade: gear asks for no stats")
	_check(c.damage_range().y > top, "a stronger weapon hits harder")

	# saving and loading keeps the bag and the gear
	c.inventory.add(tusk, 3)
	var store := CharacterStore.new(save_dir)
	store.save(c)
	var back := store.load_character("Tester")
	_check(back != null and JSON.stringify(back.inventory.to_dict()) == JSON.stringify(c.inventory.to_dict())
		and JSON.stringify(back.equipment.to_dict()) == JSON.stringify(c.equipment.to_dict())
		and back.damage_range() == c.damage_range() and back.max_hp() == c.max_hp(), "saving and loading keeps inventory, equipment and damage")
	_check(CharacterStore.clean_name("  Dawn<ling>!  ") == "Dawnling", "character names are cleaned up")
	_check_jobs()
	_check_skill_rules()

## The innate attack, buffs, quickslots and older save files, without the world.
func _check_skill_rules() -> void:
	var c := Character.create("Skiller")
	_check(c.skills.learned.is_empty() and c.skills.level(Content.skill(Character.BASIC_ATTACK)) == 1, "a new character knows only the basic attack")
	# a buff made for the test (the game has no buff skills yet), in Content until it ends
	var step := SkillDef.new()
	step.id = &"t_quick_step"
	step.display_name = "Quick Step"
	step.kind = SkillDef.Kind.BUFF
	step.duration = 3.0
	step.stats = StatBlock.new()
	step.stats.speed = 10
	Content.skills[step.id] = step
	c.skills.learned[step.id] = 1
	var speed := c.stats.speed
	c.skills.add_buff(step)
	c.recalc()
	_check(c.stats.speed > speed, "a speed buff makes you faster")
	c.skills.tick_buffs(step.duration_ticks(1))
	c.recalc()
	_check(c.skills.buffs.is_empty() and c.stats.speed == speed, "and wears off after its time")
	c.skills.learned.erase(step.id)
	Content.skills.erase(step.id)
	c.set_quickslot(0, &"item", &"return_scroll")
	var back := Character.new()
	back.load_dict(c.to_dict())
	_check(back.quickslots == c.quickslots and back.quickslots[0] == [&"item", &"return_scroll"], "quickslots save")
	# a save from before hearts: its level, EXP, Dawn Essence, job skills and potions are dropped
	var old := c.to_dict()
	for key in ["jobs_passed", "heart_shards", "mana_shards"]:
		old.erase(key)
	old["level"] = 12
	old["xp"] = 40
	old["essence"] = 300
	old["skills"] = {"power_strike": 3}
	old["quickslots"] = [["skill", "power_strike"], [], [], [], [], [], ["item", "red_potion"], ["item", "return_scroll"]]
	old["hp"] = 480
	old["job"] = "warrior"
	var legacy := Character.new()
	legacy.load_dict(old)
	_check(legacy.skills.learned.is_empty() and legacy.quickslots[0] == [] and legacy.quickslots[6] == []
		and legacy.quickslots[7] == [&"item", &"return_scroll"], "older saves drop the job skills and potions that are gone")
	_check(legacy.health.hp == legacy.max_hp(), "older saves wake with full hearts")
	_check(legacy.jobs_passed.size() == 1 and legacy.has_passed(Content.job(&"warrior")), "older saves count the jobs they advanced through as passed")

## Starting as a Beginner, advancing, and gear only some jobs can use.
func _check_jobs() -> void:
	var c := Character.create("Rookie")
	_check(c.job.id == &"beginner", "new characters start as Beginners")
	var warrior: JobDef = Content.job(&"warrior")
	var mage: JobDef = Content.job(&"mage")
	for id in [&"warrior", &"archer", &"mage", &"thief", &"pirate"]:
		_check(Content.jobs.has(id) and Content.job(id).advances_from == &"beginner", "%s is a first job" % id)
	_check(c.advance(warrior) == "Pass the %s first." % warrior.advance_quest.title, "advancing to Warrior needs the Job Test, and no stats")
	c.quests.done[warrior.advance_quest.id] = true
	var hp := c.max_hp()
	_check(c.advance(warrior) == "" and c.job == warrior and c.has_passed(warrior), "a Beginner who passed the Job Test becomes a Warrior")
	_check(c.gear.weapon() == Content.item(&"bronze_sword") and c.max_hp() >= hp, "the Warrior gets a Bronze Sword and wears it")
	_check(c.advance(warrior) != "", "a Warrior can't become a Warrior again")
	_check(c.can_become(mage) and c.advance(mage) == "Pass the %s first." % mage.advance_quest.title, "a Warrior may switch to Magician, after its Job Test")
	var wand: EquipDef = Content.item(&"apprentice_wand")
	c.inventory.add(wand)
	var slot := -1
	for i in Inventory.SLOTS:
		var st := c.inventory.at(ItemDef.Tab.EQUIP, i)
		if st and st.item == wand:
			slot = i
	_check(c.gear.equip(slot).begins_with("Only Mages"), "a Warrior can't wear a wand")
