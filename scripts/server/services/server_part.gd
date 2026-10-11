class_name ServerPart
extends RefCounted
## One area of the server's request handling: items, NPC shops, storage, travel, quests or
## jobs (see TDServer). The players, maps and saving live on TDServer; a part only keeps a
## weak reference back to it, so the two don't keep each other alive.

## The TDServer this part belongs to.
var server: TDServer:
	get:
		return _server.get_ref()

var _server: WeakRef

func _init(s: TDServer) -> void:
	_server = weakref(s)

## The player on this peer, or null.
func player_of(peer: int) -> SimPlayer:
	return server.player_of(peer)

## Tells the player something in their chat log (in red by default, for what went wrong).
func tell(p: SimPlayer, text: String, col := MapInstance.BAD) -> void:
	p.map.tell(p, text, col)

## Runs a change to the player's character and sends them the result, or why it failed.
func change(peer: int, change_: Callable) -> void:
	var p := player_of(peer)
	if p == null:
		return
	var problem: String = change_.call(p.character)
	if problem != "":
		tell(p, problem)
	p.dirty_character = true
