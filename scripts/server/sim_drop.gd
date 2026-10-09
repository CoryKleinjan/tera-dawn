class_name SimDrop
extends RefCounted
## An item lying on a map, as the server keeps it. It flies out, lands on the platform
## below, and disappears after a while. Like MapleStory, for a short time only the player
## it dropped for can take it. Clients draw it with TDDrop and run the same flight.

## Ticks before it can be picked up, so it's seen landing first.
const SETTLE_TICKS := 25
## Ticks only the owner can pick it up.
const OWNER_TICKS := 900
const LIFETIME := 3600

var id := 0
var item: ItemDef
var amount := 1
## Gear dropped from a bag keeps its rolled stats; otherwise null and rolled on pickup.
var stack: ItemStack
var owner := 0
var flight: DropFlight
var t := 0
var taken := false

func _init(drop_id: int, it: ItemDef, n: int, f: DropFlight, owner_peer: int) -> void:
	id = drop_id
	item = it
	amount = n
	flight = f
	owner = owner_peer

func step() -> void:
	t += 1
	flight.step()

func expired() -> bool:
	return t > LIFETIME

## Whether `p` may pick this up now, standing within `reach` of it (their pet reaches further).
func can_loot(p: SimPlayer, reach := 26.0) -> bool:
	return not taken and t > SETTLE_TICKS and not p.fainted() \
		and (owner == 0 or owner == p.peer or t > OWNER_TICKS) \
		and absf(flight.position.x - p.position.x) < reach and absf(flight.position.y - p.position.y) < 50 + (reach - 26.0) * 0.5

## What a client needs to show it: [id, item id, amount, flight state, age in ticks].
func snapshot() -> Array:
	return [id, item.id, amount, flight.to_array(), t]
