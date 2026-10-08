class_name MapDef
extends Resource
## One map: its size, layout, monsters, NPCs and look. Add a map by saving a MapDef in
## data/maps/ and pointing a portal at its id (see ARCHITECTURE.md).
## Coordinates are game pixels with y pointing down; platform y is the walkable top edge.

@export var id: StringName
@export var display_name := ""
## Shown on the signpost at the map's entrance (empty for no sign).
@export var sign_text := ""
@export var sign_x := 120.0
@export var biome: BiomeDef
@export var width := 2600
@export var height := 700
## The solid floor's top edge. It becomes platform 0.
@export var ground_y := 620
## Where the player appears when they respawn or load into this map.
@export var start_x := 200.0
## Lanterns stand along the floor, about this far apart (0 for none).
@export var lantern_spacing := 640.0

@export_group("Layout")
## One-way platforms, numbered from 1 in this order (0 is the floor).
@export var platforms: Array[PlatformDef] = []
@export var climbables: Array[ClimbableDef] = []
@export var portals: Array[PortalDef] = []

@export_group("Inhabitants")
@export var spawns: Array[SpawnDef] = []
@export var npcs: Array[NpcPlacement] = []

@export_group("Set dressing")
## Hand-placed scenery on top of the biome's random decoration.
@export var props: Array[PropPlacement] = []
