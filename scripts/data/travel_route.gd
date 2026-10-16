class_name TravelRoute
extends Resource
## One trip an NPC offers (a ship, a wagon, a balloon): where it goes and what it costs.
## Put these in NpcDef.travel; the NPC's dialogue then offers "Travel".

@export var target_map: StringName
## Where on that map's floor the traveller arrives.
@export var target_x := 200.0
@export var price := 0
## How it's described: "Ship", "Wagon", "Balloon".
@export var by := "Wagon"
## Only offered once the traveller has been to `target_map` (coaches go back to towns
## you know, not ahead of you).
@export var needs_visit := false

## Whether `c` may take this trip.
func open_to(c: Character) -> bool:
	return not needs_visit or c.visited.has(String(target_map))
