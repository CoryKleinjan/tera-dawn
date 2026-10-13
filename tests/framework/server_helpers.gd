extends RefCounted
## Drives a TDServer directly for server tests: no TDWorld, no window, no real time.
##
##   const ServerHarness := preload("res://tests/framework/server_helpers.gd")
##   var h := ServerHarness.new()      # a server with a fresh save folder
##   var p := h.join(2, "Ann")          # a player on peer 2, on the test field
##   h.step(10)                         # ten server ticks, run by hand
##   h.events(2, &"ev_log")             # the args of every ev_log peer 2 was sent
##   h.close()                          # frees the server, deletes the saves, undoes Content changes
##
## Events are caught with a MultiplayerAPI set on /root/Net only (`Capture`): Net.send
## sees the fake peers as connected and its rpc_id lands in `Capture._rpc` instead of the
## network, so no game code needs a hook. Requests can go through Net's req_* methods with
## `ask`, which makes the fake peer the remote sender.
##
## Maps, NPCs, monsters and quests made here (`add_map`, `monster`, `npc`, `add_quest`)
## are put in Content for the test and taken out again by `close`.

const FIELD := &"test_field"
const TOWN := &"test_town"
const MARKET := &"test_market"
const GROUND := 600.0

## A MultiplayerAPI that records every rpc instead of sending it.
class Capture extends MultiplayerAPIExtension:
	## [peer, method, args] in the order they were sent.
	var sent: Array = []
	var peers := PackedInt32Array()
	var sender := 0
	var _peer: MultiplayerPeer = OfflineMultiplayerPeer.new()

	func _poll() -> Error:
		return OK

	func _rpc(peer: int, _object: Object, method: StringName, args: Array) -> Error:
		sent.append([peer, method, args])
		return OK

	func _get_unique_id() -> int:
		return 1

	func _get_peer_ids() -> PackedInt32Array:
		return peers

	func _get_remote_sender_id() -> int:
		return sender

	func _set_multiplayer_peer(p: MultiplayerPeer) -> void:
		_peer = p

	func _get_multiplayer_peer() -> MultiplayerPeer:
		return _peer

	func _object_configuration_add(_object: Object, _configuration: Variant) -> Error:
		return OK

	func _object_configuration_remove(_object: Object, _configuration: Variant) -> Error:
		return OK

var server: TDServer
var api := Capture.new()
var dir := ""
var _old_server: TDServer
var _added := {} # Content table name -> ids added

static var _runs := 0

func _init() -> void:
	_runs += 1
	dir = "user://test_server_%d_%d" % [OS.get_process_id(), _runs]
	_wipe(dir)
	Engine.get_main_loop().set_multiplayer(api, ^"/root/Net")
	_old_server = Net.server
	add_map(field_def())
	add_map(town_def())
	_new_server()

## A server on `dir` that checks passwords at once (on this thread, with few rounds).
func _new_server() -> void:
	PasswordHash.rounds = 64
	server = TDServer.new(dir)
	server.lobby.background = false
	Net.server = server

## Frees the server, deletes its saves and takes out everything put in Content.
func close() -> void:
	if server:
		server.free()
		server = null
	Net.server = _old_server
	PasswordHash.rounds = PasswordHash.ROUNDS
	Engine.get_main_loop().set_multiplayer(null, ^"/root/Net")
	for table: String in _added:
		var t: Dictionary = Content.get(table)
		for id in _added[table]:
			t.erase(id)
	_added.clear()
	_wipe(dir)

## A fresh server on the same save folder (as if it restarted).
func restart() -> void:
	server.free()
	_new_server()
	api.peers = PackedInt32Array()

static func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

# ---------- players ----------

## The character creator's default choices, to join with a new character.
static func made() -> Dictionary:
	return NewCharacter.new().to_dict()

## Plays `char_name` on `peer` (making them with the creator's defaults if they're new) and
## puts them on `map` at `x` (on the floor). Each character gets its own account (see
## `log_in`). Clears the events sent so far.
func join(peer: int, char_name: String, map := FIELD, x := 300.0) -> SimPlayer:
	play(peer, char_name)
	var p: SimPlayer = server.sessions.get(peer)
	if p and map != p.map.def.id:
		move_to(p, map, x)
	elif p:
		p.position = Vector2(x, p.map.layout.platforms[0].y)
	clear()
	return p

## Logs `peer` in to `username`'s account without a password (made if it's new).
func log_in(peer: int, username: String) -> Dictionary:
	if not api.peers.has(peer):
		api.peers.append(peer)
	var a := server.lobby.accounts.load_account(username)
	if a.is_empty():
		a = AccountStore.make(username, {})
		server.lobby.accounts.save(a)
	server.lobby.log_in(peer, a)
	return a

## Logs in to the account "acct_<name>", makes `char_name` there if it's new, and plays it.
func play(peer: int, char_name: String, look := {}) -> void:
	var a := log_in(peer, "acct_" + char_name.to_lower().replace(" ", "_"))
	if not AccountStore.owns(a, char_name):
		server.lobby.on_create(peer, char_name, look if not look.is_empty() else made())
	server.lobby.on_play(peer, char_name)

## Takes `peer` off the server the way a disconnect does.
func leave(peer: int) -> void:
	server.disconnected(peer)
	var i := api.peers.find(peer)
	if i >= 0:
		api.peers.remove_at(i)

## Moves a player to another map like a portal does.
func move_to(p: SimPlayer, map: StringName, x := 300.0) -> void:
	server.enter_map(p, map, x)

## Puts a player exactly at `x` on the floor (or `y`), as if they had walked there.
func place(p: SimPlayer, x: float, y := GROUND) -> void:
	p.position = Vector2(x, y)
	p.since_move = 0

## Sends a request through Net as `peer`, e.g. ask(2, &"req_loot").
func ask(peer: int, request: StringName, args := []) -> void:
	api.sender = peer
	Net.callv(request, args)
	api.sender = 0

# ---------- time ----------

## Runs `n` server ticks.
func step(n := 1) -> void:
	for i in n:
		server._physics_process(1.0 / 60.0)

# ---------- events ----------

## The args of every `event` sent to `peer` (all events when `event` is empty).
func events(peer: int, event: StringName = &"") -> Array:
	var out := []
	for e in api.sent:
		if e[0] == peer and (event == &"" or e[1] == event):
			out.append(e[2])
	return out

func count(peer: int, event: StringName) -> int:
	return events(peer, event).size()

## The last args of `event` sent to `peer`, or [] if none.
func last(peer: int, event: StringName) -> Array:
	var all := events(peer, event)
	return all[-1] if not all.is_empty() else []

## The latest snapshot `peer` was sent, decoded (SnapshotCodec.decode), or {}.
func snapshot(peer: int) -> Dictionary:
	var ev := last(peer, &"ev_snapshot")
	return SnapshotCodec.decode(ev[0]) if not ev.is_empty() else {}

## The latest info `peer` was sent about player `of` ([name, level, job, guild, chair, pet,
## look, shop sign]), or [].
func player_info(peer: int, of: int) -> Array:
	for i in range(events(peer, &"ev_player_info").size() - 1, -1, -1):
		var ev: Array = events(peer, &"ev_player_info")[i]
		if ev[0] == of:
			return ev[1]
	return []

## The text of every ev_log `peer` was sent.
func logs(peer: int) -> Array[String]:
	var out: Array[String] = []
	for a in events(peer, &"ev_log"):
		out.append(a[0])
	return out

## Whether any ev_log to `peer` contains `text`.
func told(peer: int, text: String) -> bool:
	for l in logs(peer):
		if l.contains(text):
			return true
	return false

func clear() -> void:
	api.sent.clear()

# ---------- content made for tests ----------

func _register(table: String, id: StringName, res: Resource) -> void:
	var t: Dictionary = Content.get(table)
	t[id] = res
	if not _added.has(table):
		_added[table] = []
	_added[table].append(id)

## Puts a MapDef in Content until close().
func add_map(m: MapDef) -> MapDef:
	_register("maps", m.id, m)
	return m

func add_quest(q: QuestDef) -> QuestDef:
	_register("quests", q.id, q)
	return q

func add_item(it: ItemDef) -> ItemDef:
	_register("items", it.id, it)
	return it

func add_cutscene(c: CutsceneDef) -> CutsceneDef:
	_register("cutscenes", c.id, c)
	return c

## A flat 2000 x 700 field (floor at y 600) whose town is TOWN.
static func field_def(id := FIELD) -> MapDef:
	var m := MapDef.new()
	m.id = id
	m.display_name = "Test Field"
	m.width = 2000
	m.height = 700
	m.ground_y = int(GROUND)
	m.start_x = 300.0
	m.return_map = TOWN
	return m

## A flat town.
static func town_def(id := TOWN) -> MapDef:
	var m := field_def(id)
	m.display_name = "Test Town"
	m.town = true
	m.return_map = &""
	m.start_x = 500.0
	return m

## A one-way platform for a MapDef.
static func platform(x: float, y: float, width: float) -> PlatformDef:
	var d := PlatformDef.new()
	d.x = x
	d.y = y
	d.width = width
	return d

## A monster that never walks or misses its touch: level 1, 1 HP, `exp` EXP, no drops.
static func monster(id := &"test_mob", hp := 1, exp := 10) -> MonsterDef:
	var d := MonsterDef.new()
	d.id = id
	d.display_name = String(id).capitalize()
	d.level = 1
	d.max_hp = hp
	d.attack = 1
	d.exp_reward = exp
	d.speed = 0.0
	d.size = Vector2(36, 30)
	d.respawn_ticks = Vector2i(100, 100)
	return d

static func drop(item: ItemDef, amount := 1, chance := 1.0) -> DropEntry:
	var e := DropEntry.new()
	e.item = item
	e.chance = chance
	e.min_amount = amount
	e.max_amount = amount
	return e

static func spawn(m: MonsterDef, count := 1, platform_index := 0) -> SpawnDef:
	var s := SpawnDef.new()
	s.monster = m
	s.count = count
	s.platform = platform_index
	return s

## An NPC standing at `x` on the floor of `map`.
static func npc(map: MapDef, id: StringName, x: float) -> NpcDef:
	var n := NpcDef.new()
	n.id = id
	n.display_name = String(id).capitalize()
	var at := NpcPlacement.new()
	at.npc = n
	at.x = x
	map.npcs.append(at)
	return n

static func shop(entries: Array) -> ShopDef:
	var s := ShopDef.new()
	s.id = &"test_shop"
	for e: Array in entries:
		var line := ShopEntry.new()
		line.item = e[0]
		line.price = e[1]
		s.items.append(line)
	return s

## A field like FIELD with these spawns, put in Content and returned with its instance
## made fresh (any earlier one is dropped).
func field_with(spawns: Array, id := FIELD) -> MapInstance:
	var m := field_def(id)
	for s in spawns:
		m.spawns.append(s)
	add_map(m)
	server.maps.erase(id)
	return server.map_instance(id)

## Makes `p`'s Monster Book page for `m` complete, so kills never roll a card (test
## monsters have none). The "first page" achievement that would bring is marked as had.
static func no_cards(p: SimPlayer, m: MonsterDef) -> void:
	p.character.book.pages[m.id] = [0, CardDef.SET]
	if not p.character.achievements.has("first_page"):
		p.character.achievements.append("first_page")
