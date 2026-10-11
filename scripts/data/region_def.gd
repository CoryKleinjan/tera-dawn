class_name RegionDef
extends Resource
## A major zone of the world (an island, a forest): its main city and the fields around it.
## Maps name their region (MapDef.region). The world map (W) shows each region's name and city
## and the major routes between regions (WorldRoutes); clicking a region opens its zone map.
## Add one by saving a RegionDef in data/regions/.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var color := Color("8cf0a6")
## Its main city (a MapDef with `town = true` in this region): where the world map draws it
## and where its major routes start.
@export var capital: StringName
## Where its name sits on the world map, in world-map units (pixels of the world map painting,
## TDWorldMapWindow.WORLD).
@export var label_pos := Vector2.ZERO
## "Lv. 1-10": who it's for, shown on the world map.
@export var level_text := ""
## The part of the world map painting (world-map units) its zone map zooms into. Every map
## of the region sits inside it; the zone map widens it to the painting's shape.
@export var zone_rect := Rect2()

@export_group("Music")
## The tracks (Sound.music ids, files in assets/audio/music/) for its towns (and the rooms
## and markets in them) and for its fields. A map can play its own (MapDef.music).
@export var town_music: StringName
@export var field_music: StringName
