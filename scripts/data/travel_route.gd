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
