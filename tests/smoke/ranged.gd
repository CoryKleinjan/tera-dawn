extends SmokeArea
## Ranged and magic attacks: arrows, spells and throwing stars.

## An Archer's bow shoots arrows that fly to the monster, a Magician's Energy Bolt uses
## magic, and a claw with no stars can't throw.
func check() -> void:
	var ch := _me().character
	var meadow: MapInstance = Net.server.maps[&"meadow"]
	var sword := ch.equipment.take(&"weapon")
	ch.job = Content.job(&"archer")
	ch.equipment.put(&"weapon", ItemStack.exact(Content.item(&"willow_bow")))
	var arrows: ItemDef = Content.item(&"feather_arrow")
	ch.inventory.add(arrows, 50)
	ch.recalc()
	_me().dirty_character = true
	_teleport(Vector2(1380, 620))
	var m: SimMob = meadow.mobs.filter(func(x: SimMob) -> bool: return x.plat == meadow.layout.platforms[0] and not x.dead)[0]
	# only this monster may be in the arrow's way
	var others := _hold_mobs(meadow, [m])
	m.position.x = 1380 + 200
	world.player.face = 1
	_me().face = 1
	world.player.cooldown = 0
	_me().cooldown = 0
	await _ticks(3)
	_check(Game.me.basic_attack().id == &"bow_shot", "a bow turns the attack key into a shot")
	var hp := m.health.hp
	m.position.x = 1380 + 200
	m.walk_t = 1000
	m.dir = 0
	# the game's view of it has to have glided over too, or the arrow lands at once
	var view: TDMob = world.mobs()[m.index]
	await _until(func() -> bool: return absf(view.position.x - m.position.x) < 4.0, 120)
	var flying := []
	var spotted := func(c: Node) -> void:
		if c is TDProjectile:
			flying.append(c)
	world.fx_layer.child_entered_tree.connect(spotted)
	await _tap("attack")
	world.fx_layer.child_entered_tree.disconnect(spotted)
	_check(not flying.is_empty(), "the arrow flies")
	await _until(func() -> bool: return m.health.hp < hp or m.dead, 20)
	_check(m.health.hp < hp or m.dead, "it hits a monster 200 pixels away")
	_release_mobs(others)
	_check(Game.me.inventory.count_of(arrows) == 49, "and uses one arrow")
	# no arrows, no shot
	ch.inventory.remove(arrows, 49)
	_me().cooldown = 0
	world.player.cooldown = 0
	_me().dirty_character = true
	await _ticks(2)
	_check(Game.me.use_problem(Game.me.basic_attack()).contains("out of arrows"), "without arrows the bow can't shoot")
	# a Magician's spell uses Magic Attack
	ch.job = Content.job(&"mage")
	ch.equipment.take(&"weapon")
	ch.equipment.put(&"weapon", ItemStack.exact(Content.item(&"apprentice_wand")))
	ch.base.intelligence = 60
	ch.skills[&"energy_bolt"] = 1
	ch.recalc()
	var bolt: SkillDef = Content.skill(&"energy_bolt")
	var magic := ch.magic_range()
	_check(magic.y > ch.damage_range().y, "a Magician's spells hit harder than their wand")
	var hit := Combat.player_hit(bolt, m.def, ch)
	_check(hit["miss"] or (hit["damage"] >= 1 and hit["damage"] <= roundi(magic.y * 1.6) + 1), "Energy Bolt's damage comes from Magic Attack")
	# a claw needs stars
	ch.job = Content.job(&"thief")
	ch.equipment.take(&"weapon")
	ch.equipment.put(&"weapon", ItemStack.exact(Content.item(&"iron_claw")))
	ch.skills[&"lucky_seven"] = 1
	_check(ch.use_problem(Content.skill(&"lucky_seven")).contains("out of stars"), "Lucky Seven needs throwing stars")
	ch.inventory.add(Content.item(&"iron_star"), 10)
	_check(ch.use_problem(Content.skill(&"lucky_seven")) == "" and ch.ammo_attack() == 15, "with stars it's ready, and stars add attack")
	ch.skills[&"flash_fist"] = 1
	_check(ch.use_problem(Content.skill(&"flash_fist")).contains("needs a knuckle"), "Flash Fist needs a knuckle")
	# back to a Warrior with a sword for the rest of the test
	ch.job = Content.job(&"warrior")
	ch.equipment.take(&"weapon")
	ch.equipment.put(&"weapon", sword)
	ch.recalc()
	_me().dirty_character = true
	await _ticks(2)
