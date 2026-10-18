extends Node
## Autoload "Net": starts or joins a game, and carries every message between the game and
## the server. This file is the whole network protocol: requests (req_*) go from a client
## to the server, events (ev_*) go from the server to clients.
##
## There is always a server, even in single player: it runs in the same game, and the
## messages go straight to it without touching the network. So single player, hosting and
## joining a friend all play by the same rules.
##
## Every player's characters are saved on their own computer (`saves`). Whatever game they
## play, they pick one at character select and bring it along: it's sent to the server when
## they play, and the server sends it back to be saved (`ev_save`) while they do.

enum Mode { NONE, SINGLE, HOST, CLIENT }

const DEFAULT_PORT := 7350
## Players in one game, counting the host.
const MAX_PLAYERS := 4
const LOST := "Lost the connection to the host."
const HOST_ENDED := "The host ended the game."
## Physics ticks a host's connection stays open after it stops, so the players connected
## to it get told the game ended (closing at once would drop the message).
const GOODBYE_TICKS := 30

## In a game and ready to pick a character: `characters` is filled in, show character select.
signal welcomed
## The characters on this computer changed (`characters`); `selected` is the one to pick, if any.
signal characters_changed(selected: String)
## Something asked for didn't happen (a name that's taken, a full game, a host that couldn't
## be reached); `reason` says why, in words for the player.
signal refused(reason: String)
## The server put our character in the world (Game.me is filled in).
signal joined
## The connection to the host closed: lost, or the host ended the game. `why` says which,
## in words for the player.
signal disconnected(why: String)

var mode := Mode.NONE
## The port this game hosts on.
var port := DEFAULT_PORT
## The server, when this game runs one (single player or host).
var server: TDServer
## Where events for the player are shown, when this game has a client.
var world: TDWorld
## Where this computer keeps its characters (and, when hosting, the game's guilds and its
## encryption key). Tests point it somewhere else.
var save_dir := "user://characters"
## The characters character select is showing (this computer's own, or the test characters
## with the Developer setting on); see `open_saves`.
var saves: CharacterStore
## The characters as character select shows them: {name, job}.
var characters: Array = []
## The character this player is playing ("" at character select).
var playing := ""
## A host's connection after it stopped, open for `_leaving_t` more ticks (GOODBYE_TICKS).
var _leaving: ENetMultiplayerPeer
var _leaving_t := 0

func _ready() -> void:
	multiplayer.peer_connected.connect(func(peer: int) -> void:
		if server:
			server.lobby.connected(peer))
	multiplayer.peer_disconnected.connect(func(peer: int) -> void:
		if server:
			server.disconnected(peer))
	multiplayer.connection_failed.connect(func() -> void:
		stop()
		refused.emit("Couldn't reach the host."))
	multiplayer.server_disconnected.connect(func() -> void:
		stop()
		disconnected.emit(LOST))

func _physics_process(_delta: float) -> void:
	if _leaving:
		_leaving.poll()
		_leaving_t -= 1
		if _leaving_t <= 0:
			_close_leaving()

# ---------- starting and stopping ----------

## Single player: a private server inside this game, not reachable from the network.
## `welcomed` follows at once.
func play_single() -> void:
	stop()
	mode = Mode.SINGLE
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_start_server()
	_welcome()

## Host: play here, and let up to MAX_PLAYERS - 1 friends join this game on `port`, each
## bringing a character of their own. `welcomed` follows at once. Returns "" or what went
## wrong.
func host(on_port := DEFAULT_PORT) -> String:
	stop()
	_close_leaving()
	var peer := ENetMultiplayerPeer.new()
	# one connection more than there's room for, so a friend who tries a full game is told so
	if peer.create_server(on_port, MAX_PLAYERS) != OK:
		return "Couldn't open port %d. Is another game using it?" % on_port
	if peer.host.dtls_server_setup(TDTls.server_options(save_dir)) != OK:
		peer.close()
		return "Couldn't set up encryption."
	mode = Mode.HOST
	port = on_port
	multiplayer.multiplayer_peer = peer
	_start_server()
	_welcome()
	return ""

## Joins a friend's game at `address`. `welcomed` (pick a character to bring) or `refused`
## follows. Returns "" or what went wrong right away.
func join(address: String, host_port := DEFAULT_PORT) -> String:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, host_port) != OK:
		return "Couldn't connect to %s." % address
	if peer.host.dtls_client_setup(address, TDTls.client_options(address)) != OK:
		peer.close()
		return "Couldn't set up encryption."
	mode = Mode.CLIENT
	multiplayer.multiplayer_peer = peer
	return ""

## Whether other players are connected to the game this one hosts.
func has_guests() -> bool:
	return mode == Mode.HOST and not multiplayer.get_peers().is_empty()

## Leaves the game (saving everyone if this game is the server). A host tells the players
## connected to it that the game has ended, after sending them their characters to save.
func stop() -> void:
	var guests := has_guests()
	if server:
		server.save_all()
		server.queue_free()
		server = null
	if guests:
		for peer in multiplayer.get_peers():
			send(peer, &"ev_host_ended", [])
	var old := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if guests:
		_close_later(old as ENetMultiplayerPeer)
	elif old and not old is OfflineMultiplayerPeer:
		old.close()
	mode = Mode.NONE
	characters = []
	playing = ""

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

func _start_server() -> void:
	server = TDServer.new(save_dir)
	server.name = "Server"
	add_child(server)

## On to character select, with this computer's characters.
func _welcome() -> void:
	open_saves()
	welcomed.emit()

# ---------- character select (on this computer) ----------

## Picks the characters character select shows: this computer's own, or, with the
## Developer setting on in a debug build, the test characters (made or put back in their
## towns first; see TestCharacters).
func open_saves() -> void:
	var test := Settings.dev.characters_mode()
	if test == TestCharacters.Mode.OFF:
		saves = CharacterStore.new(save_dir)
	else:
		saves = CharacterStore.new(save_dir.path_join(TestCharacters.FOLDER))
		TestCharacters.prepare(saves, test == TestCharacters.Mode.REBUILD)
	characters = saves.slots()

## Makes a new character on this computer. `characters_changed` (with it selected) or
## `refused` follows; returns "" or why not.
func create_character(char_name: String, made: NewCharacter) -> String:
	var why := saves.create(char_name, made)
	if why != "":
		refused.emit(why)
		return why
	_list_characters(CharacterStore.clean_name(char_name))
	return ""

## Deletes one of this computer's characters; `typed` is what the player typed to confirm.
func delete_character(char_name: String, typed: String) -> void:
	var real := saves.saved_name(char_name)
	if real == "":
		refused.emit("That isn't one of your characters.")
		return
	if typed.strip_edges().to_lower() != real.to_lower():
		refused.emit("Type %s to delete it." % real)
		return
	saves.remove(real)
	print("Deleted %s" % real)
	_list_characters("")

## Brings one of this computer's characters into the game. `joined` or `refused` follows.
func play(char_name: String) -> void:
	var c := saves.load_character(char_name) if saves else null
	if c == null:
		refused.emit("%s's save couldn't be read." % char_name)
		return
	playing = c.name
	ask(&"req_play", [c.to_dict()])

## Leaves the world for character select, still in the game.
func leave_character() -> void:
	ask(&"req_leave_character")

func _list_characters(selected: String) -> void:
	characters = saves.slots()
	characters_changed.emit(selected)

## Drops a connection (the server, when its game is full).
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
## Each group hands off to the server part in its title.

# --- character select (TDLobby) ---

## Brings the character `character` (Character.to_dict) into the world.
@rpc("any_peer", "call_local", "reliable")
func req_play(character: Dictionary) -> void:
	if server:
		server.lobby.on_play(_sender(), character)

@rpc("any_peer", "call_local", "reliable")
func req_leave_character() -> void:
	if server:
		server.lobby.on_leave_character(_sender())

# --- moving and fighting (TDServer) ---

@rpc("any_peer", "call_local", "unreliable_ordered")
func req_move(at: Vector2, face: int, anim: StringName) -> void:
	if server:
		server.on_move(_sender(), at, face, anim)

## A Slam (RelicDef.Move.SLAM) landed with the feet `at`.
@rpc("any_peer", "call_local", "reliable")
func req_slam(at: Vector2) -> void:
	if server:
		server.on_slam(_sender(), at)

## Sit down on the ground (`down`) or get up.
@rpc("any_peer", "call_local", "reliable")
func req_sit(down: bool) -> void:
	if server:
		server.on_sit(_sender(), down)

@rpc("any_peer", "call_local", "reliable")
func req_skill(skill_id: StringName, at: Vector2, face: int, aim := 0) -> void:
	if server:
		server.on_skill(_sender(), skill_id, at, face, aim)

@rpc("any_peer", "call_local", "reliable")
func req_loot() -> void:
	if server:
		server.on_loot(_sender())

@rpc("any_peer", "call_local", "reliable")
func req_set_quickslot(i: int, kind: StringName, id: StringName) -> void:
	if server:
		server.on_set_quickslot(_sender(), i, kind, id)

# --- getting around (ServerTravel) ---

@rpc("any_peer", "call_local", "reliable")
func req_portal() -> void:
	if server:
		server.travel.on_portal(_sender())

@rpc("any_peer", "call_local", "reliable")
func req_travel(npc_id: StringName, index: int) -> void:
	if server:
		server.travel.on_travel(_sender(), npc_id, index)

# --- your things (ServerItems) ---

@rpc("any_peer", "call_local", "reliable")
func req_use_item(slot: int) -> void:
	if server:
		server.items.on_use_item(_sender(), slot)

## Bring out the pet in Setup slot `slot` (again to send it home).
@rpc("any_peer", "call_local", "reliable")
func req_setup(slot: int) -> void:
	if server:
		server.items.on_setup(_sender(), slot)

@rpc("any_peer", "call_local", "reliable")
func req_equip(slot: int, place: StringName) -> void:
	if server:
		server.items.on_equip(_sender(), slot, place)

@rpc("any_peer", "call_local", "reliable")
func req_unequip(place: StringName, slot: int) -> void:
	if server:
		server.items.on_unequip(_sender(), place, slot)

@rpc("any_peer", "call_local", "reliable")
func req_move_item(tab: int, from: int, to: int) -> void:
	if server:
		server.items.on_move_item(_sender(), tab, from, to)

@rpc("any_peer", "call_local", "reliable")
func req_drop_item(tab: int, slot: int) -> void:
	if server:
		server.items.on_drop_item(_sender(), tab, slot)

# --- NPC shops (ServerNpcShop) ---

@rpc("any_peer", "call_local", "reliable")
func req_buy(npc_id: StringName, index: int, count: int) -> void:
	if server:
		server.npc_shop.on_buy(_sender(), npc_id, index, count)

@rpc("any_peer", "call_local", "reliable")
func req_sell(npc_id: StringName, tab: int, slot: int, count: int) -> void:
	if server:
		server.npc_shop.on_sell(_sender(), npc_id, tab, slot, count)

@rpc("any_peer", "call_local", "reliable")
func req_sell_all_etc(npc_id: StringName) -> void:
	if server:
		server.npc_shop.on_sell_all_etc(_sender(), npc_id)

# --- storage (ServerStorage) ---

@rpc("any_peer", "call_local", "reliable")
func req_store(npc_id: StringName, tab: int, slot: int) -> void:
	if server:
		server.storage.on_store(_sender(), npc_id, tab, slot)

@rpc("any_peer", "call_local", "reliable")
func req_retrieve(npc_id: StringName, tab: int, slot: int) -> void:
	if server:
		server.storage.on_retrieve(_sender(), npc_id, tab, slot)

# --- enchanting (ServerEnchanting) ---

## Sets the rune in Etc slot `rune_slot` in rune slot `socket` of the gear in Equip slot
## `gear_slot`, at the enchanter `npc_id`.
@rpc("any_peer", "call_local", "reliable")
func req_enchant(npc_id: StringName, gear_slot: int, rune_slot: int, socket: int) -> void:
	if server:
		server.enchanting.on_enchant(_sender(), npc_id, gear_slot, rune_slot, socket)

## Raises the gear in Equip slot `gear_slot` one tier, at the enchanter `npc_id`.
@rpc("any_peer", "call_local", "reliable")
func req_upgrade(npc_id: StringName, gear_slot: int) -> void:
	if server:
		server.enchanting.on_upgrade(_sender(), npc_id, gear_slot)

# --- quests (ServerQuests) ---

@rpc("any_peer", "call_local", "reliable")
func req_quest_accept(npc_id: StringName, quest_id: StringName) -> void:
	if server:
		server.quests.on_quest_accept(_sender(), npc_id, quest_id)

@rpc("any_peer", "call_local", "reliable")
func req_quest_complete(npc_id: StringName, quest_id: StringName) -> void:
	if server:
		server.quests.on_quest_complete(_sender(), npc_id, quest_id)

@rpc("any_peer", "call_local", "reliable")
func req_quest_forfeit(quest_id: StringName) -> void:
	if server:
		server.quests.on_quest_forfeit(_sender(), quest_id)

# --- cutscenes (ServerScenes) ---

## The cutscene the server sent ended on this player's screen (watched or skipped).
@rpc("any_peer", "call_local", "reliable")
func req_scene_done(scene_id: StringName) -> void:
	if server:
		server.scenes.on_scene_done(_sender(), scene_id)

# --- jobs, stats and skills (ServerJobs) ---

@rpc("any_peer", "call_local", "reliable")
func req_advance(npc_id: StringName, job_id: StringName) -> void:
	if server:
		server.jobs.on_advance(_sender(), npc_id, job_id)

@rpc("any_peer", "call_local", "reliable")
func req_learn_skill(skill_id: StringName) -> void:
	if server:
		server.jobs.on_learn_skill(_sender(), skill_id)

# --- players together (TDSocial) ---

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

# ---------- events: server -> client ----------

## The host let us in: on to character select, with this computer's characters.
@rpc("authority", "call_local", "reliable")
func ev_welcome() -> void:
	_welcome()

## Our character as the server has it, to keep on this computer (see `saves`).
@rpc("authority", "call_local", "reliable")
func ev_save(character: Dictionary) -> void:
	if saves and playing != "" and str(character.get("name", "")).to_lower() == playing.to_lower():
		saves.save_data(playing, character)

## Our character left the world (saved just before): back to character select, listing
## this computer's own characters or the test characters as the Developer setting now says.
@rpc("authority", "call_local", "reliable")
func ev_left_world(char_name: String) -> void:
	playing = ""
	open_saves()
	characters_changed.emit(char_name if saves.exists(char_name) else "")

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
func ev_vitals(hp: int, mp: int, xp: int, level: int, essence: int, shards: int) -> void:
	Game.apply_vitals(hp, mp, xp, level, essence, shards)

@rpc("authority", "call_local", "reliable")
func ev_enter_map(map_id: StringName, x: float, state: Dictionary, platform: int) -> void:
	if world:
		world.enter_map(map_id, x, state, platform)

@rpc("authority", "call_local", "unreliable_ordered")
func ev_snapshot(data: PackedByteArray) -> void:
	if world:
		world.apply_snapshot(SnapshotCodec.decode(data))

## Another player's name, job and the like, when it changes (see MapInstance.send_player_info).
@rpc("authority", "call_local", "reliable")
func ev_player_info(peer: int, info: Array) -> void:
	if world:
		world.set_player_info(peer, info)

@rpc("authority", "call_local", "reliable")
func ev_player_left(peer: int) -> void:
	if world:
		world.remove_avatar(peer)

## You sat down on the ground (or got up).
@rpc("authority", "call_local", "reliable")
func ev_sit(down: bool) -> void:
	if world:
		world.player.sit(down)

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
func ev_skill(peer: int, skill_id: StringName, x: float, y: float, face: int, lines: Array, aim := 0) -> void:
	if world:
		world.show_skill(peer, Content.skills.get(skill_id), Vector2(x, y), face, lines, aim)

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
func ev_mob_shot(index: int, move_index: int, x: float, y: float) -> void:
	if world:
		world.show_mob_shot(index, move_index, Vector2(x, y))

## A monster's move did something worth showing at (x, y): "slam", "land", "blink" or
## "rage" (a boss's second wind).
@rpc("authority", "call_local", "reliable")
func ev_mob_move(index: int, what: StringName, x: float, y: float) -> void:
	if world:
		world.fx.show_mob_move(index, what, Vector2(x, y))

## A short piece of music for you alone (a quest done, a new job), played over the map's
## track (Sound.jingle).
@rpc("authority", "call_local", "reliable")
func ev_jingle(id: StringName) -> void:
	if world:
		Sound.jingle(id)

## A cutscene for you alone (see TDCutscenePlayer); answered with req_scene_done.
@rpc("authority", "call_local", "reliable")
func ev_scene(scene_id: StringName) -> void:
	if world:
		world.play_scene(scene_id)

## A player on your map levelled up (you, or someone near).
@rpc("authority", "call_local", "reliable")
func ev_level_up(peer: int, level: int) -> void:
	if world:
		world.show_level_up(peer, level)

## Dawn Essence from a monster that fell at (x, y), flying to you.
@rpc("authority", "call_local", "reliable")
func ev_essence(x: float, y: float, amount: int) -> void:
	if world:
		world.fly_essence(Vector2(x, y), amount)

## Dawn Essence or Dawnshards you just gained, shown rising over you.
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

## A buff landed on `peer`: its aura shows round them for `ticks` (SkillDef.aura).
@rpc("authority", "call_local", "reliable")
func ev_aura(peer: int, skill_id: StringName, ticks: int) -> void:
	if world and Content.skills.has(skill_id):
		world.add_aura(world.actor(peer), Content.skills[skill_id], ticks)

@rpc("authority", "call_local", "reliable")
func ev_drop(snap: Array) -> void:
	if world:
		world.add_drop(snap)

## The map's tear opened (MapInstance.check_tear).
@rpc("authority", "call_local", "reliable")
func ev_tear() -> void:
	if world:
		world.open_tear()

## A chest or wall you hit shook, or broke open (`broke`; MapInstance._strike_breakables).
@rpc("authority", "call_local", "reliable")
func ev_struck(index: int, broke: bool) -> void:
	if world:
		world.strike_breakable(index, broke)

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
