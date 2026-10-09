extends TestCase
## Joining and leaving the server, and characters being saved and loaded between visits.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness

func before_each() -> void:
	h = ServerHarness.new()

func after_each() -> void:
	h.close()

func test_join_sends_the_character_then_the_starting_map() -> void:
	h.api.peers.append(2)
	h.server.join(2, "Ann")
	check_eq(h.count(2, &"ev_joined"), 1, "ev_joined sent once")
	check_eq(h.count(2, &"ev_enter_map"), 1, "ev_enter_map sent once")
	var kinds := []
	for e in h.api.sent:
		kinds.append(e[1])
	check(kinds.find(&"ev_joined") < kinds.find(&"ev_enter_map"), "the character comes before the map")
	check_eq(h.last(2, &"ev_joined")[0]["name"], "Ann", "the joined character's name")
	check_eq(h.last(2, &"ev_enter_map")[0], Character.START_MAP, "a new character starts on the starting map")
	check_eq(h.events(2).size(), h.api.sent.size(), "every event went to peer 2")

func test_new_character_is_a_level_1_beginner_with_full_health() -> void:
	var p := h.join(2, "Ann")
	var c := p.character
	check_eq(c.level, 1, "level")
	check_eq(c.job.id, Character.START_JOB, "job")
	check_eq(c.health.hp, c.max_hp(), "full HP")
	check_eq(c.mp, c.max_mp(), "full MP")
	check_eq(c.shards, 0, "no Dawnshards")

func test_empty_name_is_refused() -> void:
	h.api.peers.append(2)
	h.server.join(2, "  !!  ")
	check_eq(h.last(2, &"ev_join_failed"), ["Please pick a name."], "why")
	check(not h.server.sessions.has(2), "no session made")

func test_name_already_playing_is_refused_in_any_case() -> void:
	h.join(2, "Ann")
	h.api.peers.append(3)
	h.server.join(3, "aNN")
	check_eq(h.last(3, &"ev_join_failed"), ["aNN is already playing."], "why")
	check(not h.server.sessions.has(3), "second session not made")
	check_eq(h.server.sessions.size(), 1, "one player")

func test_names_lose_characters_that_are_not_allowed() -> void:
	var p := h.join(2, "  An<n>!  ")
	check_eq(p.character.name, "Ann", "cleaned name")

func test_leaving_saves_the_character_and_tells_the_map() -> void:
	var a := h.join(2, "Ann")
	h.join(3, "Bob")
	a.character.shards = 1234
	h.leave(2)
	check_eq(h.last(3, &"ev_player_left"), [2], "Bob sees Ann leave")
	check(not h.server.sessions.has(2), "session gone")
	check(not h.server.maps[ServerHarness.FIELD].players.has(2), "off the map")
	check(h.server.store.exists("Ann"), "save file written")
	check_eq(h.server.store.load_character("Ann").shards, 1234, "saved Dawnshards")

func test_rejoining_after_a_restart_loads_the_saved_character() -> void:
	var a := h.join(2, "Ann")
	a.character.shards = 777
	a.character.gain_xp(a.character.xp_need())
	h.leave(2)
	h.restart()
	var again := h.join(2, "ann", ServerHarness.TOWN)
	check_eq(again.character.shards, 777, "Dawnshards kept")
	check_eq(again.character.level, 2, "level kept")
	check_eq(again.character.name, "ann", "the name is the one typed")

func test_rejoining_puts_you_back_on_the_map_you_left() -> void:
	h.join(2, "Ann", ServerHarness.FIELD)
	h.leave(2)
	h.api.peers.append(2)
	h.server.join(2, "Ann")
	check_eq(h.last(2, &"ev_enter_map")[0], ServerHarness.FIELD, "back on the field")

func test_everyone_is_saved_every_save_interval() -> void:
	var a := h.join(2, "Ann")
	a.character.shards = 55
	h.step(TDServer.SAVE_EVERY - 1)
	check_eq(h.server.store.load_character("Ann").shards, 0, "not saved yet")
	h.step(1)
	check_eq(h.server.store.load_character("Ann").shards, 55, "saved on the interval")

func test_players_on_a_map_see_each_other_in_snapshots() -> void:
	h.join(2, "Ann")
	h.join(3, "Bob", ServerHarness.FIELD, 700.0)
	h.step(TDServer.SNAPSHOT_EVERY)
	var snap: Dictionary = h.last(2, &"ev_snapshot")[0]
	var names := (snap["players"] as Array).map(func(row: Array) -> String: return row[1])
	check_has(names, "Bob", "Ann sees Bob")
	check_has(names, "Ann", "Ann sees herself")

func test_players_on_other_maps_get_no_snapshots_of_yours() -> void:
	h.join(2, "Ann")
	h.join(3, "Bob", ServerHarness.TOWN)
	h.step(TDServer.SNAPSHOT_EVERY)
	var snap: Dictionary = h.last(3, &"ev_snapshot")[0]
	check_eq((snap["players"] as Array).size(), 1, "Bob only sees himself")

func test_entering_a_map_sends_its_monsters() -> void:
	var m := ServerHarness.monster()
	h.field_with([ServerHarness.spawn(m, 3)])
	h.api.peers.append(2)
	h.server.join(2, "Ann")
	h.move_to(h.server.sessions[2], ServerHarness.FIELD)
	var state: Dictionary = h.last(2, &"ev_enter_map")[2]
	check_eq((state["mobs"] as Array).size(), 3, "three monsters in the state")

func test_events_to_a_peer_that_left_are_not_sent() -> void:
	h.join(2, "Ann")
	h.leave(2)
	h.clear()
	Net.send(2, &"ev_log", ["hi", "ffffff"])
	check_eq(h.api.sent.size(), 0, "nothing sent to a gone peer")
