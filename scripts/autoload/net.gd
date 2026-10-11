extends Node
## Autoload "Net": starts or joins a game, and carries every message between the game and
## the server. This file is the whole network protocol: requests (req_*) go from a client
## to the server, events (ev_*) go from the server to clients.
##
## There is always a server, even in single player: it runs in the same game, and the
## messages go straight to it without touching the network. So single player, hosting and
## joining all play by the same rules.

enum Mode { NONE, SINGLE, HOST, CLIENT, DEDICATED }

const DEFAULT_PORT := 7350
const MAX_PLAYERS := 32
const LOST := "Lost the connection to the server."
const HOST_ENDED := "The host ended the game."
## Physics ticks a host's connection stays open after it stops, so the players connected
## to it get told the game ended (closing at once would drop the message).
const GOODBYE_TICKS := 30

## Logged in: `username` and `characters` are filled in, show character select.
signal logged_in
## The account's characters changed (`characters`); `selected` is the one to pick, if any.
signal characters_changed(selected: String)
## The server said no (wrong password, a name that's taken...) or couldn't be reached;
## `reason` says why, in words for the player.
signal refused(reason: String)
## The server put our character in the world (Game.me is filled in).
signal joined
## The connection to the server closed: lost, or the host ended the game. `why` says
## which, in words for the player.
signal disconnected(why: String)

var mode := Mode.NONE
## The server, when this game runs one (single player, host or dedicated).
var server: TDServer
## Where events for the player are shown, when this game has a client.
var world: TDWorld
## Where the server keeps accounts and characters. Tests point it somewhere else.
var save_dir := "user://characters"
## The account we're logged in to ("" for the local account of single player and host).
var username := ""
## The account's characters as character select shows them: {name, level, job, look}.
var characters: Array = []
## [register?, username, password] to send once the connection is up. Cleared as soon as
## it's sent; the password is never kept anywhere else.
var _pending: Array = []
## A host's connection after it stopped, open for `_leaving_t` more ticks (GOODBYE_TICKS).
var _leaving: ENetMultiplayerPeer
var _leaving_t := 0

func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(peer: int) -> void:
		if server:
			server.disconnected(peer))
	multiplayer.connected_to_server.connect(func() -> void:
		if not _pending.is_empty():
			ask(&"req_register" if _pending[0] else &"req_login", [_pending[1], _pending[2]])
			_pending = [])
	multiplayer.connection_failed.connect(func() -> void:
		stop()
		refused.emit("Couldn't reach the server."))
	multiplayer.server_disconnected.connect(func() -> void:
		stop()
		disconnected.emit(LOST))

func _physics_process(_delta: float) -> void:
	if _leaving:
		_leaving.poll()
		_leaving_t -= 1
		if _leaving_t <= 0:
			_close_leaving()

func is_playing() -> bool:
	return mode != Mode.NONE and mode != Mode.DEDICATED

# ---------- starting and stopping ----------

## Single player: a private server inside this game, not reachable from the network. You
## play on its local account, so `logged_in` follows at once.
func play_single() -> void:
	stop()
	mode = Mode.SINGLE
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_server(true)
	ask(&"req_local_login", [Settings.dev.login_mode()])

## Host: play on the local account, and let other players register and log in to this game
## on `port`. Returns "" or what went wrong.
func host(port := DEFAULT_PORT) -> String:
	stop()
	_close_leaving()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS) != OK:
		return "Couldn't open port %d. Is another game using it?" % port
	if peer.host.dtls_server_setup(TDTls.server_options(save_dir)) != OK:
		peer.close()
		return "Couldn't set up encryption."
	mode = Mode.HOST
	multiplayer.multiplayer_peer = peer
	_start_server(true)
	ask(&"req_local_login", [Settings.dev.login_mode()])
	return ""

## Connects to a server and logs in (or registers a new account first, if `register`).
## `logged_in` or `refused` follows. Returns "" or what went wrong right away.
func log_in(address: String, username_: String, password: String, register := false, port := DEFAULT_PORT) -> String:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		return "Couldn't connect to %s." % address
	if peer.host.dtls_client_setup(address, TDTls.client_options(address)) != OK:
		peer.close()
		return "Couldn't set up encryption."
	mode = Mode.CLIENT
	_pending = [register, username_, password]
	multiplayer.multiplayer_peer = peer
	return ""

## A server with no player of its own (run with `-- --server`). Returns "" or what went wrong.
func run_dedicated(port := DEFAULT_PORT) -> String:
	stop()
	_close_leaving()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS) != OK:
		return "Couldn't open port %d." % port
	if peer.host.dtls_server_setup(TDTls.server_options(save_dir)) != OK:
		peer.close()
		return "Couldn't set up encryption (see %s/tls)." % save_dir
	mode = Mode.DEDICATED
	multiplayer.multiplayer_peer = peer
	_start_server(false)
	print("Tera's Dawn server listening on port %d" % port)
	return ""

## Whether other players are connected to the game this one hosts.
func has_guests() -> bool:
	return mode == Mode.HOST and not multiplayer.get_peers().is_empty()

## Leaves the game and logs out (saving everyone if this game is the server). A host tells
## the players connected to it that the game has ended.
func stop() -> void:
	var guests := has_guests()
	if guests:
		for peer in multiplayer.get_peers():
			send(peer, &"ev_host_ended", [])
	if server:
		server.save_all()
		server.queue_free()
		server = null
	var old := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if guests:
		_close_later(old as ENetMultiplayerPeer)
	elif old and not old is OfflineMultiplayerPeer:
		old.close()
	mode = Mode.NONE
	username = ""
	characters = []
	_pending = []

## Keeps a stopped host's connection open for GOODBYE_TICKS so what was just sent (the
## game ending) gets there. Sent at once too, in case the game is quitting.
func _close_later(peer: ENetMultiplayerPeer) -> void:
	_close_leaving()
	peer.host.flush()
	_leaving = peer
	_leaving_t = GOODBYE_TICKS

func _close_leaving() -> void:
	if _leaving:
		_leaving.close()
		_leaving = null

func _start_server(local_player: bool) -> void:
	server = TDServer.new(save_dir)
	server.name = "Server"
	server.local_player = local_player
	add_child(server)

# ---------- character select ----------

## Makes a new character on this account. `characters_changed` (with it selected) or
## `refused` follows.
func create_character(char_name: String, made: NewCharacter) -> void:
	ask(&"req_create_character", [char_name, made.to_dict()])

## Deletes one of this account's characters; `typed` is what the player typed to confirm.
func delete_character(char_name: String, typed: String) -> void:
	ask(&"req_delete_character", [char_name, typed])

## Plays one of this account's characters. `joined` or `refused` follows.
func play(char_name: String) -> void:
	ask(&"req_play", [char_name])

## Leaves the world for character select, still logged in.
func leave_character() -> void:
	ask(&"req_leave_character")

## Where a connection comes from (its IP address), or "peer <id>" when that isn't known
## (single player, tests).
func address_of(peer: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var conn: ENetPacketPeer = enet.get_peer(peer) if enet and multiplayer.get_peers().has(peer) else null
	return conn.get_remote_address() if conn else "peer %d" % peer

## Drops a connection (the server, after too many wrong passwords).
func kick(peer: int) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.get_peers().has(peer):
		multiplayer.multiplayer_peer.disconnect_peer(peer)

## Sends an event from the server to one peer (skipping peers that have just left).
func send(peer: int, event: StringName, args: Array) -> void:
	if peer == multiplayer.get_unique_id() or multiplayer.get_peers().has(peer):
		callv(&"rpc_id", [peer, event] + args)

## Sends a request from this player to the server, e.g. Net.ask(&"req_use_item", [slot]).
func ask(request: StringName, args := []) -> void:
	if mode != Mode.NONE:
		callv(&"rpc_id", [1, request] + args)

func _sender() -> int:
	return multiplayer.get_remote_sender_id()

# ---------- requests: client -> server ----------

@rpc("any_peer", "call_local", "reliable")
func req_register(username_: String, password: String) -> void:
	if server:
		server.lobby.on_register(_sender(), username_, password)

@rpc("any_peer", "call_local", "reliable")
func req_login(username_: String, password: String) -> void:
	if server:
		server.lobby.on_login(_sender(), username_, password)

## Single player or host: the player at this game's keyboard logs in to the local account.
## `test` (a TestCharacters.Mode) asks for the test characters' account instead; the server
## only honours it in a debug build.
@rpc("any_peer", "call_local", "reliable")
func req_local_login(test := 0) -> void:
	if server:
		server.lobby.on_local_login(_sender(), test as TestCharacters.Mode)

@rpc("any_peer", "call_local", "reliable")
func req_create_character(char_name: String, made: Dictionary) -> void:
	if server:
		server.lobby.on_create(_sender(), char_name, made)

@rpc("any_peer", "call_local", "reliable")
func req_delete_character(char_name: String, typed: String) -> void:
	if server:
		server.lobby.on_delete(_sender(), char_name, typed)

@rpc("any_peer", "call_local", "reliable")
func req_play(char_name: String) -> void:
	if server:
		server.lobby.on_play(_sender(), char_name)

@rpc("any_peer", "call_local", "reliable")
func req_leave_character() -> void:
	if server:
		server.lobby.on_leave_character(_sender())

@rpc("any_peer", "call_local", "unreliable_ordered")
func req_move(at: Vector2, face: int, anim: StringName, climbing: bool) -> void:
	if server:
		server.on_move(_sender(), at, face, anim, climbing)

@rpc("any_peer", "call_local", "reliable")
func req_skill(skill_id: StringName, at: Vector2, face: int) -> void:
	if server:
		server.on_skill(_sender(), skill_id, at, face)

@rpc("any_peer", "call_local", "reliable")
func req_portal() -> void:
	if server:
		server.on_portal(_sender())

@rpc("any_peer", "call_local", "reliable")
func req_loot() -> void:
	if server:
		server.on_loot(_sender())

@rpc("any_peer", "call_local", "reliable")
func req_use_item(slot: int) -> void:
	if server:
		server.on_use_item(_sender(), slot)

## Sit on the chair, or bring out the pet, in Setup slot `slot` (again to stop).
@rpc("any_peer", "call_local", "reliable")
func req_setup(slot: int) -> void:
	if server:
		server.on_setup(_sender(), slot)

@rpc("any_peer", "call_local", "reliable")
func req_chat(text: String) -> void:
	if server:
		server.social.on_chat(_sender(), text)

@rpc("any_peer", "call_local", "reliable")
func req_social(action: StringName, arg: String) -> void:
	if server:
		server.social.on_social(_sender(), action, arg)

@rpc("any_peer", "call_local", "reliable")
func req_invite_answer(id: int, accept: bool) -> void:
	if server:
		server.social.on_answer(_sender(), id, accept)

@rpc("any_peer", "call_local", "reliable")
func req_trade_offer(tab: int, slot: int, count: int) -> void:
	if server:
		server.social.on_trade_offer(_sender(), tab, slot, count)

@rpc("any_peer", "call_local", "reliable")
func req_trade_shards(amount: int) -> void:
	if server:
		server.social.on_trade_shards(_sender(), amount)

@rpc("any_peer", "call_local", "reliable")
func req_trade_ready() -> void:
	if server:
		server.social.on_trade_ready(_sender())

@rpc("any_peer", "call_local", "reliable")
func req_trade_cancel() -> void:
	if server:
		server.social.cancel_trade(_sender())

@rpc("any_peer", "call_local", "reliable")
func req_guild_create(npc_id: StringName, guild_name: String) -> void:
	if server:
		server.social.on_guild_create(_sender(), npc_id, guild_name)

@rpc("any_peer", "call_local", "reliable")
func req_fame(target_peer: int, up: bool) -> void:
	if server:
		server.social.on_fame(_sender(), target_peer, up)

@rpc("any_peer", "call_local", "reliable")
func req_shop_open(title: String, entries: Array) -> void:
	if server:
		server.social.on_shop_open(_sender(), title, entries)

@rpc("any_peer", "call_local", "reliable")
func req_shop_view(owner: int) -> void:
	if server:
		server.social.on_shop_view(_sender(), owner)

@rpc("any_peer", "call_local", "reliable")
func req_shop_buy(owner: int, index: int, item_id: StringName) -> void:
	if server:
		server.social.on_shop_buy(_sender(), owner, index, item_id)

@rpc("any_peer", "call_local", "reliable")
func req_shop_leave(owner: int) -> void:
	if server:
		server.social.on_shop_leave(_sender(), owner)

@rpc("any_peer", "call_local", "reliable")
func req_scroll(use_slot: int, equip_slot: int) -> void:
	if server:
		server.on_scroll(_sender(), use_slot, equip_slot)

@rpc("any_peer", "call_local", "reliable")
func req_equip(slot: int, place: StringName) -> void:
	if server:
		server.on_equip(_sender(), slot, place)

@rpc("any_peer", "call_local", "reliable")
func req_unequip(place: StringName, slot: int) -> void:
	if server:
		server.on_unequip(_sender(), place, slot)

@rpc("any_peer", "call_local", "reliable")
func req_move_item(tab: int, from: int, to: int) -> void:
	if server:
		server.on_move_item(_sender(), tab, from, to)

@rpc("any_peer", "call_local", "reliable")
func req_drop_item(tab: int, slot: int) -> void:
	if server:
		server.on_drop_item(_sender(), tab, slot)

@rpc("any_peer", "call_local", "reliable")
func req_add_ap(stat: StringName) -> void:
	if server:
		server.on_add_ap(_sender(), stat)

## Spends several Ability Points on one stat at once (the Character window's Auto button).
@rpc("any_peer", "call_local", "reliable")
func req_add_ap_many(stat: StringName, amount: int) -> void:
	if server:
		server.on_add_ap(_sender(), stat, amount)

@rpc("any_peer", "call_local", "reliable")
func req_buy(npc_id: StringName, index: int, count: int) -> void:
	if server:
		server.on_buy(_sender(), npc_id, index, count)

@rpc("any_peer", "call_local", "reliable")
func req_sell(npc_id: StringName, tab: int, slot: int, count: int) -> void:
	if server:
		server.on_sell(_sender(), npc_id, tab, slot, count)

@rpc("any_peer", "call_local", "reliable")
func req_sell_all_etc(npc_id: StringName) -> void:
	if server:
		server.on_sell_all_etc(_sender(), npc_id)

@rpc("any_peer", "call_local", "reliable")
func req_quest_accept(npc_id: StringName, quest_id: StringName) -> void:
	if server:
		server.on_quest_accept(_sender(), npc_id, quest_id)

@rpc("any_peer", "call_local", "reliable")
func req_quest_complete(npc_id: StringName, quest_id: StringName) -> void:
	if server:
		server.on_quest_complete(_sender(), npc_id, quest_id)

@rpc("any_peer", "call_local", "reliable")
func req_quest_forfeit(quest_id: StringName) -> void:
	if server:
		server.on_quest_forfeit(_sender(), quest_id)

@rpc("any_peer", "call_local", "reliable")
func req_learn_skill(skill_id: StringName) -> void:
	if server:
		server.on_learn_skill(_sender(), skill_id)

@rpc("any_peer", "call_local", "reliable")
func req_set_quickslot(i: int, kind: StringName, id: StringName) -> void:
	if server:
		server.on_set_quickslot(_sender(), i, kind, id)

@rpc("any_peer", "call_local", "reliable")
func req_store(npc_id: StringName, tab: int, slot: int) -> void:
	if server:
		server.on_store(_sender(), npc_id, tab, slot)

@rpc("any_peer", "call_local", "reliable")
func req_retrieve(npc_id: StringName, tab: int, slot: int) -> void:
	if server:
		server.on_retrieve(_sender(), npc_id, tab, slot)

@rpc("any_peer", "call_local", "reliable")
func req_travel(npc_id: StringName, index: int) -> void:
	if server:
		server.on_travel(_sender(), npc_id, index)

@rpc("any_peer", "call_local", "reliable")
func req_advance(npc_id: StringName, job_id: StringName) -> void:
	if server:
		server.on_advance(_sender(), npc_id, job_id)

@rpc("any_peer", "call_local", "reliable")
func req_reset_ap(npc_id: StringName, job_id: StringName) -> void:
	if server:
		server.on_reset_ap(_sender(), npc_id, job_id)

# ---------- events: server -> client ----------

## Logged in to `name` ("" for the local account): on to character select.
@rpc("authority", "call_local", "reliable")
func ev_logged_in(name_: String, slots: Array) -> void:
	username = name_
	characters = slots
	logged_in.emit()

## The account's characters, after making or deleting one or leaving the world.
@rpc("authority", "call_local", "reliable")
func ev_characters(slots: Array, selected: String) -> void:
	characters = slots
	characters_changed.emit(selected)

## The server said no. With `drop`, it's also closing the connection.
@rpc("authority", "call_local", "reliable")
func ev_refused(reason: String, drop: bool) -> void:
	if drop:
		stop()
	refused.emit(reason)

## The host ended the game it was running (see `stop`).
@rpc("authority", "call_local", "reliable")
func ev_host_ended() -> void:
	stop()
	disconnected.emit(HOST_ENDED)

@rpc("authority", "call_local", "reliable")
func ev_joined(character: Dictionary) -> void:
	Game.apply_character(character)
	joined.emit()

@rpc("authority", "call_local", "reliable")
func ev_character(character: Dictionary) -> void:
	Game.apply_character(character)

@rpc("authority", "call_local", "reliable")
func ev_vitals(hp: int, mp: int, xp: int, level: int, shards: int) -> void:
	Game.apply_vitals(hp, mp, xp, level, shards)

@rpc("authority", "call_local", "reliable")
func ev_enter_map(map_id: StringName, x: float, state: Dictionary) -> void:
	if world:
		world.enter_map(map_id, x, state)

@rpc("authority", "call_local", "unreliable_ordered")
func ev_snapshot(data: PackedByteArray) -> void:
	if world:
		world.apply_snapshot(SnapshotCodec.decode(data))

## Another player's name, level, look and the like, when it changes (see MapInstance.send_player_info).
@rpc("authority", "call_local", "reliable")
func ev_player_info(peer: int, info: Array) -> void:
	if world:
		world.set_player_info(peer, info)

@rpc("authority", "call_local", "reliable")
func ev_player_left(peer: int) -> void:
	if world:
		world.remove_avatar(peer)

## You sat down on a chair (or got up, with an empty id).
@rpc("authority", "call_local", "reliable")
func ev_sit(chair_id: StringName) -> void:
	if world:
		world.player.sit(chair_id)

## You reached an achievement.
@rpc("authority", "call_local", "reliable")
func ev_achievement(id: String) -> void:
	if world:
		world.show_achievement(id)

@rpc("authority", "call_local", "reliable")
func ev_log(text: String, color: String) -> void:
	if world:
		world.add_log(text, Color(color))

@rpc("authority", "call_local", "reliable")
func ev_skill(peer: int, skill_id: StringName, x: float, y: float, face: int, lines: Array) -> void:
	if world:
		world.show_skill(peer, Content.skills.get(skill_id), Vector2(x, y), face, lines)

@rpc("authority", "call_local", "reliable")
func ev_mob_died(index: int) -> void:
	if world:
		world.show_mob_death(index)

@rpc("authority", "call_local", "reliable")
func ev_chat(kind: String, from: String, text: String, from_peer: int) -> void:
	if world:
		world.show_chat(kind, from, text, from_peer)

@rpc("authority", "call_local", "reliable")
func ev_invite(id: int, kind: String, from: String, text: String) -> void:
	if world:
		world.hud.invites.add(id, kind, from, text)

@rpc("authority", "call_local", "reliable")
func ev_social(summary: Dictionary) -> void:
	if world:
		Game.social = summary

@rpc("authority", "call_local", "reliable")
func ev_trade(state: Dictionary) -> void:
	if world:
		world.hud.show_trade(state)

@rpc("authority", "call_local", "reliable")
func ev_player_shop(owner: int, owner_name: String, title: String, items: Array) -> void:
	if world:
		world.hud.show_player_shop(owner, owner_name, title, items)

@rpc("authority", "call_local", "reliable")
func ev_mob_shot(index: int, x: float, y: float) -> void:
	if world:
		world.show_mob_shot(index, Vector2(x, y))

## A short piece of music for you alone (a quest done, a new job), played over the map's
## track (Sound.jingle).
@rpc("authority", "call_local", "reliable")
func ev_jingle(id: StringName) -> void:
	if world:
		Sound.jingle(id)

@rpc("authority", "call_local", "reliable")
func ev_level_up(peer: int, level: int) -> void:
	if world:
		world.show_level_up(peer, level)

## EXP or Dawnshards you just gained, shown rising over you.
@rpc("authority", "call_local", "reliable")
func ev_gain(kind: StringName, amount: int) -> void:
	if world:
		world.show_gain(kind, amount)

## You picked something up (Dawnshards come as ev_gain instead).
@rpc("authority", "call_local", "reliable")
func ev_pickup(item_id: StringName, amount: int) -> void:
	if world and Content.items.has(item_id):
		world.show_pickup(Content.items[item_id], amount)

@rpc("authority", "call_local", "reliable")
func ev_number(x: float, y: float, value: int, kind: String) -> void:
	if world:
		world.add_number(Vector2(x, y), value, kind)

@rpc("authority", "call_local", "reliable")
func ev_effect(effect_id: StringName, x: float, y: float, face: int, follow_peer: int) -> void:
	if world:
		world.add_effect(Content.effects.get(effect_id), Vector2(x, y), face, world.actor(follow_peer))

@rpc("authority", "call_local", "reliable")
func ev_drop(snap: Array) -> void:
	if world:
		world.add_drop(snap)

@rpc("authority", "call_local", "reliable")
func ev_drop_gone(id: int, by: int) -> void:
	if world:
		world.remove_drop(id, by)

@rpc("authority", "call_local", "reliable")
func ev_hurt(from_x: float) -> void:
	if world:
		world.player.knock_back(from_x)

@rpc("authority", "call_local", "reliable")
func ev_fainted() -> void:
	if world:
		world.player.faint()

@rpc("authority", "call_local", "reliable")
func ev_place(x: float, y: float) -> void:
	if world:
		world.player.correct(Vector2(x, y))
