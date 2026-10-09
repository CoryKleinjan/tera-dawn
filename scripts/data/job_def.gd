class_name JobDef
extends Resource
## A job (class): which stats drive its damage, how HP and MP grow, and what a new
## character of this job starts with. Add a job by saving a JobDef in data/jobs/.

@export var id: StringName
@export var display_name := ""
## The stat that drives damage (STR for warriors) and the one that helps a little.
@export_enum("strength", "dexterity", "intelligence", "luck") var primary_stat := "strength"
@export_enum("strength", "dexterity", "intelligence", "luck") var secondary_stat := "dexterity"
## The lowest hit as a fraction of the highest (MapleStory's mastery).
@export_range(0.1, 0.95) var mastery := 0.6

@export_group("Growth")
@export var base_hp := 50
@export var hp_per_level := 14
@export var base_mp := 20
@export var mp_per_level := 6
## Ability Points gained per level, spent in the stats window.
@export var ap_per_level := 5

@export_group("New character")
@export var starting_stats: StatBlock
## Worn from the start.
@export var starting_gear: Array[EquipDef] = []
## Put in the inventory at the start; each entry is rolled once (use chance 1).
@export var starting_items: Array[DropEntry] = []
