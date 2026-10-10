class_name BuildingPlacement
extends Resource
## A building standing on a map. `x` is where its door is, so the door lines up with the
## spot players walk to; a door portal (`PortalDef.door`) at the same x and platform makes
## the building enterable.

@export var building: BuildingDef
## Where its door is (game pixels).
@export var x := 0.0
## The platform it stands on (0 is the floor).
@export var platform := 0
## Bigger or smaller than the picture's own `height` (a hall stands taller than a house).
@export var scale := 1.0
## Mirror it, door and all.
@export var flip := false
## Depth: 0 is where the characters walk, negative is further back. Buildings stand just
## behind the lanterns and NPCs, close enough to keep their full size.
@export var depth := -2.0
## Multiplied into its colours, so one picture can stand in for a few houses.
@export var tint := Color.WHITE

## The x of the building's middle (its picture is centred there).
func center_x() -> float:
	return x - building.door_offset(flip) * scale if building else x
