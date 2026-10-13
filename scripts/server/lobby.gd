class_name TDLobby
extends RefCounted
## Everything before a player is in the world, run by the server: letting a connection in
## (or telling it the game is full), putting the character a player brought into the world,
## and sending them back to their own character select.
##
## Characters aren't kept here. Each player's game keeps its own (CharacterStore, on their
## computer) and sends the one they picked with `req_play`; while they play, the server
## sends it back to be saved with `ev_save` (TDServer.save).

const FULL := "This game is full (%d players)."
## Ticks between telling a connection the game is full and dropping it.
const KICK_TICKS := 60

var server: TDServer
## peer -> tick to drop the connection at
var _kicks := {}

func _init(s: TDServer) -> void:
	server = s

func step(tick: int) -> void:
	for peer in _kicks.keys():
		if tick >= int(_kicks[peer]):
			_kicks.erase(peer)
			Net.kick(peer)
			server.disconnected(peer)

## A friend connected to this game: welcomed to pick a character, or told it's full. The
## player at this game's own keyboard counts as one of the Net.MAX_PLAYERS.
func connected(peer: int) -> void:
	if Net.multiplayer.get_peers().size() > Net.MAX_PLAYERS - 1:
		Net.send(peer, &"ev_refused", [FULL % Net.MAX_PLAYERS, true])
		_kicks[peer] = server.tick + KICK_TICKS
		return
	Net.send(peer, &"ev_welcome", [])

## A connection closed.
func dropped(peer: int) -> void:
	_kicks.erase(peer)

# ---------- requests (see Net) ----------

## Puts the character `data` (Character.to_dict) the player brought into the world.
func on_play(peer: int, data: Dictionary) -> void:
	if server.player_of(peer) != null or _kicks.has(peer):
		return
	var c := CharacterStore.from_dict(data)
	if c.name == "":
		refuse(peer, "That character's save couldn't be read.")
		return
	if not Content.maps.has(c.map_id):
		c.map_id = Character.START_MAP
	server.enter_game(peer, c)

## Back to character select from the world (saving the character first).
func on_leave_character(peer: int) -> void:
	var p := server.player_of(peer)
	if p == null:
		return
	server.leave(peer)
	Net.send(peer, &"ev_left_world", [p.character.name])

## Tells `peer` why something they asked for didn't happen.
func refuse(peer: int, why: String) -> void:
	Net.send(peer, &"ev_refused", [why, false])
