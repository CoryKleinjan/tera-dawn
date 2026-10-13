extends SmokeArea
## A character without the world: inventory, equipment, stats, saving, jobs and skills.

## Inventory, equipment, stats and saving, without the world.
func check() -> void:
	var c := Character.create("Tester")
	var sword: EquipDef = Content.item(&"training_sword")
	_check(c.equipment.at(&"weapon") != null and c.equipment.at(&"weapon").item == sword, "a new character wears the starting sword")
	_check(c.inventory.count_of(Content.item(&"red_potion")) == 5, "a new character carries 5 Red Potions")
	var dmg := c.damage_range()
	_check(dmg.x > 0 and dmg.y >= dmg.x, "the damage range comes from stats and the weapon (%d ~ %d)" % [dmg.x, dmg.y])

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
	c.inventory.add(Content.item(&"leaf_cap"))
	var defense := c.stats.defense
	c.gear.equip(_first_filled(c, ItemDef.Tab.EQUIP))
	_check(c.stats.defense > defense, "wearing a hat raises Weapon Defense")
	c.inventory.add(Content.item(&"dawn_blade"))
	_check(c.gear.equip(_first_filled(c, ItemDef.Tab.EQUIP)) != "", "level 1 can't wear the level 8 Dawn Blade")

	# levels give Ability Points, and STR raises damage
	c.gain_xp(c.xp_need())
	_check(c.level == 2 and c.ap.points == c.job.ap_per_level, "levelling up gives Ability Points")
	var top := c.damage_range().y
	for n in 5:
		c.ap.spend(&"strength")
	_check(c.ap.points == 0 and c.damage_range().y > top, "spending AP on STR raises damage")

	# saving and loading keeps the bag and the gear
	c.inventory.add(tusk, 3)
	var store := CharacterStore.new(save_dir)
	store.save(c)
	var back := store.load_character("Tester")
	_check(back != null and JSON.stringify(back.inventory.to_dict()) == JSON.stringify(c.inventory.to_dict())
		and JSON.stringify(back.equipment.to_dict()) == JSON.stringify(c.equipment.to_dict())
		and back.base.strength == c.base.strength and back.level == 2, "saving and loading keeps inventory, equipment and stats")
	_check(CharacterStore.clean_name("  Dawn<ling>!  ") == "Dawnling", "character names are cleaned up")
	_check_jobs()
	_check_skill_rules()

## Skill Points, Beginner skills, buffs and save files, without the world.
func _check_skill_rules() -> void:
	var c := Character.create("Skiller")
	_check(c.skills.points == 0 and c.skills.level(Content.skill(Character.BASIC_ATTACK)) == 1, "a new character knows only the basic attack")
	c.gain_xp(c.xp_need())
	_check(c.skills.points == 1, "a Beginner gets 1 Skill Point a level")
	var step: SkillDef = Content.skill(&"quick_step")
	_check(c.skills.learn(step) == "" and c.skills.level(step) == 1 and c.skills.points == 0, "a Beginner learns Quick Step")
	_check(c.skills.learn(step) != "", "no Skill Points, no more levels")
	_check(c.skills.learn(Content.skill(&"power_strike")) != "", "a Beginner can't learn Warrior skills")
	var speed := c.stats.speed
	c.mp = 100
	c.skills.add_buff(step)
	_check(c.stats.speed > speed, "Quick Step makes you faster")
	c.skills.tick_buffs(step.duration_ticks(1))
	_check(c.skills.buffs.is_empty() and c.stats.speed == speed, "and wears off after its time")
	c.skills.points = 3
	var wind: SkillDef = Content.skill(&"second_wind")
	c.skills.learn(wind)
	_check(c.skills.regen_bonus().x == wind.regen_hp, "Second Wind adds HP recovery")
	var back := Character.new()
	back.load_dict(c.to_dict())
	_check(back.skills.learned == c.skills.learned and back.skills.points == c.skills.points and back.quickslots == c.quickslots, "skills, Skill Points and quickslots save")
	var old := c.to_dict()
	old.erase("sp")
	old.erase("skills")
	old.erase("quickslots")
	old["level"] = 12
	old["job"] = "warrior"
	var legacy := Character.new()
	legacy.load_dict(old)
	_check(legacy.skills.points == 11 * 3 and legacy.quickslots[Character.QUICKSLOTS - 2] == [&"item", &"red_potion"], "older saves get Skill Points for their levels")

## Starting as a Beginner, advancing, and gear only some jobs can use.
func _check_jobs() -> void:
	var c := Character.create("Rookie")
	_check(c.job.id == &"beginner", "new characters start as Beginners")
	var warrior: JobDef = Content.job(&"warrior")
	var mage: JobDef = Content.job(&"mage")
	for id in [&"warrior", &"archer", &"mage", &"thief", &"pirate"]:
		_check(Content.jobs.has(id) and Content.job(id).advances_from == &"beginner", "%s is a first job" % id)
	_check(c.advance(warrior).begins_with("You need to be level"), "a level 1 Beginner can't advance")
	c.level = 10
	_check(c.advance(warrior).contains("STR"), "advancing to Warrior needs 35 STR")
	c.base.strength = 35
	_check(c.advance(warrior) == "Pass the Job Test first.", "advancing to Warrior needs the Job Test")
	c.quests.done[warrior.advance_quest.id] = true
	var hp := c.max_hp()
	_check(c.advance(warrior) == "" and c.job == warrior, "a level 10 Beginner with 35 STR becomes a Warrior")
	_check(c.gear.weapon() == Content.item(&"bronze_sword") and c.max_hp() >= hp, "the Warrior gets a Bronze Sword and wears it")
	_check(c.advance(mage) != "", "a Warrior can't then become a Magician")
	var wand: EquipDef = Content.item(&"apprentice_wand")
	c.inventory.add(wand)
	var slot := -1
	for i in Inventory.SLOTS:
		var st := c.inventory.at(ItemDef.Tab.EQUIP, i)
		if st and st.item == wand:
			slot = i
	_check(c.gear.equip(slot).begins_with("Only Mages"), "a Warrior can't wear a wand")
