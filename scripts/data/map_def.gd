class_name MapDef
extends Resource
## One map: its size, layout, monsters, NPCs and look. Add a map by saving a MapDef in
## data/maps/ and pointing a portal at its id (see ARCHITECTURE.md).
## Coordinates are game pixels with y pointing down; platform y is the walkable top edge.

@export var id: StringName
@export var display_name := ""
@export var biome: BiomeDef
@export var width := 2600
@export var height := 700
## The solid floor's top edge. It becomes platform 0.
@export var ground_y := 620
## Where the player appears when they respawn or load into this map.
@export var start_x := 200.0
## Lanterns stand along the floor, about this far apart, in open ground (LanternPlacement).
## -1 picks the usual spacing for a town or a field; 0 means none.
@export var lantern_spacing := -1.0

@export_group("World")
## The RegionDef it belongs to.
@export var region: StringName
## Where it sits on the world map, in world-map units (pixels of the world map painting,
## TDWorldMapWindow.WORLD).
@export var world_pos := Vector2.ZERO
## Towns are safe places to respawn and where return scrolls take you.
@export var town := false
## A free market: players may open their own shops here.
@export var market := false
## The town you wake up in after fainting here, and where a return scroll goes. Empty means
## this map if it's a town, else the starting map.
@export var return_map: StringName
## "Lv. 10-15": who it's for, shown on the world map.
@export var level_text := ""
## Inside a building: a small room with a wall instead of sky, entered by a door from
## `return_map` (the town it stands in). The world map shows you in that town.
@export var interior := false

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
## The houses, shops and halls standing along a town's streets.
@export var buildings: Array[BuildingPlacement] = []

## The town this map sends you back to (see `return_map`).
func return_town() -> StringName:
	if return_map != &"":
		return return_map
	return id if town else Character.START_MAP

## The map you're "in" on the world map: the town outside, for a room inside a building.
func outside() -> StringName:
	return return_town() if interior else id

## The maps its portals lead to.
func neighbours() -> Array[StringName]:
	var out: Array[StringName] = []
	for p in portals:
		if not p.target_map in out:
			out.append(p.target_map)
	return out

## Every monster on the map, in the order the server and every client number them:
## [MonsterDef, platform index, parent index, SpawnDef]. Monsters that split are followed
## by the ones they split into, whose parent is the index of the one that splits (-1
## otherwise). The SpawnDef says which part of the platform they walk on (patrol_area).
func roster() -> Array:
	var out := []
	for s in spawns:
		for i in s.count:
			var parent := out.size()
			out.append([s.monster, s.platform, -1, s])
			if s.monster.splits_into:
				for k in s.monster.split_count:
					out.append([s.monster.splits_into, s.platform, parent, s])
	return out
