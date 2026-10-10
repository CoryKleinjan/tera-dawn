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
## Free for a Beginner who is ready for their first job (the lowest JobDef.advance_level of
## the jobs they can advance into), so the first ride to a job town costs nothing.
@export var free_for_beginners := false

## What `c` pays for this trip.
func fare_for(c: Character) -> int:
	if free_for_beginners and c.job and c.job.is_starting_job() and c.level >= JobDef.first_advance_level(c.job.id):
		return 0
	return price
