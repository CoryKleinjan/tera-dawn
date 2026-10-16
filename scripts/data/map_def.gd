class_name MapDef
extends Resource
## One map: its size, layout, monsters, NPCs and look. Add a map by saving a MapDef in
## data/maps/ and pointing a portal at its id (see docs/architecture/maps.md).
## Coordinates are game pixels with y pointing down; platform y is the walkable top edge.

@export var id: StringName
@export var display_name := ""
## Its region's look (one BiomeDef per major zone); `variant` is this sub zone's own take on it.
@export var biome: BiomeDef
@export var variant: BiomeVariantDef
@export var width := 2600
@export var height := 700
## The solid floor's top edge. It becomes platform 0.
@export var ground_y := 620
## Where the player appears when they respawn or load into this map.
@export var start_x := 200.0
## Lanterns stand along the floor, about this far apart, in open ground (LanternPlacement).
## -1 picks the usual spacing for a town or a field; 0 means none.
@export var lantern_spacing := -1.0
## Hand-placed lantern posts on raised levels, besides the floor's own: each is an x and the
## index (1-based) of the platform it stands on.
@export var level_lanterns: Array[Vector2i] = []
## How often the biome's trees, bushes, rocks and flowers stand, as a share of what its
## DecorDefs ask for (DecorPlacement). -1 uses the shared DecorPlacement.DENSITY; 0 means none.
@export var decor_density := -1.0

@export_group("World")
## The RegionDef it belongs to.
@export var region: StringName
## Where it sits on the world map, in world-map units (pixels of the world map painting,
## TDWorldMapWindow.WORLD).
@export var world_pos := Vector2.ZERO
## Towns are safe places to respawn and where return scrolls take you.
@export var town := false
## The town you wake up in after fainting here, and where a return scroll goes. Empty means
## this map if it's a town, else the starting map.
@export var return_map: StringName
## "Lv. 10-15": the tuning tier it's made for. Never shown to players (there are no levels
## in the game); content tests use it to keep the zones in order.
@export var level_text := ""
## Inside a building: a small room with a wall instead of sky, entered by a door from
## `return_map` (the town it stands in). The world map shows you in that town.
@export var interior := false
## Its own track (a boss lair). Empty: its region's town or field music (music_id).
@export var music: StringName
## A cutscene each character sees the first time they arrive (see CutsceneDef).
@export var intro_scene: CutsceneDef
## Each player gets a copy of their own (a job test fought alone, even in co-op). The copy
## starts fresh every time they come in.
@export var solo := false

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
## A map that isn't a town may only have buildings (or building pictures among its props)
## when this is on: a quest needs the house there, or Cory asked for one. Monster maps have
## no houses otherwise (tests/content/content_houses_test.gd).
@export var houses_allowed := false
## Faint white glows hanging out over the water, drawn in code (TDStage._build_tears): x
## across the map and height above the floor, in game pixels. Nobody in the game mentions them.
@export var tears: Array[Vector2] = []
## A tear that opens when a player first stands on this platform (-1: the tears are always
## there): they only show from then on, `tear_scene` plays, and the monsters marked
## `SpawnDef.from_tear` step out of the first tear.
@export var tear_platform := -1
@export var tear_scene: CutsceneDef

var _look: BiomeDef

## How it looks: its biome with its variant applied (the biome itself when it has none).
## Builders read this, never `biome` directly.
func look() -> BiomeDef:
	if variant == null or biome == null:
		return biome
	if _look == null:
		_look = variant.apply(biome)
	return _look

## The platform a solid platform (`PlatformDef.solid`) stands on: the highest platform below
## its middle that runs under it, or 0 (the floor).
func land_under(platform: int) -> int:
	var d := platforms[platform - 1]
	var mid := d.x + d.width * 0.5
	var best := 0
	for i in platforms.size():
		var o := platforms[i]
		if o.y > d.y and mid >= o.x and mid <= o.x + o.width and (best == 0 or o.y < platforms[best - 1].y):
			best = i + 1
	return best

## The top edge of platform `platform` (0 is the floor), in game pixels.
func surface_y(platform: int) -> float:
	return float(ground_y) if platform == 0 else platforms[platform - 1].y

## The solid platforms standing on platform `platform` (0 is the floor), as their left and
## right ends (x and y): raised land whose front covers that stretch of the land below.
func solid_spans_on(platform: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in platforms.size():
		var d := platforms[i]
		if d.solid and land_under(i + 1) == platform:
			out.append(Vector2(d.x, d.x + d.width))
	return out

## The town this map sends you back to (see `return_map`).
func return_town() -> StringName:
	if return_map != &"":
		return return_map
	return id if town else Character.START_MAP

## The map you're "in" on the world map: the town outside, for a room inside a building or
## a solo map (a job test's Trial Ground).
func outside() -> StringName:
	return return_town() if interior or solo else id

## The track that plays here: its own, else its region's town music for towns and
## rooms, and its region's field music for everywhere else.
func music_id() -> StringName:
	if music != &"":
		return music
	var r: RegionDef = Content.regions.get(region)
	if r == null:
		return &""
	return r.town_music if town or interior else r.field_music

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
