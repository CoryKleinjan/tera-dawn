class_name JobDef
extends Resource
## A job (class): which stats drive its damage, how HP and MP grow, what a new character
## of this job starts with, and how a character advances into it. Add a job by saving a
## JobDef in data/jobs/.
##
## Everyone starts as a Beginner (`advances_from` empty). A job instructor (an NpcDef that
## `instructs` this job) advances a character from `advances_from` at `advance_level`.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## The job line it belongs to (warrior, archer, mage, thief, pirate, beginner). Gear that
## names a line can be worn by every job in it.
@export var family: StringName
## The job's colour, for the places that show jobs (the hero now wears his job's gear instead).
@export var tint := Color.WHITE
## The stat that drives damage (STR for warriors) and the one that helps a little.
@export_enum("strength", "dexterity", "intelligence", "luck") var primary_stat := "strength"
@export_enum("strength", "dexterity", "intelligence", "luck") var secondary_stat := "dexterity"
## Hit with whichever of STR, DEX, INT or LUK is highest instead of `primary_stat`, so any
## build works (the Beginner, who hasn't picked a path yet).
@export var uses_best_stat := false
## The lowest hit as a fraction of the highest (MapleStory's mastery).
@export_range(0.1, 0.95) var mastery := 0.6

@export_group("Growth")
@export var base_hp := 50
@export var hp_per_level := 14
@export var base_mp := 20
@export var mp_per_level := 6
## Ability Points gained per level, spent in the stats window.
@export var ap_per_level := 5
## Skill Points gained per level, spent in the skill window.
@export var sp_per_level := 3

@export_group("Advancement")
## The job you advance from (empty: you start as this job).
@export var advances_from: StringName
@export var advance_level := 10
## Base stats (STR, DEX, INT, LUK, before gear) needed to advance.
@export var advance_requirements: StatBlock
## Items handed over when advancing (each gives `min_amount`): the job's basic weapon (the
## first weapon here is worn right away, see Character.advance), its ammo and potions.
## Better weapons only drop.
@export var advance_gifts: Array[DropEntry] = []
## Skill Points handed over when advancing, so the new job has something to learn right away.
@export var advance_sp := 0

@export_group("New character")
@export var starting_stats: StatBlock
## Worn from the start.
@export var starting_gear: Array[EquipDef] = []
## Put in the inventory at the start; each entry is rolled once (use chance 1).
@export var starting_items: Array[DropEntry] = []
## The outfit pieces the character creator offers a new character of this job, any kinds of
## gear; the creator lets them pick one of each kind (see NewCharacter).
@export var creator_gear: Array[EquipDef] = []

## The stats behind weapon damage for these `total` stats: [main, helper]. Usually
## `primary_stat` and `secondary_stat`; with `uses_best_stat` the main one is the highest
## (`primary_stat` wins ties) and the helper is `secondary_stat`, or `primary_stat` when
## the highest is the secondary one.
func damage_stats(total: StatBlock) -> Array[StringName]:
	var main := StringName(primary_stat)
	var helper := StringName(secondary_stat)
	if uses_best_stat:
		for stat in StatBlock.BASE:
			if total.value(stat) > total.value(main):
				main = stat
		if helper == main:
			helper = StringName(primary_stat)
	return [main, helper]

## What advancing takes, as readable lines ("Level 10", "35 STR").
func requirement_lines() -> PackedStringArray:
	var out := PackedStringArray(["Level %d" % advance_level])
	if advance_requirements:
		for stat in StatBlock.BASE:
			var n := advance_requirements.value(stat)
			if n > 0:
				out.append("%d %s" % [n, StatBlock.LABELS[stat]])
	return out

## "Apprentice Wand, 30 Blue Potion": the advance gifts, for the message on advancing.
func gifts_text() -> String:
	var parts := PackedStringArray()
	for g in advance_gifts:
		if g.item:
			parts.append(g.item.display_name if g.item is EquipDef or g.min_amount <= 1 else "%d %s" % [g.min_amount, g.item.display_name])
	return ", ".join(parts)

## Whether this is a starting job (Beginner): one you don't advance into.
func is_starting_job() -> bool:
	return advances_from == &""

## The jobs a character of job `from` can advance into, by level and then name, so lists
## of them read the same everywhere.
static func paths_from(from: StringName) -> Array[JobDef]:
	var out: Array[JobDef] = []
	for j: JobDef in Content.jobs.values():
		if j.advances_from == from and from != &"":
			out.append(j)
	out.sort_custom(func(a: JobDef, b: JobDef) -> bool:
		return a.display_name < b.display_name if a.advance_level == b.advance_level else a.advance_level < b.advance_level)
	return out

## The lowest level at which a character of job `from` can advance into another job, or
## a level nobody reaches when no job advances from it.
static func first_advance_level(from: StringName) -> int:
	var paths := paths_from(from)
	return paths[0].advance_level if not paths.is_empty() else 1 << 30

## "Warrior: Level 10, 35 STR", for lists of the paths open to a Beginner.
func path_line() -> String:
	return "%s: %s" % [display_name, ", ".join(requirement_lines())]
