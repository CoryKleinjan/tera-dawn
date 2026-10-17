extends SmokeArea
## Job advancement through an instructor's dialogue.

## Archmage Celest in Lumewood turns a ready Beginner into a Magician through the dialogue
## window.
func check() -> void:
	var ch := _me().character
	Net.server.enter_map(_me(), &"lumewood", 300)
	await _ticks(3)
	_check(world.map.id == &"lumewood" and world.map.town, "Lumewood is a town")
	Net.server.enter_map(_me(), &"lumewood_hall", 240)
	await _ticks(3)
	_check(world.map.outside() == &"lumewood", "the Magicians' Library is a room in Lumewood")
	var guide: TDNpc = world.npcs().filter(func(n: TDNpc) -> bool: return n.def.id == &"lumewood_instructor")[0]
	ch.job = Content.job(&"beginner")
	ch.quests.done[&"jtest_mage"] = true
	ch.recalc()
	_me().dirty_character = true
	await _ticks(2)
	_teleport(Vector2(guide.position.x - 30, guide.position.y))
	await _ticks(2)
	await _tap("move_up")
	var talk: TDDialogueWindow = world.hud.windows["dialogue"]
	var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels.has("Choose a job"), "the job instructor offers to choose a job")
	talk.choose(labels.find("Choose a job"))
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	_check(labels == ["Magician", "Back"], "Lumewood's instructor teaches Magicians")
	talk.choose(labels.find("Magician"))
	_check(talk.options[0][0] == "Become a Magician", "a Beginner who passed the Job Test may become a Magician")
	talk.choose(0)
	await _ticks(2)
	_check(Game.me.job.id == &"mage" and Game.me.gear.weapon() == Content.item(&"apprentice_wand"), "the server makes them a Magician and hands them a wand to wear")
	Net.ask(&"req_equip", [Game.me.inventory.find(Content.item(&"apprentice_wand")), &"weapon"])
	await _ticks(2)
	_check(Game.me.equipment.at(&"weapon") != null and Game.me.equipment.at(&"weapon").item == Content.item(&"apprentice_wand"), "the wand stays worn")
	Net.server.enter_map(_me(), &"meadow", 300)
	await _ticks(3)
