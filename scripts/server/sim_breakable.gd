class_name SimBreakable
extends RefCounted
## A chest or wall on a map (BreakableDef), as the server keeps it. Each player breaks their
## own: it counts their blows until it breaks for them, and from then on it stays broken for
## that character (Character.secrets).

var index := 0
var def: BreakableDef
## Where it stands: the middle of its base, on its platform.
var foot := Vector2.ZERO
## peer -> blows landed so far
var blows := {}

func _init(i: int, d: BreakableDef, surface: float) -> void:
	index = i
	def = d
	foot = Vector2(d.x, surface)

## Whether it still stands whole for `p`.
func whole_for(p: SimPlayer) -> bool:
	return not p.character.found_secret(def.id)

## Lands one blow from `p`. True when that one breaks it.
func strike(p: SimPlayer) -> bool:
	var n: int = blows.get(p.peer, 0) + 1
	if n < def.hits:
		blows[p.peer] = n
		return false
	blows.erase(p.peer)
	return true

## The player left the map: their blows so far don't count any more.
func forget(peer: int) -> void:
	blows.erase(peer)
