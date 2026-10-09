extends TestCase
## Accounts and character select on the server: registering, logging in (and the limits on
## wrong passwords), the local account, making, deleting and playing characters, and that
## an account can only touch its own characters.

const ServerHarness := preload("res://tests/framework/server_helpers.gd")

var h: ServerHarness
var lobby: TDLobby

func before_each() -> void:
	h = ServerHarness.new()
	lobby = h.server.lobby

func after_each() -> void:
	h.close()

func _register(peer: int, user: String, password := "a good password") -> void:
	if not h.api.peers.has(peer):
		h.api.peers.append(peer)
	h.ask(peer, &"req_register", [user, password])

func _login(peer: int, user: String, password := "a good password") -> void:
	if not h.api.peers.has(peer):
		h.api.peers.append(peer)
	h.ask(peer, &"req_login", [user, password])

func _refusal(peer: int) -> String:
	var r := h.last(peer, &"ev_refused")
	return r[0] if not r.is_empty() else ""

# ---------- registering ----------

func test_registering_makes_an_account_and_logs_in() -> void:
	_register(2, "Rowan_7")
	check_eq(h.last(2, &"ev_logged_in"), ["Rowan_7", []], "logged in with no characters")
	check(lobby.accounts.exists("rowan_7"), "saved")
	check_eq(lobby.account_of(2)["username"], "Rowan_7", "on peer 2")

func test_the_password_is_never_saved() -> void:
	_register(2, "rowan", "secret sunrise")
	var f := FileAccess.open(lobby.accounts.folder.path_join("rowan.json"), FileAccess.READ)
	var text := f.get_as_text()
	check(not text.contains("secret sunrise"), "not in the file")
	check(PasswordHash.verify("secret sunrise", JSON.parse_string(text)["password"]), "but it checks")

func test_bad_usernames_and_passwords_are_refused() -> void:
	_register(2, "ro")
	check_eq(_refusal(2), "Usernames are 3 to 16 characters long.", "too short")
	_register(2, "ro wan")
	check_eq(_refusal(2), "Usernames use only letters, numbers and _.", "a space")
	_register(2, "~local")
	check_eq(_refusal(2), "Usernames use only letters, numbers and _.", "the local account")
	_register(2, "rowan", "short")
	check_eq(_refusal(2), "Passwords need at least 8 characters.", "short password")
	check(lobby.account_of(2).is_empty(), "not logged in")

func test_usernames_are_taken_in_any_case() -> void:
	_register(2, "Rowan")
	_register(3, "rOWAN")
	check_eq(_refusal(3), "That username is taken.", "taken")

# ---------- logging in ----------

func test_logging_in_with_the_right_password() -> void:
	_register(2, "rowan")
	h.leave(2)
	_login(3, "ROWAN")
	check_eq(h.last(3, &"ev_logged_in")[0], "rowan", "logged in, any case")

func test_a_wrong_password_and_an_unknown_username_say_the_same() -> void:
	_register(2, "rowan")
	h.leave(2)
	_login(3, "rowan", "not the password")
	check_eq(h.last(3, &"ev_refused"), [TDLobby.WRONG_LOGIN, false], "wrong password")
	_login(4, "nobody_here")
	check_eq(h.last(4, &"ev_refused"), [TDLobby.WRONG_LOGIN, false], "unknown username")
	check(lobby.account_of(3).is_empty() and lobby.account_of(4).is_empty(), "neither logged in")

func test_an_account_logs_in_once_at_a_time() -> void:
	_register(2, "rowan")
	_login(3, "rowan")
	check_eq(_refusal(3), "That account is already logged in.", "refused")

func test_too_many_wrong_passwords_drop_the_connection() -> void:
	_register(2, "rowan")
	h.leave(2)
	for i in LoginGuard.MAX_TRIES - 1:
		_login(3, "rowan", "guess %d" % i)
	check_eq(h.last(3, &"ev_refused")[1], false, "still connected")
	_login(3, "rowan", "last guess")
	check_eq(h.last(3, &"ev_refused"), [TDLobby.WRONG_LOGIN, true], "told it's dropped")
	_login(3, "rowan")
	check(lobby.account_of(3).is_empty(), "no more tries on that connection")
	h.step(TDLobby.KICK_TICKS)
	check(not lobby._kicks.has(3), "dropped")

func test_a_username_with_too_many_wrong_passwords_waits() -> void:
	_register(2, "rowan")
	h.leave(2)
	for i in LoginGuard.MAX_TRIES:
		_login(10 + i, "rowan", "guess %d" % i)
	_login(20, "rowan")
	check_eq(_refusal(20), "Too many wrong passwords. Wait a little and try again.", "locked, even with the right one")
	h.server.tick += LoginGuard.LOCK_TICKS
	_login(21, "rowan")
	check_eq(h.last(21, &"ev_logged_in")[0], "rowan", "works again later")

func test_logging_in_checks_passwords_off_the_game_thread() -> void:
	lobby.background = true
	_register(2, "rowan")
	check_eq(h.count(2, &"ev_logged_in"), 0, "not answered at once")
	for i in 200:
		if h.count(2, &"ev_logged_in") > 0:
			break
		await get_tree().process_frame
	check_eq(h.count(2, &"ev_logged_in"), 1, "answered once the hash is done")

func test_requests_before_logging_in_do_nothing() -> void:
	h.api.peers.append(2)
	h.ask(2, &"req_create_character", ["Ann", ServerHarness.made()])
	h.ask(2, &"req_play", ["Ann"])
	check(not h.server.store.exists("Ann"), "nothing made")
	check(h.server.sessions.is_empty(), "nobody playing")

# ---------- the local account ----------

func test_only_this_games_own_player_gets_the_local_account() -> void:
	h.api.peers.append(1)
	h.ask(1, &"req_local_login")
	check(lobby.account_of(1).is_empty(), "not on a server without a local player")
	h.server.local_player = true
	h.api.peers.append(2)
	h.ask(2, &"req_local_login")
	check(lobby.account_of(2).is_empty(), "not for someone who joined")
	h.ask(1, &"req_local_login")
	check_eq(lobby.account_of(1)["username"], AccountStore.LOCAL, "the host's own player")
	check_eq(h.last(1, &"ev_logged_in")[0], "", "shown without a username")

func test_the_local_account_takes_in_characters_from_before_accounts() -> void:
	var old := Character.create("Oldie")
	h.server.store.save(old)
	h.join(3, "Owned") # someone else's, from an account
	h.leave(3)
	h.server.local_player = true
	lobby.import_legacy_save = true
	h.api.peers.append(1)
	h.ask(1, &"req_local_login")
	check_eq(lobby.account_of(1)["characters"], ["Oldie"] as Array[String], "the unowned one only")

# ---------- characters ----------

func test_making_a_character_adds_it_to_the_account() -> void:
	_register(2, "rowan")
	h.ask(2, &"req_create_character", ["Ann", ServerHarness.made()])
	var r := h.last(2, &"ev_characters")
	check_eq(r[1], "Ann", "picked")
	check_eq((r[0] as Array).size(), 1, "one character")
	check_eq(r[0][0]["name"], "Ann", "named")
	check_eq(r[0][0]["level"], 1, "level 1")
	check_eq(r[0][0]["job"], Content.job(Character.START_JOB).display_name, "a Beginner")
	check(r[0][0]["look"].has("appearance"), "with a look for the preview")
	check(h.server.sessions.is_empty(), "not playing yet")

func test_an_account_has_at_most_six_characters() -> void:
	_register(2, "rowan")
	for i in TDLobby.MAX_CHARACTERS:
		h.ask(2, &"req_create_character", ["Hero%d" % i, ServerHarness.made()])
	h.ask(2, &"req_create_character", ["OneMore", ServerHarness.made()])
	check_eq(_refusal(2), "You can have up to 6 characters on this server.", "refused")
	check(not h.server.store.exists("OneMore"), "not made")

func test_playing_puts_the_character_in_the_world() -> void:
	_register(2, "rowan")
	h.ask(2, &"req_create_character", ["Ann", ServerHarness.made()])
	h.ask(2, &"req_play", ["ann"])
	check_eq(h.last(2, &"ev_joined")[0]["name"], "Ann", "joined as Ann")
	check(h.server.player_of(2) != null, "in the world")
	h.ask(2, &"req_create_character", ["Bob", ServerHarness.made()])
	check(not h.server.store.exists("Bob"), "no making characters while playing")

func test_you_cant_play_or_delete_someone_elses_character() -> void:
	_register(2, "rowan")
	h.ask(2, &"req_create_character", ["Ann", ServerHarness.made()])
	_register(3, "mira")
	h.ask(3, &"req_play", ["Ann"])
	check_eq(_refusal(3), "That isn't one of your characters.", "can't play it")
	h.ask(3, &"req_delete_character", ["Ann", "Ann"])
	check_eq(_refusal(3), "That isn't one of your characters.", "can't delete it")
	check(h.server.store.exists("Ann"), "still there")
	check(h.server.sessions.is_empty(), "nobody playing")

func test_deleting_needs_the_name_typed_and_moves_the_save_aside() -> void:
	_register(2, "rowan")
	h.ask(2, &"req_create_character", ["Ann", ServerHarness.made()])
	h.ask(2, &"req_delete_character", ["Ann", "An"])
	check_eq(_refusal(2), "Type Ann to delete it.", "needs the name")
	check(h.server.store.exists("Ann"), "kept")
	h.ask(2, &"req_delete_character", ["Ann", " ann "])
	check_eq(h.last(2, &"ev_characters"), [[], ""], "gone from the list")
	check(not h.server.store.exists("Ann"), "save gone")
	check(FileAccess.file_exists(h.dir.path_join("deleted/ann.json")), "kept aside for the server's owner")
	h.ask(2, &"req_create_character", ["Ann", ServerHarness.made()])
	check_eq(h.last(2, &"ev_characters")[1], "Ann", "the name is free again")

func test_deleting_takes_the_character_out_of_its_guild_and_buddy_lists() -> void:
	var bob := h.join(3, "Bob")
	h.server.social.guilds["dawn"] = {"name": "Dawn", "master": "Ann", "members": ["Ann", "Bob"]}
	bob.character.buddies.append("Ann")
	_register(2, "rowan")
	h.ask(2, &"req_create_character", ["Ann", ServerHarness.made()])
	h.ask(2, &"req_delete_character", ["Ann", "Ann"])
	check_eq(h.server.social.guilds["dawn"]["members"], ["Bob"], "out of the guild")
	check_eq(h.server.social.guilds["dawn"]["master"], "Bob", "the guild passes on")
	check(not bob.character.buddies.has("Ann"), "off Bob's buddies")

func test_leaving_the_world_goes_back_to_character_select() -> void:
	_register(2, "rowan")
	h.ask(2, &"req_create_character", ["Ann", ServerHarness.made()])
	h.ask(2, &"req_play", ["Ann"])
	h.server.player_of(2).character.shards = 42
	h.ask(2, &"req_leave_character")
	check(h.server.player_of(2) == null, "out of the world")
	check_eq(h.last(2, &"ev_characters")[1], "Ann", "back on the list with Ann picked")
	check_eq(h.server.store.load_character("Ann").shards, 42, "saved")
	check_eq(lobby.account_of(2)["username"], "rowan", "still logged in")

func test_disconnecting_logs_out() -> void:
	_register(2, "rowan")
	h.leave(2)
	check(lobby.account_of(2).is_empty(), "logged out")
	_login(3, "rowan")
	check_eq(h.last(3, &"ev_logged_in")[0], "rowan", "can log in again")
