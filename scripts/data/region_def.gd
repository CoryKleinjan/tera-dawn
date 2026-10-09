class_name RegionDef
extends Resource
## A part of the world (an island, a forest, a town and its fields). Maps name their region
## (MapDef.region); the world map (W) draws each region as a coloured patch behind its maps,
## with its name. Add one by saving a RegionDef in data/regions/.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var color := Color("8cf0a6")
## Where its name sits on the world map, in world-map units (1000 x 600).
@export var label_pos := Vector2.ZERO
## "Lv. 1-10": who it's for, shown on the world map.
@export var level_text := ""
