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

## The server accepted our character (Game.me is filled in).
signal joined
## Joining didn't work; `reason` says why, in words for the player.
signal join_failed(reason: String)
## The connection to the server was lost.
signal disconnected

var mode := Mode.NONE
## The server, when this game runs one (single player, host or dedicated).
var server: TDServer
## Where events for the player are shown, when this game has a client.
var world: TDWorld
## Where the server keeps characters. Tests point it somewhere else.
var save_dir := "user://characters"
## Whether a server started for this player may bring in the save from before multiplayer.
var import_legacy_save := true
var _name := ""

func _ready() -> void:
	multiplayer.peer_disconnected.connect(func(peer: int) -> void:
		if server:
			server.leave(peer))
	multiplayer.connected_to_server.connect(func() -> void: req_join.rpc_id(1, _name))
	multiplayer.connection_failed.connect(func() -> void:
		stop()
		join_failed.emit("Couldn't reach the server."))
	multiplayer.server_disconnected.connect(func() -> void:
		stop()
		disconnected.emit())

func is_playing() -> bool:
	return mode != Mode.NONE and mode != Mode.DEDICATED

# ---------- starting and stopping ----------

## Single player: a private server inside this game, not reachable from the network.
func play_single(char_name: String) -> void:
	stop()
	mode = Mode.SINGLE
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_server(true)
	req_join.rpc_id(1, char_name)

## Host: play, and let other players join this game on `port`. Returns "" or what went wrong.
func host(char_name: String, port := DEFAULT_PORT) -> String:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS) != OK:
		return "Couldn't open port %d. Is another game using it?" % port
	mode = Mode.HOST
	multiplayer.multiplayer_peer = peer
	_start_server(true)
	req_join.rpc_id(1, char_name)
	return ""

## Join someone else's server. `joined` or `join_failed` follows.
func join(char_name: String, address: String, port := DEFAULT_PORT) -> String:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, port) != OK:
		return "Couldn't connect to %s." % address
	mode = Mode.CLIENT
	_name = char_name
	multiplayer.multiplayer_peer = peer
	return ""

## A server with no player of its own (run with `-- --server`). Returns "" or what went wrong.
func run_dedicated(port := DEFAULT_PORT) -> String:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS) != OK:
		return "Couldn't open port %d." % port
	mode = Mode.DEDICATED
	multiplayer.multiplayer_peer = peer
	_start_server(false)
	print("Tera Dawn server listening on port %d" % port)
	return ""

## Leaves the game (saving everyone if this game is the server).
func stop() -> void:
	if server:
		server.save_all()
		server.queue_free()
		server = null
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE

func _start_server(local_player: bool) -> void:
	server = TDServer.new(save_dir)
	server.name = "Server"
	server.import_legacy_save = local_player and import_legacy_save
	add_child(server)

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
func req_join(char_name: String) -> void:
	if server:
		server.join(_sender(), char_name)

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
func req_advance(npc_id: StringName, job_id: StringName) -> void:
	if server:
		server.on_advance(_sender(), npc_id, job_id)

# ---------- events: server -> client ----------

@rpc("authority", "call_local", "reliable")
func ev_joined(character: Dictionary) -> void:
	Game.apply_character(character)
	joined.emit()

@rpc("authority", "call_local", "reliable")
func ev_join_failed(reason: String) -> void:
	stop()
	join_failed.emit(reason)

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
func ev_snapshot(snap: Dictionary) -> void:
	if world:
		world.apply_snapshot(snap)

@rpc("authority", "call_local", "reliable")
func ev_player_left(peer: int) -> void:
	if world:
		world.remove_avatar(peer)

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
func ev_level_up(peer: int, level: int) -> void:
	if world:
		world.show_level_up(peer, level)

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
