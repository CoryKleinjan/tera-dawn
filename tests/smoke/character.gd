extends SmokeArea
## A character without the world: inventory, equipment, levels and power, saving, jobs and skills.

## Inventory, equipment, stats and saving, without the world.
func check() -> void:
	var c := Character.create("Tester")
	var sword: EquipDef = Content.item(&"training_sword")
	_check(c.equipment.at(&"weapon") != null and c.equipment.at(&"weapon").item == sword, "a new character wears the starting sword")
	_check(c.inventory.count_of(Content.item(&"red_potion")) == 5, "a new character carries 5 Red Potions")
	var dmg := c.damage_range()
	_check(dmg.x > 0 and dmg.y >= dmg.x, "the damage range comes from power and the weapon (%d ~ %d)" % [dmg.x, dmg.y])

	# stacking and a full tab
	var red: ItemDef = Content.item(&"red_potion")
	c.inventory.add(red, 150)
	_check(c.inventory.count_of(red) == 155 and c.inventory.at(ItemDef.Tab.USE, 0).count == 100 and c.inventory.at(ItemDef.Tab.USE, 1).count == 55, "potions stack up to 100 a slot")
	var tusk: ItemDef = Content.item(&"boar_tusk")
	var left := c.inventory.add(tusk, 200 * Inventory.SLOTS + 7)
	_check(left == 7 and not c.inventory.has_room(tusk), "a full Etc tab hands back what doesn't fit")
	c.inventory.clear()

	# unequip and equip change stats
	var attack := c.stats.attack
	_check(c.gear.unequip(&"weapon") == "" and c.stats.attack == attack - sword.stats.attack, "taking off the sword lowers Weapon Attack")
	_check(c.gear.equip(_first_filled(c, ItemDef.Tab.EQUIP)) == "" and c.stats.attack == attack, "putting it back on restores Weapon Attack")
	c.gear.unequip(&"armor")
	c.inventory.clear()
	c.inventory.add(Content.item(&"leaf_cap"))
	var defense := c.stats.defense
	c.gear.equip(_first_filled(c, ItemDef.Tab.EQUIP))
	_check(c.stats.defense > defense, "wearing a hat raises Weapon Defense")
	c.inventory.add(Content.item(&"dawn_blade"))
	_check(c.gear.equip(_first_filled(c, ItemDef.Tab.EQUIP)) == "", "a new Beginner can wear the Dawn Blade: gear asks for no stats")

	# a level raises power, and with it damage
	var top := c.damage_range().y
	var power := c.power()
	_check(c.gain_xp(c.xp_need()) == 1 and c.power() == power + CharacterStats.POWER_PER_LEVEL and c.damage_range().y > top, "a level raises power and damage")

	# saving and loading keeps the bag and the gear
	c.inventory.add(tusk, 3)
	var store := CharacterStore.new(save_dir)
	store.save(c)
	var back := store.load_character("Tester")
	_check(back != null and JSON.stringify(back.inventory.to_dict()) == JSON.stringify(c.inventory.to_dict())
		and JSON.stringify(back.equipment.to_dict()) == JSON.stringify(c.equipment.to_dict())
		and back.level == c.level and back.power() == c.power() and back.essence == c.essence, "saving and loading keeps inventory, equipment and level")
	_check(CharacterStore.clean_name("  Dawn<ling>!  ") == "Dawnling", "character names are cleaned up")
	_check_jobs()
	_check_skill_rules()

## Buying skills with Dawn Essence, Beginner skills, buffs and save files, without the world.
func _check_skill_rules() -> void:
	var c := Character.create("Skiller")
	_check(c.skills.spent() == 0 and c.skills.level(Content.skill(Character.BASIC_ATTACK)) == 1, "a new character knows only the basic attack")
	var step: SkillDef = Content.skill(&"quick_step")
	_check(c.skills.learn(step).contains("Dawn Essence"), "learning a skill costs Dawn Essence")
	c.gain_essence(c.skills.price())
	_check(c.skills.learn(step) == "" and c.skills.level(step) == 1 and c.essence == 0, "a Beginner learns Quick Step")
	_check(c.skills.learn(step) != "", "no Dawn Essence, no more levels")
	_check(c.skills.learn(Content.skill(&"power_strike")) != "", "a Beginner can't learn Warrior skills")
	var speed := c.stats.speed
	c.mp = 100
	c.skills.add_buff(step)
	_check(c.stats.speed > speed, "Quick Step makes you faster")
	c.skills.tick_buffs(step.duration_ticks(1))
	_check(c.skills.buffs.is_empty() and c.stats.speed == speed, "and wears off after its time")
	c.gain_essence(c.skills.price())
	var aid: SkillDef = Content.skill(&"first_aid")
	c.skills.learn(aid)
	_check(c.skills.level(aid) == 1 and aid.heal_at(1) > 0.0 and aid.recharge_ticks(1) > 0, "First Aid heals, then takes a while to use again")
	var back := Character.new()
	back.load_dict(c.to_dict())
	_check(back.skills.learned == c.skills.learned and back.skills.paid == c.skills.paid and back.quickslots == c.quickslots, "skills, what was paid for them and quickslots save")
	# a save from before Dawn Essence: its level and EXP stay, unspent Skill Points become essence
	var old := c.to_dict()
	old.erase("essence")
	old.erase("skills")
	old.erase("skills_paid")
	old.erase("quickslots")
	old.erase("jobs_passed")
	old["level"] = 12
	old["xp"] = 40
	old["sp"] = 3
	old["job"] = "warrior"
	var legacy := Character.new()
	legacy.load_dict(old)
	var sp_worth := CharacterStats.skill_price(0) + CharacterStats.skill_price(1) + CharacterStats.skill_price(2)
	_check(legacy.level == 12 and legacy.xp == 40 and legacy.essence == sp_worth and legacy.quickslots[Character.QUICKSLOTS - 2] == [&"item", &"red_potion"], "older saves keep their level and turn Skill Points into Dawn Essence")
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
	var hp := c.max_hearts()
	_check(c.advance(warrior) == "" and c.job == warrior and c.has_passed(warrior), "a Beginner who passed the Job Test becomes a Warrior")
	_check(c.gear.weapon() == Content.item(&"bronze_sword") and c.max_hearts() >= hp, "the Warrior gets a Bronze Sword and wears it")
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
