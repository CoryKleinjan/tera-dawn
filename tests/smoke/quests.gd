extends SmokeArea
## Quests: taking, doing and handing in a quest through the dialogue window, quest-only
## drops, and giving a quest up.

## Takes Elder Rowan's first quest, does it, hands it in; then a quest whose item only
## drops while you're on it.
func check() -> void:
	Net.server.enter_map(_me(), Character.START_MAP, 300)
	await _ticks(3)
	var meadow: MapInstance = Net.server.map_instance(&"meadow")
	var elder := world.npcs()[0]
	var q1: QuestDef = Content.quest(&"q01_dewling_trouble")
	_teleport(Vector2(elder.position.x - 30, 620))
	await _ticks(2)
	_check(elder.quest_marker() == "!", "the elder shows a ! for a quest he can give")
	await _tap("move_up")
	var talk: TDDialogueWindow = world.hud.windows["dialogue"]
	var labels: Array = talk.options.map(func(o: Array) -> String: return o[0])
	var i := labels.find("New quest: %s" % q1.title)
	_check(i >= 0, "he offers Dewling Trouble")
	talk.choose(i)
	_check(talk.text.contains(q1.offer_text) and talk.options[0][0] == "Accept", "picking it shows the offer with Accept")
	talk.choose(0)
	await _ticks(1)
	_check(Game.me.quests.active.has(q1.id), "accepting it starts the quest")
	talk.choose(talk.options.size() - 1)
	var xp_level: int = Game.me.level * 100000 + Game.me.xp
	var potions := Game.me.inventory.count_of(Content.item(&"red_potion"))
	var shards := Game.me.shards
	var dewlings := meadow.mobs.filter(func(m: SimMob) -> bool: return m.def.id == &"dewling")
	for n in 8:
		var m: SimMob = dewlings[n % dewlings.size()]
		m._reset()
		meadow.kill_mob(m, _me())
	await _ticks(1)
	_check(Game.me.quests.is_ready(q1, Game.me) and elder.quest_marker() == "?", "defeating 8 Dewlings readies it, and the elder shows a ?")
	world.hud.windows["quests"].toggle()
	_check(world.hud.windows["quests"].listed().has(q1), "the quest log lists it in progress")
	world.hud.windows["quests"].toggle()
	await _tap("move_up")
	labels = talk.options.map(func(o: Array) -> String: return o[0])
	talk.choose(labels.find("Hand in: %s" % q1.title))
	talk.choose(0)
	await _ticks(1)
	_check(Game.me.quests.done.has(q1.id) and not Game.me.quests.active.has(q1.id), "handing it in finishes it")
	_check(Game.me.inventory.count_of(Content.item(&"red_potion")) == potions + 5 and Game.me.shards >= shards + q1.reward_shards
		and Game.me.level * 100000 + Game.me.xp > xp_level, "it pays its EXP, Dawnshards and potions")
	talk.choose(talk.options.size() - 1)

	# Petal Nectar only drops for someone on Sweet Nectar.
	var nectar: ItemDef = Content.item(&"petal_nectar")
	var bat: SimMob = meadow.mobs.filter(func(m: SimMob) -> bool: return m.def.id == &"petal_bat")[0]
	var nectar_drops := func() -> int:
		return meadow.drops.values().filter(func(d: SimDrop) -> bool: return d.item == nectar).size()
	for n in 10:
		bat._reset()
		meadow.kill_mob(bat, _me())
	_check(nectar_drops.call() == 0, "quest items don't drop without the quest")
	var ch := _me().character
	ch.quests.done[&"q02_moss_for_the_stall"] = 1
	ch.level = maxi(ch.level, 3)
	ch.quests.accept(Content.quest(&"q04_sweet_nectar"))
	for n in 10:
		bat._reset()
		meadow.kill_mob(bat, _me())
	_check(nectar_drops.call() > 0, "they do once you're on it")
	server_forfeit_check(ch)

## Gives up Sweet Nectar through the server.
func server_forfeit_check(ch: Character) -> void:
	Net.ask(&"req_quest_forfeit", [&"q04_sweet_nectar"])
	_check(not ch.quests.active.has(&"q04_sweet_nectar"), "a quest can be given up")
