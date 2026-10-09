class_name TDLobby
extends RefCounted
## Everything before a player is in the world, run by the server: registering an account,
## logging in, the account's list of characters (character select), making and deleting
## characters, and picking one to play. Accounts are this server's own (AccountStore);
## characters are saved by the server's CharacterStore and belong to one account.
##
## The player at the keyboard of a single-player or hosted game uses the LOCAL account and
## needs no password (`on_local_login`). Everyone else registers or logs in with a username
## and password, which are checked off the game thread so hashing never stalls the world.

const MAX_CHARACTERS := 6
const WRONG_LOGIN := "Wrong username or password."
## Ticks between telling a connection it used up its tries and dropping it.
const KICK_TICKS := 60
## What a missing account's password is checked against, so a wrong username takes as
## long to answer as a wrong password and doesn't give away which usernames exist.
const _NOBODY := {"algo": PasswordHash.ALGO, "salt": "00000000000000000000000000000000",
	"hash": "0000000000000000000000000000000000000000000000000000000000000000"}

var server: TDServer
var accounts: AccountStore
var guard := LoginGuard.new()
## peer -> the account (AccountStore record) logged in on it
var logins := {}
## Whether the LOCAL account takes in characters saved before accounts existed (and the
## older single-player user://save.json) when it's first made. On for a host or single player.
var import_legacy_save := false
## Run password hashing on a worker thread. Tests turn it off to get answers at once.
var background := true
## peer -> number of the password check running for it
var _busy := {}
## password check number -> its WorkerThreadPool task
var _tasks := {}
var _checks := 0
## peer -> tick to drop the connection at
var _kicks := {}

func _init(s: TDServer, save_folder: String) -> void:
	server = s
	accounts = AccountStore.new(save_folder)

func step(tick: int) -> void:
	for peer in _kicks.keys():
		if tick >= int(_kicks[peer]):
			_kicks.erase(peer)
			Net.kick(peer)
			server.disconnected(peer)

## The account logged in on `peer`, or {}.
func account_of(peer: int) -> Dictionary:
	return logins.get(peer, {})

## A connection closed: forget its login.
func dropped(peer: int) -> void:
	logins.erase(peer)
	_busy.erase(peer)
	_kicks.erase(peer)
	guard.forget_peer(peer)

# ---------- requests (see Net) ----------

func on_register(peer: int, username: String, password: String) -> void:
	if not _can_log_in(peer):
		return
	username = username.strip_edges()
	var why := AccountStore.username_problem(username)
	if why == "":
		why = AccountStore.password_problem(password)
	if why == "" and accounts.exists(username):
		why = "That username is taken."
	if why != "":
		refuse(peer, why)
		return
	_off_thread(peer, func() -> Dictionary: return PasswordHash.make(password), func(record: Dictionary) -> void:
		if accounts.exists(username):
			refuse(peer, "That username is taken.")
			return
		var a := AccountStore.make(username, record)
		accounts.save(a)
		print("Account %s registered (peer %d)" % [username, peer])
		log_in(peer, a))

func on_login(peer: int, username: String, password: String) -> void:
	if not _can_log_in(peer):
		return
	username = username.strip_edges()
	if guard.locked(username, server.tick):
		refuse(peer, "Too many wrong passwords. Wait a little and try again.")
		return
	var a := accounts.load_account(username) if AccountStore.username_problem(username) == "" else {}
	var record: Dictionary = a.get("password", {}) if not a.is_empty() else _NOBODY.merged({"rounds": PasswordHash.rounds})
	_off_thread(peer, func() -> bool: return PasswordHash.verify(password, record), func(ok: bool) -> void:
		if not ok or a.is_empty():
			var out := guard.failed(peer, username, server.tick)
			Net.send(peer, &"ev_refused", [WRONG_LOGIN, out])
			if out:
				_kicks[peer] = server.tick + KICK_TICKS
			return
		guard.succeeded(username)
		if _logged_in(a["username"]):
			refuse(peer, "That account is already logged in.")
			return
		log_in(peer, a))

## The player at this game's own keyboard (single player or host) logs in to LOCAL.
func on_local_login(peer: int) -> void:
	if peer != MultiplayerPeer.TARGET_PEER_SERVER or not server.local_player or not _can_log_in(peer):
		return
	var a := accounts.load_account(AccountStore.LOCAL)
	if a.is_empty():
		a = AccountStore.make(AccountStore.LOCAL, {})
		if import_legacy_save:
			_adopt_old_characters(a)
		accounts.save(a)
	log_in(peer, a)

func on_create(peer: int, raw_name: String, made: Dictionary) -> void:
	var a := _choosing(peer)
	if a.is_empty():
		return
	if (a["characters"] as Array).size() >= MAX_CHARACTERS:
		refuse(peer, "You can have up to %d characters on this server." % MAX_CHARACTERS)
		return
	var char_name := CharacterStore.clean_name(raw_name)
	if char_name == "":
		refuse(peer, "Please pick a name.")
		return
	if server.store.exists(char_name):
		refuse(peer, "%s is taken. Try another name." % char_name)
		return
	var c := Character.create(char_name, Character.START_JOB, NewCharacter.from_dict(made))
	server.store.save(c)
	a["characters"].append(c.name)
	accounts.save(a)
	send_characters(peer, c.name)

## Deletes one of the account's characters. `typed` must repeat its name.
func on_delete(peer: int, char_name: String, typed: String) -> void:
	var a := _choosing(peer)
	if a.is_empty():
		return
	var i := AccountStore.index_of(a, char_name)
	if i < 0:
		refuse(peer, "That isn't one of your characters.")
		return
	var real: String = a["characters"][i]
	if typed.strip_edges().to_lower() != real.to_lower():
		refuse(peer, "Type %s to delete it." % real)
		return
	server.store.remove(real)
	server.social.forget(real)
	a["characters"].remove_at(i)
	accounts.save(a)
	print("%s deleted %s" % [a["username"], real])
	send_characters(peer, "")

func on_play(peer: int, char_name: String) -> void:
	var a := _choosing(peer)
	if a.is_empty():
		return
	var i := AccountStore.index_of(a, char_name)
	if i < 0:
		refuse(peer, "That isn't one of your characters.")
		return
	var c := server.store.load_character(a["characters"][i])
	if c == null:
		refuse(peer, "%s's save couldn't be read." % a["characters"][i])
		return
	server.enter_game(peer, c)

## Back to character select from the world, still logged in.
func on_leave_character(peer: int) -> void:
	var p := server.player_of(peer)
	if p == null or not logins.has(peer):
		return
	server.leave(peer)
	send_characters(peer, p.character.name)

# ---------- logging in ----------

## Logs `account` in on `peer` and sends them to character select.
func log_in(peer: int, account: Dictionary) -> void:
	logins[peer] = account
	var shown: String = account["username"] if account["username"] != AccountStore.LOCAL else ""
	Net.send(peer, &"ev_logged_in", [shown, slots(account)])

## Tells `peer` why something they asked for didn't happen.
func refuse(peer: int, why: String) -> void:
	Net.send(peer, &"ev_refused", [why, false])

## The account's characters as character select shows them, in the order they were made.
func slots(account: Dictionary) -> Array:
	var out := []
	for n: String in account["characters"]:
		var c := server.store.load_character(n)
		if c:
			out.append({"name": c.name, "level": c.level, "job": c.job.display_name, "look": c.look()})
	return out

## Sends the account's characters again, with `selected` picked.
func send_characters(peer: int, selected: String) -> void:
	Net.send(peer, &"ev_characters", [slots(account_of(peer)), selected])

func _can_log_in(peer: int) -> bool:
	return not logins.has(peer) and not _busy.has(peer) and not _kicks.has(peer)

func _logged_in(username: String) -> bool:
	for a: Dictionary in logins.values():
		if AccountStore.key(a["username"]) == AccountStore.key(username):
			return true
	return false

## The account of a logged-in peer who isn't in the world, or {}.
func _choosing(peer: int) -> Dictionary:
	if server.player_of(peer) != null:
		return {}
	return account_of(peer)

## Runs `work` (password hashing) on a worker thread and `done` with its result back on the
## game thread, unless the peer left in the meantime.
func _off_thread(peer: int, work: Callable, done: Callable) -> void:
	_checks += 1
	var check := _checks
	_busy[peer] = check
	if not background:
		_finish(peer, check, done, work.call())
		return
	_tasks[check] = WorkerThreadPool.add_task(func() -> void:
		_finish.call_deferred(peer, check, done, work.call()))

func _finish(peer: int, check: int, done: Callable, result: Variant) -> void:
	if _tasks.has(check):
		WorkerThreadPool.wait_for_task_completion(_tasks[check])
		_tasks.erase(check)
	if not is_instance_valid(server) or _busy.get(peer) != check:
		return
	_busy.erase(peer)
	done.call(result)

## Gives a new LOCAL account the characters saved here before accounts existed, that no
## other account owns, and the single-player save from before multiplayer.
func _adopt_old_characters(local: Dictionary) -> void:
	var owned := {}
	for a in accounts.all():
		for n: String in a["characters"]:
			owned[n.to_lower()] = true
	var old := CharacterStore.load_file("user://save.json", "")
	if old and old.name != "" and not server.store.exists(old.name):
		server.store.save(old)
	for n in server.store.saved_names():
		if (local["characters"] as Array).size() < MAX_CHARACTERS and not owned.has(n.to_lower()):
			local["characters"].append(n)
			owned[n.to_lower()] = true
