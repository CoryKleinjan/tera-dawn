extends SmokeArea
## Real multiplayer: a second copy of the game joins a hosted game over the network.

## The first port the multiplayer check tries. Each run starts somewhere after it (by its
## process id) and moves on past ports in use, so smoke tests running side by side on one
## machine neither fail to host nor join each other's games.
const TEST_PORT := 7391
const TEST_PORTS := 400

## Where the bot client writes what it saw.
var bot_result := "user://smoke_test_bot_%d.json" % OS.get_process_id()

## Hosts a game and has a second copy of the game (tests/bot_client.tscn) join it over
## the network: each must see the other, and the bot's attacks must count on the server.
func check() -> void:
	var port := TEST_PORT + OS.get_process_id() % TEST_PORTS
	var problem := Net.host(port)
	for i in 20:
		if problem == "":
			break
		port = TEST_PORT + (port - TEST_PORT + 1) % TEST_PORTS
		problem = Net.host(port)
	_check(problem == "", "hosting opens a port (%d)%s" % [port, "" if problem == "" else ": " + problem])
	if problem != "":
		return
	Net.create_character("Host", NewCharacter.new())
	Net.play("Host")
	await _ticks(2)
	_check(world.started and Net.mode == Net.Mode.HOST, "the host plays in their own game")
	_me().inv = 100000
	DirAccess.remove_absolute(bot_result)
	var bot := OS.create_process(OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/bot_client.tscn", "--", str(port), bot_result])
	_check(bot > 0, "a second game starts to join")
	var bot_peer := 0
	for i in 1200:
		await _ticks(1)
		for peer in Net.server.sessions:
			if peer != 1:
				bot_peer = peer
		if bot_peer != 0:
			break
	_check(bot_peer != 0, "the second game joins the host over an encrypted connection, bringing its own character")
	_check(not CharacterStore.new(save_dir).exists(BotClient.CHARACTER), "the bot's character isn't saved on the host")
	if bot_peer == 0:
		OS.kill(bot)
		return
	var bot_player: SimPlayer = Net.server.sessions[bot_peer]
	bot_player.inv = 100000
	# both players go out to the meadow, where the monsters are (the village has none)
	Net.server.enter_map(_me(), &"meadow", 360)
	Net.server.enter_map(bot_player, &"meadow", 300)
	# hold a Dewling in front of the bot until its attacks defeat one
	var meadow: MapInstance = Net.server.maps[&"meadow"]
	var kills := bot_player.character.book.total_kills()
	var seen_name := ""
	for i in 1200:
		await _ticks(1)
		if world.avatars.has(bot_peer):
			seen_name = world.avatars[bot_peer].char_name
		for m in meadow.mobs:
			if m.def.id == &"dewling" and m.plat == meadow.layout.platforms[0] and not m.dead:
				m.area = m.plat # floor Dewlings keep away from the meadow's entrance, where the bot stands
				m.position.x = bot_player.position.x + 40
				break
		if bot_player.character.book.total_kills() > kills:
			break
	_check(bot_player.character.book.total_kills() > kills, "the joining player's attacks defeat a monster on the server")
	_check(seen_name == "Bot", "the host sees the other player, with their name")
	for i in 2400:
		await _ticks(1)
		if not OS.is_process_running(bot):
			break
	var f := FileAccess.open(bot_result, FileAccess.READ)
	var result: Variant = JSON.parse_string(f.get_as_text()) if f else null
	f = null
	DirAccess.remove_absolute(bot_result)
	_check(result is Dictionary and result.get("saw_host", false), "the other player sees the host %s" % [result])
	_check(result is Dictionary and result.get("saw_mobs", false) and result.get("saw_hits", false), "the other player sees the monsters and their own hits")
	_check(result is Dictionary and result.get("saved", false), "the other player's progress is saved on their own computer")
	for i in 120:
		await _ticks(1)
		if not Net.server.sessions.has(bot_peer):
			break
	_check(not Net.server.sessions.has(bot_peer) and not world.avatars.has(bot_peer), "when they quit, they leave the host's map")
	world.stop()
