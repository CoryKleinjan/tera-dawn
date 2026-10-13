extends TestCase
## Hosting: character select shows what friends type to join, a friend brings their own
## character in and it's saved on their side. Leaving while hosting: with a friend connected
## the host is asked first, Cancel keeps the game going, and ending it tells the friend "The
## host ended the game." The friend is a second copy of Net in this process, on its own
## MultiplayerAPI and its own character saves, joined over the network.

const PORT := 7800
const PORTS := 200

var ui: UiHelpers
## The friend's game: a node with its own MultiplayerAPI, holding the friend's Net.
var friend_game: Node
var friend: Node
## Why the friend's game says it was disconnected ("" until it is).
var friend_why := ""
## Whether the host let the friend in (their character select).
var friend_in := false
const FRIEND_SAVES := "user://host_test_friend_characters"

func before_each() -> void:
	ui = UiHelpers.new(self)
	await ui.open_title()
	friend_why = ""
	friend_in = false

func after_each() -> void:
	if friend_game:
		friend.stop()
		get_tree().set_multiplayer(null, friend_game.get_path())
		friend_game.free()
		friend_game = null
	UiHelpers.clear_saves_at(FRIEND_SAVES)
	ui.stop()

## Hosts on a free test port. Returns the port, or 0.
func _host() -> int:
	var port := PORT + OS.get_process_id() % PORTS
	for i in 20:
		if Net.host(port) == "":
			return port
		port = PORT + (port - PORT + 1) % PORTS
	return 0

## A friend joins this game's port; waits until the host lets them in.
func _friend_joins(port: int) -> bool:
	friend_game = Node.new()
	friend_game.name = "FriendGame"
	add_child(friend_game)
	get_tree().set_multiplayer(SceneMultiplayer.new(), friend_game.get_path())
	friend = (load("res://scripts/autoload/net.gd") as GDScript).new()
	friend.name = "Net"
	friend_game.add_child(friend)
	friend.save_dir = FRIEND_SAVES
	friend.disconnected.connect(func(why: String) -> void: friend_why = why)
	friend.welcomed.connect(func() -> void: friend_in = true)
	friend.join("127.0.0.1", port)
	for i in 600:
		await ui.ticks(1)
		if friend_in and Net.has_guests():
			return true
	return false

func test_a_friend_brings_their_own_character_and_keeps_it() -> void:
	var port := _host()
	if not check(port != 0, "hosting opens a port"):
		return
	await ui.ticks(2)
	if not check(await _friend_joins(port), "a friend is let in"):
		return
	check_eq(friend.create_character("Pal", NewCharacter.new()), "", "they make a character on their side")
	check(not CharacterStore.new(UiHelpers.SAVE_DIR).exists("Pal"), "not on the host's computer")
	friend.play("Pal")
	var pal: SimPlayer = null
	for i in 600:
		await ui.ticks(1)
		for p: SimPlayer in Net.server.sessions.values():
			if p.character.name == "Pal":
				pal = p
		if pal:
			break
	if not check(pal != null, "Pal is in the host's game"):
		return
	pal.character.shards = 321
	Net.server.save(pal)
	for i in 300:
		await ui.ticks(1)
		if CharacterStore.new(FRIEND_SAVES).load_character("Pal").shards == 321:
			break
	check_eq(CharacterStore.new(FRIEND_SAVES).load_character("Pal").shards, 321, "saved on the friend's computer")
	check(not CharacterStore.new(UiHelpers.SAVE_DIR).exists("Pal"), "and still not on the host's")

func test_leaving_with_friends_playing_asks_and_tells_them() -> void:
	var port := _host()
	if not check(port != 0, "hosting opens a port"):
		return
	await ui.ticks(2)
	if not check(await _friend_joins(port), "a friend is let in"):
		return
	var sel := ui.hud.title.character_select
	sel.leave_button.pressed.emit()
	var ask := ui.hud.title.confirm
	check(ask.visible, "asks first")
	check_eq(ask.question.text, "Friends are playing in your game. Leave and end it for them?", "says why")
	check(ask.cancel_button.has_focus(), "Cancel has the focus")
	await ui.press("pause")
	check(not ask.visible and sel.visible, "Esc cancels")
	check(sel.create_button.has_focus(), "the focus goes back")
	check_eq(Net.mode, Net.Mode.HOST, "still hosting")
	sel.leave_button.pressed.emit()
	ask.ok_button.pressed.emit()
	check_eq(Net.mode, Net.Mode.NONE, "left")
	check(ui.hud.title.title_card.visible, "title card")
	for i in 300:
		await ui.ticks(1)
		if friend_why != "":
			break
	check_eq(friend_why, Net.HOST_ENDED, "the friend is told the host ended the game")

func test_leaving_alone_while_hosting_doesnt_ask() -> void:
	if not check(_host() != 0, "hosting opens a port"):
		return
	await ui.ticks(2)
	ui.hud.title.character_select.leave_button.pressed.emit()
	check(not ui.hud.title.confirm.visible, "no question")
	check_eq(Net.mode, Net.Mode.NONE, "left")

func test_hosting_shows_what_friends_type_to_join() -> void:
	var port := _host()
	if not check(port != 0, "hosting opens a port"):
		return
	await ui.ticks(2)
	var sel := ui.hud.title.character_select
	check(sel.host_panel.visible, "the host panel shows on character select")
	check_eq(sel.subheading.text, "Hosting a game for up to %d players" % Net.MAX_PLAYERS, "says it's hosting")
	if sel.host_panel.address != "":
		check(sel.host_panel.address.ends_with(":%d" % port), "the address carries the test port")
		check(sel.host_panel.address_label.text.contains(sel.host_panel.address), "and is shown")
	check(not sel.host_panel.firewall_button.visible, "no firewall to open off Windows")
	sel.leave_button.pressed.emit()
	Net.play_single()
	await ui.ticks(2)
	check(not sel.host_panel.visible, "playing solo hides it")
