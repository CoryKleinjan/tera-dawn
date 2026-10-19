extends TestCase
## Bringing a character into a game and leaving it, a full game, and characters being sent
## back to their player's game to save. Making, naming and deleting characters on the
## player's own computer is in character_store_test.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()

func test_join_sends_the_character_then_the_starting_map() -> void:
	h.play(2, "Ann")
	check_eq(h.count(2, &"ev_joined"), 1, "ev_joined sent once")
	check_eq(h.count(2, &"ev_enter_map"), 1, "ev_enter_map sent once")
	var kinds := []
	for e in h.api.sent:
		kinds.append(e[1])
	check(kinds.find(&"ev_joined") < kinds.find(&"ev_enter_map"), "the character comes before the map")
	check_eq(h.last(2, &"ev_joined")[0]["name"], "Ann", "the joined character's name")
	check_eq(h.last(2, &"ev_enter_map")[0], Character.NEW_MAP, "a new character starts on the tutorial beach")
	check_eq(h.events(2).size(), h.api.sent.size(), "every event went to peer 2")
	check_eq(h.count(2, &"ev_refused"), 0, "nothing refused")

func test_new_character_is_a_beginner_with_full_health() -> void:
	var p := h.join(2, "Ann")
	var c := p.character
	check_eq(c.job.id, Character.START_JOB, "job")
	check_eq(c.health.hp, c.max_hp(), "every heart")
	check_eq(c.mp, 0, "an empty Mana orb")
	check_eq(c.shards, 0, "no Dawnshards")

func test_a_name_already_playing_is_refused() -> void:
	h.join(2, "Ann")
	h.api.peers.append(3)
	h.server.lobby.on_play(3, Character.create("aNN").to_dict())
	check_eq(h.last(3, &"ev_refused"), ["aNN is already playing.", false], "why")
	check(not h.server.sessions.has(3), "not in the world")

func test_a_character_that_cannot_be_read_is_refused() -> void:
	h.api.peers.append(2)
	h.server.lobby.on_play(2, {"shards": 3})
	check_eq(h.last(2, &"ev_refused"), ["That character's save couldn't be read.", false], "why")
	check(not h.server.sessions.has(2), "not in the world")

func test_a_character_on_a_map_this_game_lacks_starts_on_the_starting_map() -> void:
	var data := Character.create("Ann").to_dict()
	data["map_id"] = "nowhere_at_all"
	h.api.peers.append(2)
	h.server.lobby.on_play(2, data)
	check_eq(h.last(2, &"ev_enter_map")[0], Character.START_MAP, "the starting map")

func test_playing_twice_on_one_connection_is_ignored() -> void:
	h.join(2, "Ann")
	h.server.lobby.on_play(2, Character.create("Bob").to_dict())
	check_eq(h.server.sessions[2].character.name, "Ann", "still Ann")

func test_the_game_holds_four_players_counting_the_host() -> void:
	for peer in [2, 3, 4]:
		h.api.peers.append(peer)
		h.server.lobby.connected(peer)
		check_eq(h.count(peer, &"ev_welcome"), 1, "peer %d let in" % peer)
	h.api.peers.append(5)
	h.server.lobby.connected(5)
	check_eq(h.last(5, &"ev_refused"), [TDLobby.FULL % Net.MAX_PLAYERS, true], "a fifth is told it's full")
	check_eq(h.count(5, &"ev_welcome"), 0, "and not let in")
	h.server.lobby.on_play(5, Character.create("Eve").to_dict())
	check(not h.server.sessions.has(5), "it can't play while it's being dropped")

func test_leaving_for_character_select_saves_then_says_so() -> void:
	var a := h.join(2, "Ann")
	a.character.shards = 42
	h.ask(2, &"req_leave_character")
	var kinds := h.api.sent.filter(func(e: Array) -> bool: return e[0] == 2).map(func(e: Array) -> StringName: return e[1])
	check(kinds.find(&"ev_save") >= 0 and kinds.find(&"ev_save") < kinds.find(&"ev_left_world"), "saved first")
	check_eq(h.last(2, &"ev_left_world"), ["Ann"], "back to character select")
	check_eq(h.saved("Ann").shards, 42, "with her Dawnshards")
	check(not h.server.sessions.has(2), "out of the world")

func test_leaving_saves_the_character_and_tells_the_map() -> void:
	var a := h.join(2, "Ann")
	h.join(3, "Bob")
	a.character.shards = 1234
	h.leave(2)
	check_eq(h.last(3, &"ev_player_left"), [2], "Bob sees Ann leave")
	check(not h.server.sessions.has(2), "session gone")
	check(not h.server.maps[ServerHarness.FIELD].players.has(2), "off the map")
	check(h.saved("Ann") != null, "sent to her game to save")
	check_eq(h.saved("Ann").shards, 1234, "saved Dawnshards")

func test_rejoining_after_a_restart_loads_the_saved_character() -> void:
	var a := h.join(2, "Ann")
	a.character.shards = 777
	h.leave(2)
	h.restart()
	var again := h.join(2, "ann", ServerHarness.TOWN)
	check_eq(again.character.shards, 777, "Dawnshards kept")
	check_eq(again.character.name, "Ann", "the name as it was made")

func test_rejoining_puts_you_back_on_the_map_you_left() -> void:
	h.join(2, "Ann", ServerHarness.FIELD)
	h.leave(2)
	h.play(2, "Ann")
	check_eq(h.last(2, &"ev_enter_map")[0], ServerHarness.FIELD, "back on the field")

func test_everyone_is_saved_every_save_interval() -> void:
	var a := h.join(2, "Ann")
	a.character.shards = 55
	h.step(TDServer.SAVE_EVERY - 1)
	check_eq(h.saved("Ann").shards, 0, "not saved yet")
	h.step(1)
	check_eq(h.saved("Ann").shards, 55, "saved on the interval")

func test_players_on_a_map_see_each_other_in_snapshots() -> void:
	h.join(2, "Ann")
	h.join(3, "Bob", ServerHarness.FIELD, 700.0)
	h.step(TDServer.SNAPSHOT_EVERY)
	var peers := (h.snapshot(2)["players"] as Array).map(func(row: Array) -> int: return row[0])
	check_has(peers, 3, "Ann sees Bob")
	check_has(peers, 2, "Ann sees herself")
	check_eq(h.player_info(2, 3)[0], "Bob", "and his name")

func test_players_on_other_maps_get_no_snapshots_of_yours() -> void:
	h.join(2, "Ann")
	h.join(3, "Bob", ServerHarness.TOWN)
	h.step(TDServer.SNAPSHOT_EVERY)
	check_eq((h.snapshot(3)["players"] as Array).size(), 1, "Bob only sees himself")
	check_eq(h.player_info(3, 2), [], "and hears nothing about Ann")

func test_entering_a_map_sends_its_monsters() -> void:
	var m := ServerHarness.monster()
	h.field_with([ServerHarness.spawn(m, 3)])
	h.play(2, "Ann")
	h.move_to(h.server.sessions[2], ServerHarness.FIELD)
	var state: Dictionary = h.last(2, &"ev_enter_map")[2]
	check_eq((state["mobs"] as Array).size(), 3, "three monsters in the state")

func test_events_to_a_peer_that_left_are_not_sent() -> void:
	h.join(2, "Ann")
	h.leave(2)
	h.clear()
	Net.send(2, &"ev_log", ["hi", "ffffff"])
	check_eq(h.api.sent.size(), 0, "nothing sent to a gone peer")

# ---------- making a new character ----------

func test_the_creators_choices_make_a_beginner_with_that_outfit() -> void:
	var made := NewCharacter.new()
	made.outfit[EquipDef.Slot.ARMOR] = Content.item(&"meadow_shirt")
	h.play(2, "Ann", made.to_dict())
	var c: Character = h.server.sessions[2].character
	check_eq(c.job.id, Character.START_JOB, "a Beginner")
	check_eq(c.equipment.at(&"armor").item.id, &"meadow_shirt", "the top picked")
	check_eq(h.last(2, &"ev_joined")[0]["name"], "Ann", "the client hears it")

func test_an_older_clients_look_choices_are_left_out() -> void:
	h.play(2, "Ann", {"look": {"hair": "hair_ponytail"}, "outfit": ["meadow_shirt"]})
	var c: Character = h.server.sessions[2].character
	check_eq(c.equipment.at(&"armor").item.id, &"meadow_shirt", "the top picked")
	check(not c.to_dict().has("appearance"), "no old appearance kept")
	check_eq(c.look, HeroLookDef.all()[0].id, "the first look")

func test_the_look_picked_is_the_characters_and_others_see_it() -> void:
	var made := NewCharacter.new()
	made.look = &"boy"
	h.play(2, "Ann", made.to_dict())
	check_eq(h.server.sessions[2].character.look, &"boy", "the look picked")
	check_eq(h.server.sessions[2].info()[4], &"boy", "in what other players get")

func test_player_info_is_sent_only_when_it_changes() -> void:
	var a := h.join(2, "Ann")
	h.join(3, "Bob", ServerHarness.FIELD, 700.0)
	h.step(TDServer.SNAPSHOT_EVERY)
	var before := h.events(3, &"ev_player_info").size()
	h.step(TDServer.SNAPSHOT_EVERY * 4)
	check_eq(h.events(3, &"ev_player_info").size(), before, "nothing new while nothing changed")
	a.character.guild = "Dawnguard"
	h.step(TDServer.SNAPSHOT_EVERY)
	check_eq(h.player_info(3, 2)[2], "Dawnguard", "her new guild is sent")

func test_a_newcomer_hears_about_everyone_already_there() -> void:
	h.join(2, "Ann")
	h.step(TDServer.SNAPSHOT_EVERY * 2)
	h.join(3, "Bob", ServerHarness.FIELD, 700.0)
	h.step(TDServer.SNAPSHOT_EVERY)
	check_eq(h.player_info(3, 2)[0], "Ann", "Bob hears about Ann")

func test_unchanged_monsters_are_left_out_until_a_full_update() -> void:
	var m := ServerHarness.monster()
	h.field_with([ServerHarness.spawn(m, 3)])
	var a := h.join(2, "Ann")
	var mi: MapInstance = a.map
	check_eq((SnapshotCodec.decode(mi.snapshot(true))["mobs"] as Array).size(), 3, "a full update has all three")
	check_eq((SnapshotCodec.decode(mi.snapshot())["mobs"] as Array).size(), 0, "then none while nothing changed")
	mi.mobs[1].position.x += 40
	var rows: Array = SnapshotCodec.decode(mi.snapshot())["mobs"]
	check_eq(rows.map(func(r: Array) -> int: return r[0]), [1], "only the one that moved")
