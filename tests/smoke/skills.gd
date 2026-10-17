extends SmokeArea
## The skill book, quickslots, buffs and passives in the game.

## A Warrior with Dawn Essence buys skills in the skill window: they land on quickslots,
## a buff raises stats until it runs out, and a passive is always on.
func check() -> void:
	var ch := _me().character
	ch.job = Content.job(&"warrior")
	ch.skills.learned.clear()
	ch.skills.paid.clear()
	# enough Dawn Essence for five skill levels
	var essence := 0
	for n in 5:
		essence += CharacterStats.skill_price(n)
	ch.essence = essence
	ch.quickslots.fill([])
	_me().dirty_character = true
	await _ticks(2)
	var book: TDSkillWindow = world.hud.windows["skills"]
	await _press("skills")
	_check(book.visible and book.jobs() == [&"beginner", &"warrior"], "K opens the skill book with Beginner and Warrior tabs")
	book.tab = 1
	var slash: SkillDef = Content.skill(&"dawn_slash")
	book.learn(slash)
	await _ticks(1)
	_check(Game.me.skills.level(slash) == 0 and Game.me.essence == essence, "Dawn Slash needs Power Strike first")
	book.learn(Content.skill(&"power_strike"))
	book.learn(slash)
	book.learn(Content.skill(&"iron_body"))
	book.learn(Content.skill(&"blade_mastery"))
	await _ticks(1)
	_check(Game.me.skills.level(slash) == 1 and Game.me.essence == CharacterStats.skill_price(4), "spending Dawn Essence learns skills, each level dearer than the last")
	_check(Game.me.quickslots[0] == [&"skill", &"power_strike"] and Game.me.quickslots[1] == [&"skill", &"dawn_slash"]
		and Game.me.quickslots[2] == [&"skill", &"iron_body"], "learned skills go on the free quickslots")
	_check(Game.me.stats.melee_damage == 2, "Blade Mastery raises Melee Damage")
	await _press("skills")
	# Iron Body raises defense until it wears off.
	var defense := Game.me.stats.defense
	ch.mp = ch.max_mp()
	world.player.cooldown = 0
	_me().cooldown = 0
	await _tap("quick_3")
	await _ticks(1)
	_check(Game.me.skills.buffs.has(&"iron_body") and Game.me.stats.defense == defense + 5, "Iron Body raises Weapon Defense")
	ch.skills.buffs[&"iron_body"][1] = 2
	await _ticks(4)
	_check(not Game.me.skills.buffs.has(&"iron_body") and Game.me.stats.defense == defense, "it wears off")
	# Quickslots can be rearranged from the client, and the server keeps them.
	world.hud.quickslots.assign(5, &"skill", &"dawn_slash")
	await _ticks(1)
	_check(ch.quickslots[5] == [&"skill", &"dawn_slash"] and ch.quickslots[1] == [], "moving a skill to another quickslot")
	world.hud.quickslots.assign(1, &"skill", &"dawn_slash")
	# A Red Potion on a quickslot is drunk with its key.
	world.hud.quickslots.assign(7, &"item", &"red_potion")
	ch.health.set_hp(1)
	await _ticks(2)
	_me().item_cd = 0
	await _tap("quick_8")
	await _ticks(1)
	_check(Game.me.health.hp > 1, "a potion's quickslot key drinks it")
	world.player.cooldown = 0
	_me().cooldown = 0
	await _ticks(30)
